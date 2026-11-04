import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MusicDatabase's sharing server serves HTTPS with its own certificate (made by the server
/// itself, not signed by anyone the phone knows), on the home network and the VPN alike. The
/// phone trusts it the way SSH trusts a host: the first time, the user compares a short code
/// with the one MusicDatabase shows and says it's theirs ([pin]); from then on a server showing
/// another certificate is refused. A certificate the system already trusts (a real one) needs
/// no pin, so a server behind a proper certificate works as any website does.
/// [ADR 0015](../../../docs/decisions/0015-server-https.md).
class ServerTrust {
  ServerTrust._();

  static final instance = ServerTrust._();

  static const _prefsKey = 'server_certificate_pins';

  final _pins = <String>{};

  /// Reads the pinned certificates; before it, no own certificate is trusted.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _pins
      ..clear()
      ..addAll(prefs.getStringList(_prefsKey) ?? const []);
  }

  bool isPinned(X509Certificate certificate) =>
      _pins.contains(certificateFingerprint(certificate));

  /// The user said [certificate] is their server's: trusted from now on, on every address.
  Future<void> pin(X509Certificate certificate) async {
    _pins.add(certificateFingerprint(certificate));
    await _save();
  }

  /// Forgets every pinned certificate (Źródło bazy danych › "Zapomnij certyfikat serwera"):
  /// the next connection asks again.
  Future<void> forgetAll() async {
    _pins.clear();
    await _save();
  }

  bool get hasPins => _pins.isNotEmpty;

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _pins.toList()..sort());
  }

  /// An HttpClient for MusicDatabase's server: certificates the system trusts as usual, plus
  /// the pinned ones. Use it for every request to the server — a bare `HttpClient()` refuses
  /// its certificate.
  HttpClient client() =>
      HttpClient()
        ..badCertificateCallback = (certificate, _, _) => isPinned(certificate);

  /// What the server at [base] shows: [CertificateTrusted] for plain HTTP, a certificate the
  /// system trusts or a pinned one, [CertificateUnknown] with the certificate to ask about, or
  /// [CertificateUnreachable] when nothing answered.
  Future<CertificateCheck> check(
    Uri base, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    X509Certificate? unknown;
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (certificate, _, _) {
        if (isPinned(certificate)) return true;
        unknown = certificate;
        return false;
      };
    try {
      final request = await client.headUrl(base).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return const CertificateTrusted();
    } catch (_) {
      final certificate = unknown;
      return certificate == null
          ? const CertificateUnreachable()
          : CertificateUnknown(certificate);
    } finally {
      client.close(force: true);
    }
  }
}

sealed class CertificateCheck {
  const CertificateCheck();
}

class CertificateTrusted extends CertificateCheck {
  const CertificateTrusted();
}

class CertificateUnreachable extends CertificateCheck {
  const CertificateUnreachable();
}

class CertificateUnknown extends CertificateCheck {
  const CertificateUnknown(this.certificate);

  final X509Certificate certificate;

  /// The code to compare with MusicDatabase's ([certificateCode]).
  String get code => certificateCode(certificate);
}

/// SHA-256 of the certificate (DER), lowercase hex — what [ServerTrust] pins.
String certificateFingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();

/// The short code a person compares: the SHA-256 of the certificate (DER) in base32 (RFC 4648),
/// its first 12 characters in groups of 4 ("K7X2-9QPM-A3DF"). MusicDatabase's sharing server
/// prints the same (`certificate_code()` in `sharing_server.py`) — keep the two alike.
String certificateCode(X509Certificate certificate) =>
    codeOfDigest(sha256.convert(certificate.der).bytes);

String codeOfDigest(List<int> digest) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in digest) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5 && out.length < 12) {
      bits -= 5;
      out.write(alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
    if (out.length == 12) break;
  }
  final code = out.toString();
  return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}';
}

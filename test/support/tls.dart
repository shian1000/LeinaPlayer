import 'dart:io';

/// A self-signed certificate (`tls/cert.pem`, key `tls/key.pem`, made once with openssl, valid
/// for 100 years) standing in for MusicDatabase's own server certificate.
SecurityContext testServerContext() => SecurityContext()
  ..useCertificateChain('test/support/tls/cert.pem')
  ..usePrivateKey('test/support/tls/key.pem');

/// [certificateCode] of that certificate, worked out by hand (sha256 of the DER, base32).
const testCertificateCode = 'VMW7-ZEYD-JNLA';

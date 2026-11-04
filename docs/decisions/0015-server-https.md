# 0015 - MusicDatabase's server over HTTPS with its own, pinned certificate

## Status

Accepted (2026-11-04, owner's decision). The phone's side is built: `ServerTrust`
(`lib/src/data/server_trust.dart`), `ServerAudioSource` (`lib/src/playback/server_audio_source.dart`)
and the confirmation on Ustawienia › Serwer. MusicDatabase's side, the sharing server serving TLS
with a certificate it makes itself, is built in MusicDatabase at the same time.

## Context

[ADR 0002](0002-database-download.md) took plain HTTP, assuming the server is reached only over
the tailnet, where the VPN already encrypts the traffic. Since then the server also listens on
the home network (for a phone that isn't on the VPN), and the phone sends more than the public
catalog: the login password, its token, and the account's playlists, moods, saved songs, listens
and covers ([ADR 0006](0006-musicdatabase-login.md) onwards). On the home Wi-Fi all of that went
in the clear. Anyone else on that network could read it, or answer in the server's place.

The catalog itself (`music.db`, `tag.db`) is public anyway (the GitHub release,
[ADR 0014](0014-github-database-and-request-packages.md)). The account's data is not.

A certificate signed by a public authority needs a public domain name. The server has none on
the home network, and the owner doesn't want the app to depend on the VPN's own certificates.

## Decision

- The server serves HTTPS on every address it listens on, the home network and the VPN alike,
  with one certificate it makes for itself (MusicDatabase's `sharing_server.py`).
- The phone trusts that certificate the way SSH trusts a host. The first time an `https://`
  address is saved (or found on the Wi-Fi), the phone shows a short code: the certificate's
  SHA-256 in base32, the first 12 characters as `XXXX-XXXX-XXXX`. The owner compares it with the
  code MusicDatabase shows and confirms it ("Czy to Twój serwer?"). The certificate's SHA-256 is
  then pinned (`SharedPreferences`, `server_certificate_pins`) and trusted on every address. A
  server showing another certificate is refused (`HandshakeException`, worded on Serwer as
  "Nieznany certyfikat serwera"). "Zapomnij" on Serwer drops the pins for a new certificate.
- Every request to the server goes through `ServerTrust.instance.client()`. A certificate the
  system trusts works as before, so a server behind a real certificate needs no pin. Plain
  `http://` addresses still work, for servers that haven't switched.
- Android's player fetches an `AudioSource.uri` itself and would refuse the certificate, so a
  server file over HTTPS plays through `ServerAudioSource`, a just_audio `StreamAudioSource` that
  fetches the bytes with the pinned client, passing byte ranges on for seeking.
- An address typed without a scheme is `https://`. Looking for the server on the Wi-Fi takes the
  remote address's scheme (HTTPS when none is set) and accepts any certificate while probing,
  since it only reads the start of the public `music.db`. Whether to trust the server it finds is
  asked afterwards.

## Consequences

- An app version from before this decision can't reach a server serving HTTPS. Phone and server
  are updated together.
- The pin is the server's certificate itself, not a CA. A new certificate on the server means
  forgetting the old pin on every phone and confirming again.
- `StreamAudioSource` is marked experimental in just_audio. An update that changes it breaks
  streaming from the server over HTTPS, and `test/data/server_trust_test.dart` catches it.
- iOS: no change is needed for HTTPS with a pinned certificate. The plain-HTTP exception noted in
  ADR 0002 matters less now.

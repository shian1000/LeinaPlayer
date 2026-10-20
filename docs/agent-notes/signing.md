# Release signing

Android installs an update only when it is signed with the same key as the installed app; a
different key means uninstalling, which wipes everything the phone keeps. So every release
APK — the user's phones and the friends' copies from GitHub Releases — must be signed with the
one release key, for good.

- The key: `~/keys/leina-radio.jks` (PKCS12, alias `leina-radio`, made 2026-10-20), outside the
  repo, with a backup kept by the user elsewhere. Losing it = no more updates without a
  reinstall for everyone. Never commit it or its passwords.
- `android/key.properties` (git-ignored) points to it and holds the passwords;
  `android/app/build.gradle.kts` reads it into `signingConfigs.release`. Without the file
  (someone else's checkout) release builds fall back to the debug key so they still build,
  but `tool/build_release_apk.sh` refuses unless `ALLOW_DEBUG_KEY=1` — a debug-signed APK
  can't update one installed from a release. The key and `key.properties` are `chmod 600`.
- SHA-1 `D7:1B:8B:4C:8C:50:0D:6C:80:04:C5:07:5C:20:17:59:B7:9B:76:47` (4096-bit RSA, valid
  till 2126). It is registered with the Android OAuth client in Google Cloud, needed by
  "Utwórz na YouTube"'s Google sign-in ([`youtube.md`](youtube.md)). A self-built APK with
  another key needs its own SHA-1 there (or its own Google Cloud project).
- Until 2026-10-20 releases were signed with `~/.android/debug.keystore`; phones with such a
  build had to be reinstalled once.
- Read the SHA-1: `keytool -list -v -keystore ~/keys/leina-radio.jks -alias leina-radio`
  (keytool from Android Studio: `/snap/android-studio/current/jbr/bin/keytool`; there's none
  on PATH).

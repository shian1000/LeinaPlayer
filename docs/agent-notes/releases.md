# Releases and the update check

The APK that friends install comes from the GitHub releases of this repo; the app checks them
for a newer build (Ustawienia › Informacje i pomoc › Aktualizacje, `lib/src/data/app_updates.dart`).

## Making a release (owner, by hand)

1. Commit everything — a release is built from a commit, never from "+zmiany".
2. `tool/prepare_release.sh` (or the desktop shortcut "Przygotuj wydanie Leina Radio"): builds
   the universal APK unless the current one is fresh, then the split ones (Flutter makes no
   universal APK in a split build — two builds), all signed with the release key
   ([`signing.md`](signing.md)); copies `build/release/LeinaRadio-<version>+<build>.apk`
   (universal, ~69 MB) and `…-arm64-v8a.apk` (~25 MB) and prints `TAG=<version>+<build>`.
3. On GitHub: new release with **exactly that tag** (`1.0.0+58`), **both APKs** attached, and
   the notes ("Co nowego") in the description — the app shows them in its dialog. Not a draft
   or pre-release: the app reads `releases/latest`. (Owner's choice: arm64 + universal, no armv7.)

## Version numbers

- Android's `versionCode` = build number × 10 + variant (`android/app/build.gradle.kts`,
  `androidComponents.onVariants`): 1 armeabi-v7a, 2 arm64-v8a, 4 x86_64, 9 universal.
  `force-version-code-ignoring-abi=true` in `android/gradle.properties` stops Flutter's own
  scheme (ABI × 1000 + build), under which a universal APK could never replace a split one and
  codes collide at 1000 builds. With ours a newer build always wins, either way between split
  and universal; the universal one also replaces a split one of the same build. Builds before
  this scheme (≤ 67) were plain build numbers, all below it.
- So `versionCode` isn't the build number: the app reads it from `BUILD_NUMBER`
  (`--dart-define` from `tool/build_release_apk.sh`), else `versionCode ~/ 10`
  (`buildNumberOf` in `app_updates.dart`); the last digit tells "Zainstalowana wersja: mała /
  duża" in Informacje i pomoc (`isUniversalApk`).

The owner does GitHub writes himself; agents prepare the files and give the steps.

## The update check

- Build-time only: `tool/release.env` (git-ignored; `tool/release.env.example`) sets
  `UPDATE_REPO=<owner>/<repo>`, passed by `tool/build_release_apk.sh` as a `--dart-define`.
  Without it (someone else's build) nothing is checked or shown — their APK, signed with
  another key, couldn't install the owner's releases anyway. The same file holds
  `GOOGLE_WEB_CLIENT_ID` ("Utwórz na YouTube", [`youtube.md`](youtube.md)); only the keys
  listed in `tool/build_release_apk.sh` are passed on.
- Once a day on start / return to the app (switch in Informacje i pomoc, on by default) and
  "Sprawdź teraz": `GET https://api.github.com/repos/<repo>/releases/latest` (no token; the
  anonymous limit of 60 requests an hour is plenty). The tag's `+<build>` is compared with the
  installed build number (= `git rev-list --count`, `tool/build_info.sh`); the APK offered is
  the one with this phone's ABI in its name (`Abi.current()`), else the one with no ABI in its
  name (universal). A tag without the build or a release with no APK this phone can install is
  ignored; 404 (no release yet) isn't an error.
- A newer one is offered once in a dialog at start (`AppShell`); "Później" stops the dialog for
  that build, it stays in Informacje i pomoc. "Pobierz" opens the APK's URL in the browser,
  which downloads it and hands it to Android's installer (no install permission in the app —
  owner's choice). Updating keeps the app's data as long as the signing key is the same.
- Widget tests: `testWidgets` answers every `HttpClient` request with 400 — tests talking to a
  local fake server set `HttpOverrides.global = null` (see `test/update_screen_test.dart`).

# Releases and the update check

The APK that friends install comes from the GitHub releases of this repo; the app checks them
for a newer build (Ustawienia › Informacje i pomoc › Aktualizacje, `lib/src/data/app_updates.dart`).

## Making a release (owner, by hand)

1. Commit everything — a release is built from a commit, never from "+zmiany".
2. `tool/prepare_release.sh`: builds the APK unless the current one is fresh (signed with the
   release key, [`signing.md`](signing.md)), copies it to
   `build/release/LeinaRadio-<version>+<build>.apk` and prints `TAG=<version>+<build>`.
3. On GitHub: new release with **exactly that tag** (`1.0.0+58`), the APK attached, and the
   notes ("Co nowego") in the description — the app shows them in its dialog. Not a draft or
   pre-release: the app reads `releases/latest`.

The owner does GitHub writes himself; agents prepare the files and give the steps.

## The update check

- Build-time only: `tool/release.env` (git-ignored; `tool/release.env.example`) sets
  `UPDATE_REPO=<owner>/<repo>`, passed by `tool/build_release_apk.sh` as a `--dart-define`.
  Without it (someone else's build) nothing is checked or shown — their APK, signed with
  another key, couldn't install the owner's releases anyway. The same file is the place for
  other build-time pointers to the owner's services (sharing checklist 6.1: the Google client id).
- Once a day on start / return to the app (switch in Informacje i pomoc, on by default) and
  "Sprawdź teraz": `GET https://api.github.com/repos/<repo>/releases/latest` (no token; the
  anonymous limit of 60 requests an hour is plenty). The tag's `+<build>` is compared with the
  installed build number (= `git rev-list --count`, `tool/build_info.sh`); a tag without it or
  a release without an `.apk` asset is ignored; 404 (no release yet) isn't an error.
- A newer one is offered once in a dialog at start (`AppShell`); "Później" stops the dialog for
  that build, it stays in Informacje i pomoc. "Pobierz" opens the APK's URL in the browser,
  which downloads it and hands it to Android's installer (no install permission in the app —
  owner's choice). Updating keeps the app's data as long as the signing key is the same.
- Widget tests: `testWidgets` answers every `HttpClient` request with 400 — tests talking to a
  local fake server set `HttpOverrides.global = null` (see `test/update_screen_test.dart`).

# Leina Radio

A music player and library app for Android, built with Flutter. It plays the music on your
phone and works with [MusicDatabase](https://github.com/shian1000/LeinaMusicDatabase) — a personal
music library and metadata tool — for its catalog of songs, artists, albums and moods.

The app's interface is in Polish. It is a private project, shared with friends; it is not and
will not be published in any app store.

## Install

1. Open the [latest release](https://github.com/shian1000/LeinaPlayer/releases/latest) on your
   phone and download one of the APKs:
   - **`LeinaRadio-<version>-arm64-v8a.apk`** (~25 MB) — for almost every phone made in the last
     years (64-bit). Take this one.
   - **`LeinaRadio-<version>.apk`** (~69 MB) — works on any Android phone (it carries builds for
     three kinds of processor). Use it if the small one doesn't install.
2. Open the downloaded file. The first time, Android asks to allow installing apps from your
   browser.
3. Updates: the app checks for a new release once a day and offers it (Ustawienia › Informacje i
   pomoc › Aktualizacje). An update keeps your data. You can move from the large APK to the small
   one or back at any time.

Requires Android 7.0 or newer.

## What it does

- **Your music** — scans folders on the phone and plays the files; a queue, shuffle, repeat,
  crossfade, a sleep timer, background playback with notification controls.
- **The MusicDatabase catalog** — downloaded once a day (from your own MusicDatabase server, or
  the public copy published on GitHub) and searched on the phone, offline.
- **Library** — playlists made on the phone or imported from YouTube and Spotify links, moods,
  folders, liked songs and songs saved for later, dynamic playlists (saved searches).
- **Discovery** — a song's radio, Odkrywaj (one song at a time), browsing by mood, genre, decade,
  language and country, recommendations on Home.
- **Listening stats** — top songs, artists and albums, highlights of the week and yearly /
  seasonal summaries, computed on the phone.
- **Corrections for MusicDatabase** — the phone notices dead links and missing songs, and you
  can correct a song's details; reports go to your MusicDatabase server, or as a `.zip` package
  you send to its owner.
- **With a MusicDatabase account** (optional) — your library and stats sync between phones and
  survive a reinstall.
- Album covers, lyrics, and short explanations of some settings on a long press.

The app works without any server: the catalog then comes from GitHub and everything you add
stays on the phone.

## Privacy

No ads, no analytics, no crash reporting. The app only connects to the internet when a feature
you use needs it, and almost every automatic connection can be switched off. Details:
[PRIVACY.md](PRIVACY.md), and in the app: Ustawienia › Prywatność i połączenia.

## Building

### Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) stable (built with 3.47; Dart ≥ 3.13).
- Android SDK with platform 37, and a JDK 17+ (Android Studio's bundled one works).
- ~3 GB of free RAM for a release build (the Gradle heap is capped in
  `android/gradle.properties`).

### Debug build

```bash
flutter pub get
flutter run
```

### Release build

Release APKs are built with a script, not a bare `flutter build apk` — it numbers the build and
passes the build-time settings:

```bash
tool/build_release_apk.sh                  # universal APK
tool/build_release_apk.sh --split-per-abi  # one APK per processor
```

Output: `build/app/outputs/flutter-apk/`. The build number is the git commit count; Android's
`versionCode` is that × 10 + the APK's processor variant (see
[`docs/agent-notes/releases.md`](docs/agent-notes/releases.md)).

**Signing.** Updates only install over an APK signed with the same key, so use one key for good:

```bash
keytool -genkeypair -v -keystore ~/keys/leina-radio.jks -alias leina-radio \
  -keyalg RSA -keysize 4096 -validity 36500
```

Then create `android/key.properties` (git-ignored):

```properties
storeFile=/home/<you>/keys/leina-radio.jks
keyAlias=leina-radio
storePassword=<password>
keyPassword=<password>
```

Back up the key and its password — losing it means your users can't update without
uninstalling. Without `key.properties` the script refuses to build; `ALLOW_DEBUG_KEY=1` builds
with the debug key anyway (fine for trying it out, not for handing out).

**Build-time settings.** Copy `tool/release.env.example` to `tool/release.env` (git-ignored):

- `UPDATE_REPO=<owner>/<repo>` — the GitHub repository whose releases carry *your* APKs. Leave it
  unset unless you publish your own releases: an APK signed with another key can't install the
  original author's.
- `GOOGLE_WEB_CLIENT_ID` — only for "Utwórz na YouTube" (making a YouTube playlist from a library
  playlist). Without it that button is left out. To get one, in your own
  [Google Cloud](https://console.cloud.google.com) project:
  1. enable **YouTube Data API v3**;
  2. set up the **OAuth consent screen** (testing mode is fine) and add your Google account as a
     test user;
  3. create an **Android** OAuth client with the package name `com.shian1000.music_database_app`
     and the SHA-1 of *your* signing key
     (`keytool -list -v -keystore ~/keys/leina-radio.jks -alias leina-radio`);
  4. create a **Web** OAuth client — its client id is `GOOGLE_WEB_CLIENT_ID`.

**Making a release** (the steps the author follows): `tool/prepare_release.sh` builds the
universal and arm64 APKs from a clean commit and prints the tag (`<version>+<build>`); a GitHub
release with exactly that tag and both APKs is what the app's update check reads.

### Tests

```bash
flutter analyze
flutter test
```

## Running your own MusicDatabase server

Optional. See [LeinaMusicDatabase](https://github.com/shian1000/LeinaMusicDatabase); in the app,
enter its address under Ustawienia › Serwer.

## Libraries

The full list of libraries the app uses, with their licences, is in the app: Ustawienia ›
Informacje i pomoc › Licencje bibliotek.

## For contributors

The code and its conventions are described in [`AGENTS.md`](AGENTS.md) (written for AI coding
agents, readable for people) and [`docs/`](docs/index.md); every screen and menu element is in
[`docs/menu-map.md`](docs/menu-map.md).

## Licence

[GNU GPL v3](LICENSE) — required by one of the libraries the app uses. Anyone who receives the
app is entitled to its source code under the same licence.

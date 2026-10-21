---
name: prepare-github-release
description: 'Get a new GitHub release of Leina Radio ready: check the repo is committed and pushed, build the universal and arm64 APKs with tool/prepare_release.sh, verify them (versionCode, signature, CPU), draft the "What''s new" notes in English from the commits since the previous release, give the owner the prefilled release link and the files to attach, then — once the owner says it is published — check it the way the app''s update check reads it. Trigger on "/prepare-github-release", "przygotuj wydanie", "przygotuj buildy na githuba", "nowe wydanie", "wydaj nową wersję", "prepare a release", "release builds for GitHub". The owner publishes on GitHub himself; this skill never creates releases, tags or pushes. Not for sharing a test build over Tailscale — that is share-build-tailscale.'
---

# Prepare a GitHub release

The owner does every write on GitHub himself (creating the release, uploading). This skill
prepares the files and the text, and checks the result. Background:
[`docs/agent-notes/releases.md`](../../../docs/agent-notes/releases.md) (tag format, versionCode
scheme, the update check) and [`signing.md`](../../../docs/agent-notes/signing.md).

Answer the owner in Polish; the release notes themselves are in **English** (everything on GitHub
is — user's rule).

## Step 1 — Is the repo ready?

```bash
git status --short
git fetch -q --tags origin
git rev-list --left-right --count main...origin/main
tool/build_info.sh
```

- Uncommitted changes in `lib/`, `android/` or the pubspec files → `prepare_release.sh` refuses
  ("+zmiany"). Tell the owner and give a commit command; don't commit yourself.
- `main` ahead of `origin/main` → ask the owner to push first: the GitHub release is tagged on
  `main`, so the release's source must be on GitHub.
- `tool/build_info.sh` prints the build number the release gets; the tag is
  `<version from pubspec.yaml>+<build>`, e.g. `1.0.0+72`.
- `tool/release.env` and `android/key.properties` must exist (both git-ignored); without them the
  script refuses — say which is missing.

## Step 2 — Build (two builds, ~10–15 min)

Memory first, as in `run-on-physical-phone` Step 2b (`free -m`; stop leftover Gradle daemons;
below 2500 MB available ask the owner before building). Then, in the background:

```bash
tool/prepare_release.sh
(cd android && JAVA_HOME=/snap/android-studio/current/jbr ./gradlew --stop)
```

It prints `TAG=`, `APK_UNIVERSAL=`, `APK_ARM64=`, `COMMIT=`. The owner can also run it from the
desktop shortcut "Przygotuj wydanie Leina Radio" — never both at once (two Gradle builds don't fit
in memory).

## Step 3 — Verify the APKs

```bash
A=~/Android/Sdk/build-tools/36.0.0
for f in build/release/LeinaRadio-<tag>*.apk; do
  $A/aapt dump badging "$f" | head -1 | grep -o "versionCode='[0-9]*'"
  unzip -l "$f" | grep -o 'lib/[a-z0-9_-]*/libapp.so' | cut -d/ -f2 | tr '\n' ' '
  JAVA_HOME=/snap/android-studio/current/jbr PATH=/snap/android-studio/current/jbr/bin:$PATH \
    $A/apksigner verify --print-certs "$f" 2>/dev/null | grep SHA-1
done
```

Expect: universal `versionCode` = build × 10 + 9 with three ABIs; arm64 = build × 10 + 2 with
`arm64-v8a` only; both signed with SHA-1 `d7:1b:8b:…:76:47` (`signing.md`). Anything else — stop
and report.

## Step 4 — Draft "What's new"

From the commits since the previous release:

```bash
prev=$(git tag --sort=-v:refname | head -1)   # the last published release's tag
git log --format='%s' "$prev"..HEAD
```

Write 3–8 short English bullets for **users** (what they'll notice), not for developers:

- leave out docs, tests, skills, build scripts, refactors and internal fixes nobody sees;
- **never mention playing audio from YouTube, NewPipe or youtube_explode** (owner's rule for
  public GitHub texts — the add-ons will document them; checklist 8.3);
- name screens by their Polish UI labels where it helps ("Ustawienia › Prywatność i połączenia");
- no private data (addresses, paths, account names).

The app shows this text in its "Dostępna nowa wersja" dialog.

## Step 5 — Hand over to the owner

Give, in Polish:

1. the prefilled link — `+` must be `%2B`:
   `https://github.com/shian1000/LeinaPlayer/releases/new?tag=<version>%2B<build>&title=Leina%20Radio%20<version>%2B<build>`
2. the two files to attach, with full paths:
   `build/release/LeinaRadio-<tag>.apk` (large, any phone) and
   `build/release/LeinaRadio-<tag>-arm64-v8a.apk` (small, 64-bit phones);
3. the "What's new" text in a code block, ready to paste;
4. the checklist: tag exactly `<tag>`, target `main`, **both** APKs, not a pre-release, "Set as the
   latest release" on, Publish.

## Step 6 — After the owner publishes: check it

```bash
curl -s -H "Accept: application/vnd.github+json" -H "User-Agent: LeinaRadio" \
  https://api.github.com/repos/shian1000/LeinaPlayer/releases/latest
```

Check: `tag_name` is the new tag, not draft / pre-release, both `.apk` assets present; an arm64
phone gets the asset with `arm64-v8a` in its name and any other phone the one without an ABI
(the app's rule, `AppRelease.fromGitHub`); download both public URLs (`curl -sL`, `%2B` in the
path) and compare SHA-256 with the local files. Report in Polish; if the notes came out with
CRLF line ends that's fine (the app normalises them).

Then tick the release in `docs/udostepnienie-todo.txt` if that checklist still has a matching
item.

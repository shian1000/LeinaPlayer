# 0004 - GPLv3, private use only, never in an app store

## Status

Accepted (2026-10-10)

## Context

YouTube playback on Android is planned through NewPipeExtractor (the library behind NewPipe),
which is GPLv3. Linking it makes the whole app GPLv3. Separately, downloading or playing YouTube
audio outside YouTube's official player breaks YouTube's terms and Google Play's policies — the
reason NewPipe itself is not on Google Play.

## Decision

- The app is licensed under GPLv3 (`LICENSE` in the repo root).
- It is for private use. It may be given for free to a small circle of friends, with access to
  the source code (the public repo, https://github.com/shian1000/MusicDatabaseApp).
- It is never published in Google Play or any other app store.
- "Ustawienia › Informacje i pomoc" (`about_screen.dart`) states all of this, as a reminder for
  the owner.

## Consequences

- Any library added must be GPLv3-compatible.
- YouTube support can break whenever YouTube changes; fixing it means a new APK. Accepted.

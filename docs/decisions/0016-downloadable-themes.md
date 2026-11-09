# 0016 - Themes downloaded from GitHub

## Status

Accepted (2026-11-09).

## Context

Themes were compiled into the app, so a new or corrected one needed a new release. A theme is
almost only data: colours, a few look switches and a font.

## Decision

- Lain, Cyberpunk and Redesign move to a public repository, `shian1000/LeinaThemes`
  (`index.json`, `themes/<id>/theme.json`, fonts beside it), read over
  `raw.githubusercontent.com`. Ustawienia › Wygląd › "Pobierz motyw" lists, downloads, updates
  and removes them.
- Dummify (dark and light) stays built in: the first start without a connection, a broken file
  or a missing repository must still leave the app with a look. It is now the default dark
  theme of a new install.
- A theme file is only data, checked when read, never code; ids and file names are restricted so
  they can't leave the folder. `format` lets an old app leave out a theme it can't read.
- A phone that had a moved theme chosen (or stayed on the old default, Lain) downloads it once
  by itself on start, showing Dummify until it arrives. It's the only automatic connection and
  ends when the theme is there; it retries on the next start without a connection.

## Consequences

- The ~1.2 MB Rajdhani font leaves the APK; its licence comes with the theme and shows in
  Licencje bibliotek.
- A look `AppPalette`'s switches can't express (a new corner shape) still needs an app release.
- `LeinaThemes` has to be public on GitHub before a build with this change reaches anyone.

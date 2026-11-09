# Theming

- A theme is an `AppThemeDef`: a name, an `AppPalette` and an optional `fontFamily`. Only Dummify
  (dark and light) is built in (`lib/src/theme.dart`), so the app always has a look; the rest are
  downloaded ([ADR 0016](../decisions/0016-downloadable-themes.md)).
- A downloaded theme's `theme.json` is kept whole in `shared_preferences`
  (`appearance.downloaded_themes`, so it's read before the first frame and is in the backup), its
  fonts in `<support>/theme_fonts/<id>__<file>`, loaded with `FontLoader` when the theme is used.
  It's only data (`ThemeFile.parse`, `data/theme_repository.dart`): a new look a theme can't get
  from `AppPalette`'s switches needs an app change and a higher `format`. `buildAppTheme()` turns it into `ThemeData` and attaches the palette as a
  `ThemeExtension`.
- Screens never hard-code colours, corner radii or pill/stadium/circle shapes. They use
  `context.palette` (`accent`, `textSecondary`, `colorForSeed()`, `radius()`, `pillShape`,
  `boxShape()`, `buttonShape`, `outlineSide`…) plus the defaults `ThemeData` already applies (list tiles, app bars,
  dividers, snackbars, sheets, switches). A literal `Colors.white` in a screen will look wrong in
  other themes.
- `ThemeController` (`lib/src/theme_controller.dart`) sits above `MaterialApp` and holds the
  chosen light theme, dark theme, the "Przełącz na tryb ciemny" switch and "Systemowe
  przełączanie trybu ciemnego"; `ThemeScope.of(context)` reads/sets them. `MaterialApp` gets
  `theme` (light), `darkTheme` (dark) and `themeMode` (system / dark / light) from it. All of it
  is saved in `shared_preferences` (`appearance.*` keys) and loaded in `main()` before the first
  frame, so the app doesn't flash the default theme on start.
- A light and a dark theme may share a name (both are "Dummify"): names are unique only within
  `lightThemes` / `darkThemes`. Status-bar icon colour follows the active brightness via an
  `AnnotatedRegion` in `MaterialApp.builder`, since tab screens have no AppBar to set it.
- `AppPalette.lerp` switches in one step instead of interpolating, because themes also differ in
  shape and font.

## Themes

Dummify's two variants are here; Lain, Cyberpunk and Redesign live in the
`shian1000/LeinaThemes` repository, with the ids that were their saved names (a phone that had
one picked downloads it by itself on start, showing Dummify until then — `_restoreMissing`).

- **Dummify** (dark) — modelled on the reference app (black/grey, green accent, rounded).
- **Dummify** (light, `dummifyLightTheme`) — white/light grey with near-black text and a darker
  green accent (`#14A04A`, readable as text on white).
- **Redesign** (light, `redesignLightTheme`) — after the light Home of Juxtopposed's Spotify
  redesign (`docs/ideas/`): soft grey page (`#F2F2F0`), lighter grey cards and chips, deep green
  accent (`#138A43`).
- **Lain** (dark, the default dark theme — user's choice) — after Serial Experiments Lain fan desktops and retro terminal/HUD UIs (user's Pins
  folder): near-black navy, cyan accent, steel-blue window chrome (`outline`), square corners
  (`rounded: false`), section headings as window title bars with "×" (`panelHeaders: true`), and
  Android's built-in `monospace` font (nothing bundled).
- **Cyberpunk** (dark) — after red/cyan cyberpunk HUD phone wallpapers (user's Pins folder; the
  user picked this palette over black/yellow and green ones): near-black page, red frames
  (`outline`) and subtitles (`textSecondary`), cyan accent, `chamfered: true` — `ChamferedBorder`
  cuts the top-left and bottom-right corners of chips, cards, buttons, dialogs and sheets, and
  cards (`boxShape`) get a small accent triangle in the top-right corner; what's clipped with
  `radius()` (covers) stays square. Section headings are a red tab with a cut corner and a line
  to the edge; `uppercaseTitles` puts tab titles in capitals (song, artist and playlist names
  keep their spelling — user's choice; AppBar titles aren't uppercased). Font: Rajdhani
  (in the theme's folder of `LeinaThemes`, SIL OFL, its licence shown in Licencje bibliotek through
  `ThemeController.licenses`); it has Latin Extended but no Cyrillic, which falls back to the system font. The
  native "Otwórz w…" sheet only knows `monospace`, so there it uses the system font.

## Adding a theme

1. In `LeinaThemes`, add `themes/<id>/theme.json` (and fonts with their licence beside it) and
   an entry in `index.json`; raise `version` on every change, so phones offer the update.
2. Fill every palette field (`rounded`, `chamfered`, `panelHeaders`, `uppercaseTitles` are
   optional switches); `coverColors` needs at least two entries (the picker previews the
   first two). Colours are `#RRGGBB` or `#AARRGGBB`.
3. Check the Wygląd picker preview and the main screens on the phone; wide fonts may need
   `FittedBox`/ellipsis in tight spots (see the quick tiles in `settings_screen.dart`).

# Theming

- A theme is an `AppThemeDef` in `lib/src/theme.dart`: a name, an `AppPalette` and an optional
  `fontFamily`. `buildAppTheme()` turns it into `ThemeData` and attaches the palette as a
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
  (`assets/fonts/rajdhani/`, SIL OFL, its licence registered in `main()` for Licencje
  bibliotek); it has Latin Extended but no Cyrillic, which falls back to the system font. The
  native "Otwórz w…" sheet only knows `monospace`, so there it uses the system font.

## Adding a theme

1. Add a `const AppThemeDef(...)` in `theme.dart` and append it to `darkThemes`, or — with
   `brightness: Brightness.light` — to `lightThemes`.
2. Fill every palette field (`rounded`, `chamfered`, `panelHeaders`, `uppercaseTitles` are
   optional switches); `coverColors` needs at least two entries (the picker previews the
   first two).
3. Check the Wygląd picker preview and the main screens on the phone; wide fonts may need
   `FittedBox`/ellipsis in tight spots (see the quick tiles in `settings_screen.dart`).

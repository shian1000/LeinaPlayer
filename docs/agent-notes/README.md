# Agent notes

- [`covers.md`](covers.md) — album covers: sources, matching, rate limits, the cover cache,
  filters, avoiding placeholder flashes, the MusicDatabase hand-off.
- [`local-library.md`](local-library.md) — phone library scan, matching, `local.db`, search
  availability, playback order, background playback.
- [`playlists.md`](playlists.md) — Biblioteka playlists: tables, YouTube and Spotify import,
  recognising songs, videos YouTube removed, searching YouTube/Spotify playlists and previews,
  Spotify albums and track links, sharing playlists and songs.
- [`theming.md`](theming.md) — how themes work and how to add one.
- [`ui-sizing.md`](ui-sizing.md) — calibrated font sizes and spacing, no screen-size scaling.
- [`youtube.md`](youtube.md) — YouTube search methods, lite matcher + benchmark, NewPipe playback,
  remembered matches, "not found" and removed videos, server-wins rule, the audio cache, links
  given to the app and the native "Otwórz w…" sheet with "Zapisz na później".

Add one short file per non-obvious subsystem here as the app grows (e.g. how the
backend client is structured, caching behavior, platform-specific quirks) — not a running log of
changes, just what a future agent would need to not rediscover from scratch.

# Handoff for the MusicDatabase agent: Latin forms of names in other alphabets

**Status (2026-10-14):** done on both sides. MusicDatabase answered in its
`docs/handoffs/latin-names-for-musicdatabaseapp.md`: migration `0011_latin_names.sql` adds the
columns as asked (they reach the shared music.db once MusicDatabase has been started), the three
pairs are in `FIELDS`. Differences worth knowing on the phone: a one-song single's album
(`albums.type = 'single'`) always copies its song's `title_latin`; a correction of a title or
name keeps the existing Latin form (and the automatic pass leaves it for review); on an artist
merge with two different forms the dropped one goes to `synonyms`. Most rows stay NULL until the
owner fills them in (Manage database › "Fill in Latin forms of names in other alphabets").

Written by the MusicDatabaseApp agent (2026-10-14) for an agent working in `../MusicDatabase`.
Read MusicDatabase's own `AGENTS.md`, `docs/runbooks/database.md`, `docs/data-model.md` and
`docs/handoffs/field-corrections-for-musicdatabaseapp.md` first; their rules win over anything
here. When it's built, answer with a hand-off of your own in `docs/handoffs/` (like
`field-corrections-for-musicdatabaseapp.md`): what was built and anything that differs from this.

## Why

Many songs have titles, artists or albums in another alphabet: about 400 of the ~5700 songs are
in Cyrillic (Russian, Ukrainian, Belarusian, plenty marked `Unknown`), ~100 in Japanese (kana and
kanji), a few in Hangul, Greek, Georgian and Arabic. The owner wants the phone to show these
with a Latin form after them: **Кино (Kino)**, **Группа крови (Gruppa krovi)**.

An automatic transliteration on the phone was tried and dropped (the owner's decision): kanji
can't be read without a dictionary, Cyrillic depends on the language, and the result can't be
corrected. Instead **the Latin forms are stored in music.db, written by the owner**: in
MusicDatabase, or sent from the phone as a field correction for the owner to review.

## The columns

Three new nullable text columns (one migration, in MusicDatabase's usual way):

| Table | Column | Latin form of |
|---|---|---|
| `songs` | `title_latin` | `songs.title` |
| `artists` | `name_latin` | `artists.name` |
| `albums` | `title_latin` | `albums.title` |

- Free text, in whatever form the owner writes (trimmed; empty = NULL). No scheme is imposed.
  Earlier the owner picked English-style romanization for Russian/Ukrainian (Zemfira, Alyona,
  Zhuki) and MusicDatabase's own Lacinka for Belarusian — worth using for anything suggested
  automatically (see below), never for overwriting what the owner wrote.
- `songs.album` (the free-text name) gets **no** column: the phone shows the album's form via
  `songs.album_id` → `albums.title_latin`. A song without `album_id` shows no Latin album name.
- They must reach the shared `music.db` the phone downloads, like every other column.

## What the phone does with them (for reference — nothing to build for it)

- Reads the columns when they exist (older `music.db`s still work: nothing is shown).
- Shows "name (Latin form)" only when the name has a letter outside the Latin script and the
  form differs from it. Ustawienia › Wygląd › "Nazwy w alfabecie łacińskim" switches it off.
- An artist without `name_latin` falls back to the **first** entry of its `artists.synonyms`
  written only in Latin letters (`Бумбокс` with `familyboombox, Bumboks, BoomBox` shows
  `familyboombox` — setting `name_latin` fixes that). A title or album without a form shows
  nothing extra. A song with several artists shows the Latin label only if every non-Latin
  artist has a form.
- Song search on the phone also finds songs by these forms, and `name_latin` counts as one more
  name of the artist when matching phone files and YouTube videos (like a synonym).

## Requests from the phone: field corrections

The phone sends Latin forms as ordinary `field_corrections` rows (format unchanged — see the
app's `musicdatabase-field-corrections.md`). Three new `(table_name, column_name)` pairs:

| `table_name` | `column_name` | `new_value` |
|---|---|---|
| `songs` | `title_latin` | text or NULL |
| `artists` | `name_latin` | text or NULL |
| `albums` | `title_latin` | text or NULL |

- The phone offers them (in "Informacje o utworze", with the pencil) only for a song / artist /
  album whose name has a non-Latin letter, or whose form is already set.
- It offers them **even before music.db has the columns**; `old_value` is then NULL. They share
  request files with the other corrections. Today such a pair is an `UNSUPPORTED` case: the
  file's other corrections are answered as usual and the file stays in the inbox — so the owner's
  first Latin forms are already waiting there and must come up once the pairs are known.
- Everything else as for other text fields: reviewed in "Resolve new requests" (or saved by the
  automatic pass for a user with `apply_corrections`), the same stale / repeat / settled rules. `FIELD_LABELS` could read e.g.
  "song title in Latin letters", "artist's name in Latin letters", "album title in Latin letters".

## Things to handle in MusicDatabase

1. **The migration** adding the three columns, and the models in `datatables.py`.
2. **Editing them in MusicDatabase's own UI**, next to wherever a title, artist name or album
   title is edited today.
3. **Field corrections**: the three pairs in `FIELDS` (`inbox_field_corrections.py`).
4. **Merges and renames**: when two artists or albums are merged, keep a Latin form (the kept
   row's, else the other's). A renamed title/name keeps its form — it may need a look, the owner's
   call whether to flag it.
5. **Finding what's missing** (suggested, the owner's call): a way to list songs / artists /
   albums whose name has non-Latin letters and no form yet, so they can be filled in one go.
   `utils/youtube/transliteration.py` (Belarusian) and `utils/common/script_utils.py` could
   pre-fill a suggestion the owner accepts or edits — kanji have no automatic reading, so those
   stay for the owner to type. Nothing is stored without the owner accepting it.
6. Whether MusicDatabase's own search, matching or display also use the forms is up to it —
   the phone doesn't depend on that.

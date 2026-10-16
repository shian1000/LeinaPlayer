import 'dart:math';

import 'song_catalog.dart';
import 'text_normalizer.dart';

/// "Przejdź do radia utworu": [seed] first, then up to [size] songs of music.db like it, the most
/// alike first with a little chance mixed in. MusicDatabase has no radio of its own, so this is
/// the phone's lite guess from what music.db and tag.db know: a shared artist, genres, moods
/// ([moodsOf]), language, country and decade. A genre counts as shared when the names are the
/// same, and half as much when one has a word of the other ("indie pop" and "pop"). One artist takes at most [perArtist] places, so the
/// radio isn't the seed's discography. The same seed gives the same radio, so the list doesn't
/// change under the user while the screen rebuilds.
List<CatalogSong> songRadio(
  CatalogSong seed,
  Iterable<CatalogSong> songs, {
  Set<String> Function(int songId)? moodsOf,
  int size = 50,
  int perArtist = 8,
}) {
  final random = Random(seed.id);
  final seedArtists = _artistsOf(seed);
  final seedMoods = moodsOf?.call(seed.id) ?? const <String>{};
  final seedLanguage = _language(seed);
  final seedGenres = {for (final g in seed.genres) normalizeForSearch(g)};
  final seedGenreWords = {for (final g in seedGenres) ..._genreWords(g)};
  int score(CatalogSong song) {
    var points = 0;
    if (_artistsOf(song).any(seedArtists.contains)) points += 3;
    if (seedMoods.isNotEmpty) {
      points +=
          2 * (moodsOf!(song.id).intersection(seedMoods).length).clamp(0, 2);
    }
    if (seedGenres.isNotEmpty && song.genres.isNotEmpty) {
      var same = 0;
      var near = false;
      for (final genre in song.genres) {
        final name = normalizeForSearch(genre);
        if (seedGenres.contains(name)) {
          same++;
        } else if (_genreWords(name).any(seedGenreWords.contains)) {
          near = true;
        }
      }
      points += same > 0 ? 2 * same.clamp(0, 2) : (near ? 1 : 0);
    }
    if (seedLanguage != null && _language(song) == seedLanguage) points += 1;
    if (song.countries.any(seed.countries.contains)) points += 1;
    if (seed.year case final year?) {
      if (song.year case final other?) {
        if (other ~/ 10 == year ~/ 10) points += 1;
        if ((other - year).abs() <= 3) points += 1;
      }
    }
    return points;
  }

  final ranked = [
    for (final song in songs)
      if (song.id != seed.id)
        if (score(song) case final points when points >= 2)
          (song: song, rank: points + random.nextDouble() * 2),
  ]..sort((a, b) => b.rank.compareTo(a.rank));
  final perArtistCount = <String, int>{};
  final picked = <CatalogSong>[seed];
  for (final (:song, rank: _) in ranked) {
    if (picked.length > size) break;
    final artists = _artistsOf(song);
    if (artists.any((a) => (perArtistCount[a] ?? 0) >= perArtist)) continue;
    for (final artist in artists) {
      perArtistCount.update(artist, (n) => n + 1, ifAbsent: () => 1);
    }
    picked.add(song);
  }
  return picked;
}

Set<String> _artistsOf(CatalogSong song) => {
  for (final name in artistNamesOf(song.artistLabel)) normalizeForSearch(name),
};

String? _language(CatalogSong song) =>
    const {null, '', 'Unknown'}.contains(song.language) ? null : song.language;

/// The words of a normalized genre name that say something: "drum and bass" and "rhythm and
/// blues" aren't alike.
Iterable<String> _genreWords(String genre) =>
    genre.split(' ').where((w) => w.length > 2 && w != 'and');

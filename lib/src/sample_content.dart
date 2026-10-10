/// Static placeholder content shown until the app talks to MusicDatabase.
library;

const userName = 'Shian';

enum LibraryItemKind { playlist, album, artist }

class LibraryItem {
  const LibraryItem(this.title, this.kind, this.owner, {this.pinned = false});

  final String title;
  final LibraryItemKind kind;
  final String owner;
  final bool pinned;

  String get kindLabel => switch (kind) {
    LibraryItemKind.playlist => 'Playlista',
    LibraryItemKind.album => 'Album',
    LibraryItemKind.artist => 'Wykonawca',
  };
}

const likedSongsTitle = 'Polubione utwory';

const libraryItems = [
  LibraryItem(
    likedSongsTitle,
    LibraryItemKind.playlist,
    userName,
    pinned: true,
  ),
  LibraryItem('Przykładowa playlista A', LibraryItemKind.playlist, userName),
  LibraryItem(
    'Przykładowa playlista B',
    LibraryItemKind.playlist,
    'Inny użytkownik',
  ),
  LibraryItem('Przykładowy album', LibraryItemKind.album, 'Wykonawca A'),
  LibraryItem('Przykładowa playlista C', LibraryItemKind.playlist, userName),
  LibraryItem('Wykonawca B', LibraryItemKind.artist, ''),
  LibraryItem('Przykładowa playlista D', LibraryItemKind.playlist, userName),
  LibraryItem('Przykładowy album 2', LibraryItemKind.album, 'Wykonawca C'),
];

const searchDiscoverTags = ['#polskie indie', '#mod rock', '#dance rock'];

const searchCategories = [
  'Muzyka',
  'Podcasty',
  'Wydarzenia na żywo',
  'Przygotowane dla Ciebie',
  'Nadchodzące wydania',
  'Nowe wydania',
  'Hip-hop',
  'Nastrój',
  'Na czasie',
  'Muzyka elektroniczna/dance',
  'Listy przebojów',
  'Ranking podcastów',
  'Komedia',
  'Edukacja',
  'Relaks',
  'Odkryj muzykę',
  'Radio',
  'Fresh Finds',
  'Impreza',
  'Disco polo',
  'RADAR',
  'Muzyka do treningu',
  'EQUAL',
  'Dekady',
  'GLOW',
  'K-pop',
  'Jazz',
  'Klasyczna',
  'Koncentracja',
  'Folk i akustyczna',
  'Soul',
  'Dzieci i rodzina',
  'Gry',
  'Film i telewizja',
  'R&B',
  'Instrumentalna',
  'Punk',
  'Wellness',
  'Podróż',
  'Muzyka karaibska',
  'Afro',
  'Autorzy piosenek',
  'Odgłosy natury i szumy',
  'Funk',
  'Frequency',
  'Country',
  'Trendsetterzy',
  'Zmiksowana przez',
];

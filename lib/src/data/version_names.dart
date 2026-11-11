import 'text_normalizer.dart';

/// What kind of version of another song a row is (`songs.version_kind`, MusicDatabase's
/// `constants.VERSION_KINDS`; hand-off `song-versions-for-musicdatabaseapp.md`), with the label
/// shown when `songs.version_label` is empty.
enum VersionKind {
  live('Live'),
  remix('Remix'),
  acoustic('Acoustic'),
  edit('Edit'),
  extended('Extended'),
  demo('Demo'),
  instrumental('Instrumental'),

  /// `other`, and any value the phone doesn't know yet.
  other('Version');

  const VersionKind(this.label);

  final String label;

  static VersionKind of(String value) =>
      values.asNameMap()[value.trim().toLowerCase()] ?? other;
}

/// A song row that is a version of another song — live, a remix, an acoustic take. The marker is
/// never part of `songs.title`: MusicDatabase keeps the title without it.
class SongVersion {
  const SongVersion(this.kind, {String? label, this.originalId})
    : label = label == null || label == '' ? null : label;

  final VersionKind kind;

  /// `songs.version_label`, the marker as shown ("Cid Rim Remix"); `null` for [kind]'s own.
  final String? label;

  /// `songs.version_of`: the original's `songs.id`, when music.db has it — always the original
  /// itself, never another version.
  final int? originalId;

  /// "Live", "Cid Rim Remix".
  String get marker => label ?? kind.label;

  /// [marker] for comparing: "Live" and "live" are the same marker.
  String get markerKey => normalizeForSearch(marker);
}

/// "Boję się (Live)", or just [title] when it isn't a version.
String titleWithVersion(String title, SongVersion? version) =>
    version == null ? title : '$title (${version.marker})';

/// What a title says about being a version: [title] without the marker, the [kind] and the
/// marker as written ([label]; `null` when it only names the kind, "Live").
typedef VersionReading = ({String title, VersionKind kind, String? label});

final _bracket = RegExp(r'\s*[(\[【（［]([^()\[\]【】（）［］]*)[)\]】）］]');
// " - Live at Wembley" at the end, after a spaced dash
final _dashSuffix = RegExp(r'\s+[-–—]\s+([^-–—()\[\]【】（）［］]+?)\s*$');

// First match wins: "na żywo, akustycznie" is live, "Extended Orchestral Version" extended.
const _kindWords = [
  (VersionKind.live, r'live|na zywo|koncert\w*|concert'),
  (VersionKind.acoustic, r'acoustic|akustycz\w*|unplugged'),
  (VersionKind.instrumental, r'instrumental|instrumentalna'),
  (VersionKind.demo, r'demo'),
  (VersionKind.remix, r'remix|rmx|rework|bootleg|mashup|mix|dub'),
  (VersionKind.extended, r'extended|long version|long mix'),
  (VersionKind.edit, r'edit'),
  (VersionKind.other, r'version|wersja'),
];
final _kindRes = [
  for (final (kind, words) in _kindWords)
    (kind, RegExp('(?:^| )(?:$words)(?: |\$)')),
];
// Which release, not which recording
final _sameRecording = RegExp(
  r'^(?:\d{4} )?(?:radio|album|single|original|clean|explicit|explicit album|mono|stereo|lp|ep)'
  r'(?: (?:edit|version|mix|cut))?$|remaster',
);
// Brackets other readings own: a cover credit, a featured artist
final _otherCredit = RegExp(
  r'(?:^| )(?:cover|covered|feat|ft|featuring|with)(?: |$)',
);
final _spaces = RegExp(r'\s{2,}');
final _trimmed = RegExp(r'^[\s\-–—.,]+|[\s\-–—.,]+$');

/// The kind of version a marker ("Live Session", "Cid Rim Remix") names, `null` when it names
/// none or only a release ("Radio Edit", "Remastered", "Bonus track").
VersionKind? versionKindOf(String marker) {
  final key = normalizeForSearch(marker);
  if (key.isEmpty ||
      _sameRecording.hasMatch(key) ||
      _otherCredit.hasMatch(key)) {
    return null;
  }
  for (final (kind, words) in _kindRes) {
    if (words.hasMatch(key)) return kind;
  }
  return null;
}

VersionReading? _reading(String title, int start, int end, String marker) {
  final kind = versionKindOf(marker);
  final rest = '${title.substring(0, start)} ${title.substring(end)}'
      .replaceAll(_spaces, ' ')
      .replaceAll(_trimmed, '');
  if (kind == null || rest.isEmpty) return null;
  final label = marker.trim();
  return (
    title: rest,
    kind: kind,
    label: normalizeForSearch(label) == normalizeForSearch(kind.label)
        ? null
        : label,
  );
}

/// What [title] says about being a version: its last bracket naming one ("Song (Live)
/// (Remastered)" is live), else a spaced-dash suffix ("Song - Acoustic Version"); `null` when it
/// says nothing. A lite version of MusicDatabase's `read_version()`
/// (`src/utils/common/version_names.py`; ADR 0003).
VersionReading? readVersion(String? title) {
  if (title == null || title.isEmpty) return null;
  for (final bracket in _bracket.allMatches(title).toList().reversed) {
    final reading = _reading(
      title,
      bracket.start,
      bracket.end,
      bracket.group(1)!,
    );
    if (reading != null) return reading;
  }
  if (_dashSuffix.firstMatch(title) case final dash?) {
    return _reading(title, dash.start, dash.end, dash.group(1)!);
  }
  return null;
}

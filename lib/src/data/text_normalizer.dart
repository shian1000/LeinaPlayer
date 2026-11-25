/// Search normalization matching MusicDatabase's `normalize()` (`src/utils/common/normalizer.py`,
/// default flags), so the phone finds the same songs for a query as the backend does: accents
/// stripped, a few special letters spelled out, apostrophes dropped, other punctuation turned into
/// spaces, whitespace collapsed, lower case.
library;

// Dart has no Unicode decomposition, so letters whose NFKD form is "ASCII letter + combining
// marks" (or, like "ſ" and "ϐ", one other letter) are listed here, generated from Python's
// `unicodedata` (Latin-1 Supplement, Latin Extended-A/B, Latin Extended Additional, Greek,
// Cyrillic and kana: "Вахтёрам" is "вахтерам", "Летний" "летнии", "ブルース" "フルース" — so a
// title with the voiced mark as a combining U+3099, "フ\u3099ルース" as YouTube sent LUCKY TAPES'
// "レイディ・ブルース", is the same title). Index i of [_accented] maps to index i of [_plain].
const _accented =
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆ'
    'ćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐő'
    'ŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚ'
    'ǛǜǞǟǠǡǦǧǨǩǪǫǬǭǰǴǵǸǹǺǻȀȁȂȃȄȅȆȇȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȞȟȦȧȨȩȪȫȬȭȮ'
    'ȯȰȱȲȳḀḁḂḃḄḅḆḇḈḉḊḋḌḍḎḏḐḑḒḓḔḕḖḗḘḙḚḛḜḝḞḟḠḡḢḣḤḥḦḧḨḩḪḫḬḭḮḯḰḱḲḳḴḵḶ'
    'ḷḸḹḺḻḼḽḾḿṀṁṂṃṄṅṆṇṈṉṊṋṌṍṎṏṐṑṒṓṔṕṖṗṘṙṚṛṜṝṞṟṠṡṢṣṤṥṦṧṨṩṪṫṬṭṮṯṰṱṲ'
    'ṳṴṵṶṷṸṹṺṻṼṽṾṿẀẁẂẃẄẅẆẇẈẉẊẋẌẍẎẏẐẑẒẓẔẕẖẗẘẙẛẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳ'
    'ẴẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữ'
    'ỰựỲỳỴỵỶỷỸỹ'
    'ΆΈΉΊΌΎΏΐΪΫάέήίΰϊϋόύώϐϑϒϓϔϕϖϰϱϲϴϵϹЀЁЃЇЌЍЎЙй'
    'ѐёѓїќѝўѶѷӁӂӐӑӒӓӖӗӚӛӜӝӞӟӢӣӤӥӦӧӪӫӬӭӮӯӰӱӲӳӴӵӸӹ'
    'がぎぐげござじずぜぞだぢづでどばぱびぴぶぷべぺぼぽゔゞ'
    'ガギグゲゴザジズゼゾダヂヅデドバパビピブプベペボポヴヷヸヹヺヾ';
const _plain =
    'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaC'
    'cCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOo'
    'RrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZzsOoUuAaIiOoUuUuUuUu'
    'UuAaAaGgKkOoOojGgNnAaAaAaEeEeIiIiOoOoRrRrUuUuSsTtHhAaEeOoOoO'
    'oOoYyAaBbBbBbCcDdDdDdDdDdEeEeEeEeEeFfGgHhHhHhHhHhIiIiKkKkKkL'
    'lLlLlLlMmMmMmNnNnNnNnOoOoOoOoPpPpRrRrRrRrSsSsSsSsSsTtTtTtTtU'
    'uUuUuUuUuVvVvWwWwWwWwWwXxXxYyZzZzZzhtwysAaAaAaAaAaAaAaAaAaAa'
    'AaAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUu'
    'UuYyYyYyYy'
    'ΑΕΗΙΟΥΩιΙΥαεηιυιυουωβθΥΥΥφπκρςΘεΣЕЕГІКИУИи'
    'еегікиуѴѵЖжАаАаЕеӘәЖжЗзИиИиОоӨөЭэУуУуУуЧчЫы'
    'かきくけこさしすせそたちつてとははひひふふへへほほうゝ'
    'カキクケコサシスセソタチツテトハハヒヒフフヘヘホホウワヰヱヲヽ';

/// Letters that don't decompose; same table as `_SPECIAL_REPLACEMENTS` in normalizer.py.
const _special = {
  'ß': 'ss',
  'Æ': 'AE',
  'æ': 'ae',
  'Œ': 'OE',
  'œ': 'oe',
  'Ø': 'O',
  'ø': 'o',
  'Ł': 'L',
  'ł': 'l',
  'Đ': 'D',
  'đ': 'd',
};

final _letterMap = <int, String>{
  for (var i = 0; i < _accented.length; i++) _accented.codeUnitAt(i): _plain[i],
  for (final e in _special.entries) e.key.codeUnitAt(0): e.value,
};

final _apostrophes = RegExp(
  '[\'`\u00b4\u02b9\u02bc\u02bb\u02bd\u0374\uff07\u2018\u2019\u201a\u201b\u2032\u2035]',
);
// Dropped, not turned into spaces, as normalize.py drops what NFKD leaves combining and the
// invisible format characters: "ブ" may come as "フ" + U+3099, "é" as "e" + U+0301.
final _marks = RegExp(r'[\p{Mn}\p{Me}\p{Cf}]', unicode: true);
final _punctuation = RegExp(r'[^\p{L}\p{N}_\s]', unicode: true);
final _spaces = RegExp(r'\s+');

String normalizeForSearch(String? text) {
  if (text == null || text.isEmpty) return '';
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    final replacement = _letterMap[unit];
    if (replacement != null) {
      buffer.write(replacement);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer
      .toString()
      .replaceAll(_marks, '')
      .replaceAll(_apostrophes, '')
      .replaceAll(_punctuation, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .toLowerCase();
}

final _andSign = RegExp(r'\s*[&+]\s*');

/// [name] normalised with "&" and "+" read as "and": another key for an artist's name, so
/// "Florence and the Machine" is music.db's "Florence + the Machine" and "The Ball And Chain"
/// "The Ball & Chain" ([normalizeForSearch] alone turns the signs into spaces and keeps "and").
String normalizeWithAnd(String? name) =>
    normalizeForSearch(name?.replaceAll(_andSign, ' and '));

final _digitRuns = RegExp(r'\d+|\D+');

/// Orders names as people read them: normalised, with runs of digits compared by value,
/// so "2. Telefon" comes before "10. Pidvalia".
int compareNames(String? a, String? b) {
  final partsA = _digitRuns.allMatches(normalizeForSearch(a)).toList();
  final partsB = _digitRuns.allMatches(normalizeForSearch(b)).toList();
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final (x, y) = (partsA[i][0]!, partsB[i][0]!);
    final (nx, ny) = (BigInt.tryParse(x), BigInt.tryParse(y));
    final c = nx != null && ny != null
        ? (nx.compareTo(ny) != 0 ? nx.compareTo(ny) : x.length - y.length)
        : x.compareTo(y);
    if (c != 0) return c;
  }
  return partsA.length - partsB.length;
}

/// Could [corrected] be [name] spelt better, rather than another name? A lite
/// `title_resembles()` (MusicDatabase's `text_utils.py`): equal once normalised, or alike
/// enough — a longest-common-subsequence ratio standing in for `SequenceMatcher`, with the same
/// stricter thresholds for short names (no bracketed subtitles, no comparing across alphabets).
/// MusicDatabase flags an `artists.name` correction that doesn't resemble the old name in review.
bool nameResembles(String name, String corrected) {
  final a = normalizeForSearch(name);
  final b = normalizeForSearch(corrected);
  if (a.isNotEmpty && a == b) return true;
  final x = name.toLowerCase();
  final y = corrected.toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  final shortest = x.length < y.length ? x.length : y.length;
  final threshold = shortest <= 5
      ? 0.92
      : shortest <= 8
      ? 0.85
      : 0.7;
  return 2 * _commonSubsequence(x, y) / (x.length + y.length) >= threshold;
}

int _commonSubsequence(String a, String b) {
  var previous = List.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final row = List.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      row[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? previous[j - 1] + 1
          : (previous[j] > row[j - 1] ? previous[j] : row[j - 1]);
    }
    previous = row;
  }
  return previous[b.length];
}

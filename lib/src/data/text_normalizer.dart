/// Search normalization matching MusicDatabase's `normalize()` (`src/utils/common/normalizer.py`,
/// default flags), so the phone finds the same songs for a query as the backend does: accents
/// stripped, a few special letters spelled out, apostrophes dropped, other punctuation turned into
/// spaces, whitespace collapsed, lower case.
library;

// Dart has no Unicode decomposition, so letters whose NFKD form is "ASCII letter + combining
// marks" are listed here, generated from Python's `unicodedata` (Latin-1 Supplement, Latin
// Extended-A/B, Latin Extended Additional). Index i of [_accented] maps to index i of [_plain].
const _accented =
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆ'
    'ćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐő'
    'ŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚ'
    'ǛǜǞǟǠǡǦǧǨǩǪǫǬǭǰǴǵǸǹǺǻȀȁȂȃȄȅȆȇȈȉȊȋȌȍȎȏȐȑȒȓȔȕȖȗȘșȚțȞȟȦȧȨȩȪȫȬȭȮ'
    'ȯȰȱȲȳḀḁḂḃḄḅḆḇḈḉḊḋḌḍḎḏḐḑḒḓḔḕḖḗḘḙḚḛḜḝḞḟḠḡḢḣḤḥḦḧḨḩḪḫḬḭḮḯḰḱḲḳḴḵḶ'
    'ḷḸḹḺḻḼḽḾḿṀṁṂṃṄṅṆṇṈṉṊṋṌṍṎṏṐṑṒṓṔṕṖṗṘṙṚṛṜṝṞṟṠṡṢṣṤṥṦṧṨṩṪṫṬṭṮṯṰṱṲ'
    'ṳṴṵṶṷṸṹṺṻṼṽṾṿẀẁẂẃẄẅẆẇẈẉẊẋẌẍẎẏẐẑẒẓẔẕẖẗẘẙẛẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳ'
    'ẴẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữ'
    'ỰựỲỳỴỵỶỷỸỹ';
const _plain =
    'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaC'
    'cCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOo'
    'RrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZzsOoUuAaIiOoUuUuUuUu'
    'UuAaAaGgKkOoOojGgNnAaAaAaEeEeIiIiOoOoRrRrUuUuSsTtHhAaEeOoOoO'
    'oOoYyAaBbBbBbCcDdDdDdDdDdEeEeEeEeEeFfGgHhHhHhHhHhIiIiKkKkKkL'
    'lLlLlLlMmMmMmNnNnNnNnOoOoOoOoPpPpRrRrRrRrSsSsSsSsSsTtTtTtTtU'
    'uUuUuUuUuVvVvWwWwWwWwWwXxXxYyZzZzZzhtwysAaAaAaAaAaAaAaAaAaAa'
    'AaAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUu'
    'UuYyYyYyYy';

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
  '[\'`\u00b4\u02bc\u02bb\uff07\u2018\u2019\u201a\u201b\u2032\u2035]',
);
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
      .replaceAll(_apostrophes, '')
      .replaceAll(_punctuation, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .toLowerCase();
}

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

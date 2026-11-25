/// music.db's `songs.language`: ISO 639-3 codes, several in order with the main one first
/// ("eng / jpn"), `zxx` for a song without words and `und` for one not known — MusicDatabase's
/// `clean_language()` (hand-off `language-codes-for-musicdatabaseapp.md`). Screens show the
/// names in the app's language (`l10n.languageName`, a code it doesn't know as it is).
///
/// A music.db downloaded before 2026-11-25, and what the phone kept from one (a saved queue,
/// "Języki wyłączone z transliteracji"), holds English names instead: [languageCode] reads them
/// as their codes.
library;

import '../l10n.dart';
import 'text_normalizer.dart';

/// No words (an instrumental).
const noWordsLanguage = 'zxx';

/// MusicDatabase's placeholder for a language not known — not a language to show or group by.
const unknownLanguage = 'und';

/// Every code music.db used on 2026-11-25, the ones `languageName` has a name for.
final languageCodes =
    ('alt ara bel bos bre bul cat ces chu ckm crh csb cym dan deu dua ell eng est fao '
            'fas fil fin fra fro gaa gcf gla gle grc hbs heb hin hrv hsb hun hye isl isv ita '
            'jam jpn kan kas kat kaz kea kjv kor kur lat lav lit mkd mon mri nds nld non nor '
            'pan pcm pol por qiv qpd qpl rom ron rue rus sco shi slk slv sot spa srp sux swe '
            'szl tat tgl tur twi tyv ukr und vie wol yid yor yue zho zul zxx')
        .split(' ');

/// music.db's English names from before the codes, lower case (the hand-off's table).
const _oldNames = {
  'altai': 'alt',
  'arabic': 'ara',
  'belarusian': 'bel',
  'bosnian': 'bos',
  'breton': 'bre',
  'bulgarian': 'bul',
  'catalan': 'cat',
  'czech': 'ces',
  'church slavonic': 'chu',
  'croatian (čakavian)': 'ckm',
  'crimean tatar': 'crh',
  'kashubian': 'csb',
  'welsh': 'cym',
  'danish': 'dan',
  'german': 'deu',
  'duala': 'dua',
  'greek': 'ell',
  'english': 'eng',
  'estonian': 'est',
  'faroese': 'fao',
  'persian': 'fas',
  'filipino': 'fil',
  'finnish': 'fin',
  'french': 'fra',
  'old french': 'fro',
  'ga': 'gaa',
  'guadeloupean creole': 'gcf',
  'scottish gaelic': 'gla',
  'irish': 'gle',
  'ancient greek': 'grc',
  'attic greek': 'grc',
  'serbo-croatian': 'hbs',
  'hebrew': 'heb',
  'hindi': 'hin',
  'croatian': 'hrv',
  'upper sorbian': 'hsb',
  'hungarian': 'hun',
  'armenian': 'hye',
  'icelandic': 'isl',
  'interslavic': 'isv',
  'italian': 'ita',
  'jamaican patois': 'jam',
  'english (jamaican)': 'jam',
  'japanese': 'jpn',
  'kannada': 'kan',
  'kashmiri': 'kas',
  'georgian': 'kat',
  'kazakh': 'kaz',
  'cape verdean creole': 'kea',
  'croatian (kajkavian)': 'kjv',
  'korean': 'kor',
  'kurdish': 'kur',
  'latin': 'lat',
  'latvian': 'lav',
  'lithuanian': 'lit',
  'macedonian': 'mkd',
  'mongolian': 'mon',
  'maori': 'mri',
  'low german': 'nds',
  'dutch': 'nld',
  'old norse': 'non',
  'norwegian': 'nor',
  'punjabi': 'pan',
  'nigerian pidgin': 'pcm',
  'polish': 'pol',
  'portuguese': 'por',
  'invented': 'qiv',
  'podlachian': 'qpd',
  'pseudo-latin': 'qpl',
  'romani': 'rom',
  'romanian': 'ron',
  'rusyn': 'rue',
  'ruthenian': 'rue',
  'russian': 'rus',
  'scots': 'sco',
  'tachelhit': 'shi',
  'berber': 'shi',
  'slovak': 'slk',
  'slovenian': 'slv',
  'sotho': 'sot',
  'spanish': 'spa',
  'serbian': 'srp',
  'sumerian': 'sux',
  'swedish': 'swe',
  'silesian': 'szl',
  'tatar': 'tat',
  'tagalog': 'tgl',
  'turkish': 'tur',
  'twi': 'twi',
  'tuvan': 'tyv',
  'ukrainian': 'ukr',
  'unknown': 'und',
  'vietnamese': 'vie',
  'wolof': 'wol',
  'yiddish': 'yid',
  'yoruba': 'yor',
  'cantonese': 'yue',
  'chinese': 'zho',
  'zulu': 'zul',
  'instrumental': 'zxx',
  'no language': 'zxx',
};

final _code = RegExp(r'^[a-z]{3}$');

/// The code of one language of `songs.language`: [name] itself when it's a code, an old
/// English name's code, else [name] as it is.
String languageCode(String name) {
  final lower = name.trim().toLowerCase();
  return _oldNames[lower] ?? (_code.hasMatch(lower) ? lower : name.trim());
}

/// The codes of a `songs.language` value: "eng / jpn" → eng, jpn.
List<String> languagesOf(String? language) => [
  for (final part in (language ?? '').split('/'))
    if (part.trim().isNotEmpty) languageCode(part),
];

/// [language] as codes ("Japanese / English" → "jpn / eng"); `null` when it holds none.
String? languageValue(String? language) {
  final codes = languagesOf(language);
  return codes.isEmpty ? null : codes.join(' / ');
}

/// Whether [language] names a language to show, group or match by: set and not [unknownLanguage].
bool isKnownLanguage(String? language) {
  final codes = languagesOf(language);
  return codes.isNotEmpty && !codes.every((c) => c == unknownLanguage);
}

/// [language] in the app's language: "eng / jpn" → "Angielski / Japoński".
String languageNames(String? language) =>
    languagesOf(language).map(l10n.languageName).join(' / ');

/// The texts in every language the app has, so a search or a typed name in any of them works
/// whichever language the app speaks now.
final List<AppLocalizations> _allTexts = [
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale),
];

/// What search matches [language] by: each code and its names in every app language ("jpn
/// Japoński Japanese").
String languageSearchText(String? language) => [
  for (final code in languagesOf(language))
    if (code != unknownLanguage) ...{
      code,
      for (final texts in _allTexts) texts.languageName(code),
    },
].join(' ');

final Map<String, String> _codesByName = {
  for (final MapEntry(:key, :value) in _oldNames.entries)
    normalizeForSearch(key): value,
  for (final code in languageCodes)
    for (final texts in _allTexts)
      normalizeForSearch(texts.languageName(code)): code,
};

/// A `songs.language` value typed by the user ("Polski / angielski", "eng") as codes for
/// MusicDatabase; a name the phone doesn't know goes as typed (MusicDatabase reads it then).
String? languageValueOfTyped(String typed) {
  final codes = [
    for (final part in typed.split('/'))
      if (part.trim().isNotEmpty)
        _codesByName[normalizeForSearch(part)] ?? languageCode(part),
  ];
  return codes.isEmpty ? null : codes.join(' / ');
}

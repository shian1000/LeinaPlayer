import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/l10n.dart';

void main() {
  test('the phone language picks the closest translation, else Polish', () {
    expect(resolveSystemLocale(const [Locale('pl', 'PL')]), const Locale('pl'));
    expect(resolveSystemLocale(const [Locale('en', 'US')]), const Locale('en'));
    expect(
      resolveSystemLocale(const [Locale('en', 'GB')]),
      const Locale('en', 'GB'),
    );
    expect(
      resolveSystemLocale(const [Locale('ja'), Locale('en', 'AU')]),
      const Locale('en', 'GB'),
    );
    expect(resolveSystemLocale(const [Locale('ja')]), const Locale('pl'));
    expect(resolveSystemLocale(null), const Locale('pl'));
  });

  test('Polish plurals and dates come from the template', () {
    setAppLocale(const Locale('pl'));
    expect(l10n.songsCount(1), '1 utwór');
    expect(l10n.songsCount(3), '3 utwory');
    expect(l10n.songsCount(5), '5 utworów');
    expect(l10n.songsCount(22), '22 utwory');
    expect(l10n.dateDayMonthYear(16, '10', 2026), '16 października 2026');
  });

  test('English (US and UK)', () {
    setAppLocale(const Locale('en'));
    expect(l10n.songsCount(1), '1 song');
    expect(l10n.dateDayMonth(16, '10'), 'October 16');
    setAppLocale(const Locale('en', 'GB'));
    expect(l10n.dateDayMonth(16, '10'), '16 October');
    expect(l10n.songsCount(2), '2 songs');
    setAppLocale(const Locale('pl'));
  });
}

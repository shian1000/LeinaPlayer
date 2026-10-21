import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app_name.dart';
import 'app_updates.dart';
import 'error_log.dart';

/// Which phone a report comes from; `null` fields when Android doesn't say (or not Android).
typedef DeviceInfo = ({String? manufacturer, String? model, String? android});

const _channel = MethodChannel('music_database_app/links');

/// The phone's maker, model and Android version (`deviceInfo` in `MainActivity.kt`).
Future<DeviceInfo> deviceInfo() async {
  if (!Platform.isAndroid) {
    return (manufacturer: null, model: null, android: null);
  }
  try {
    final info = (await _channel.invokeMethod<Map>('deviceInfo')) ?? {};
    return (
      manufacturer: info['manufacturer'] as String?,
      model: info['model'] as String?,
      android: info['release'] == null
          ? null
          : '${info['release']} (API ${info['sdk']})',
    );
  } on PlatformException {
    return (manufacturer: null, model: null, android: null);
  } on MissingPluginException {
    return (manufacturer: null, model: null, android: null);
  }
}

/// "Zgłoś problem"'s report (sharing checklist 4.3): the app's version, the phone, what the
/// user wrote and the [ErrorLog] — plain text, shown before it's sent.
String problemReport({
  required PackageInfo package,
  required DeviceInfo device,
  required String description,
  required String log,
  required DateTime at,
  String commit = const String.fromEnvironment('GIT_COMMIT'),
}) {
  final universal = isUniversalApk(package.buildNumber);
  String two(int n) => n.toString().padLeft(2, '0');
  final lines = [
    'Raport problemu — $appName',
    'Utworzony: ${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}',
    '',
    'Wersja: ${package.version}, kompilacja ${buildNumberOf(package.buildNumber)}'
        '${commit.isEmpty ? '' : ', $commit'}'
        '${universal == null
            ? ''
            : universal
            ? ', wersja duża'
            : ', wersja mała'}',
    'Telefon: ${[device.manufacturer, device.model].nonNulls.join(' ').ifEmpty('nieznany')}',
    'Android: ${device.android ?? 'nieznany'}',
    '',
    'Co się stało:',
    description.trim().isEmpty ? '(nie opisano)' : description.trim(),
    '',
    'Dziennik błędów (ostatnie ${ErrorLog.keepFor.inDays} dni):',
    log.trim().isEmpty ? '(pusty)' : log.trim(),
  ];
  return '${lines.join('\n')}\n';
}

/// [report] as a `.txt` in the app's temporary folder, for "Udostępnij".
Future<File> saveProblemReport(String report, DateTime at) async {
  String two(int n) => n.toString().padLeft(2, '0');
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/leina-radio-raport-${at.year}-${two(at.month)}-${two(at.day)}_'
    '${two(at.hour)}-${two(at.minute)}.txt',
  );
  await file.writeAsString(report, flush: true);
  return file;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

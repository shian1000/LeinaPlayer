import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../data/error_log.dart';
import '../data/problem_report.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Informacje i pomoc › Zgłoś problem": what happened (optional), the report as it will be sent
/// — version, phone, the error log — and "Wyślij", which hands a `.txt` to "Udostępnij". Nothing
/// is sent by the app itself.
class ProblemReportScreen extends StatefulWidget {
  const ProblemReportScreen({
    super.key,
    this.log,
    this.packageInfo,
    this.device,
    this.share,
  });

  /// Tests pass their own; [ErrorLog.instance] otherwise.
  final ErrorLog? log;
  final Future<PackageInfo> Function()? packageInfo;
  final Future<DeviceInfo> Function()? device;
  final Future<void> Function(String report)? share;

  @override
  State<ProblemReportScreen> createState() => _ProblemReportScreenState();
}

class _ProblemReportScreenState extends State<ProblemReportScreen> {
  final _description = TextEditingController();
  PackageInfo? _package;
  DeviceInfo? _device;

  ErrorLog get _log => widget.log ?? ErrorLog.instance;

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
    (widget.packageInfo ?? PackageInfo.fromPlatform)().then((p) {
      if (mounted) setState(() => _package = p);
    });
    (widget.device ?? deviceInfo)().then((d) {
      if (mounted) setState(() => _device = d);
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String? get _report {
    final package = _package;
    final device = _device;
    if (package == null || device == null) return null;
    return problemReport(
      package: package,
      device: device,
      description: _description.text,
      log: _log.text,
      at: DateTime.now(),
    );
  }

  Future<void> _send() async {
    final report = _report;
    if (report == null) return;
    final share = widget.share;
    if (share != null) return share(report);
    final file = await saveProblemReport(report, DateTime.now());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Leina Radio — raport problemu',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Zgłoś problem'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Co się stało? (opcjonalnie)',
              hintText: 'Co robiłeś, co się stało, czego się spodziewałeś',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Raport zawiera wersję aplikacji, model telefonu, wersję Androida, Twój opis i '
            'dziennik błędów z ostatnich ${ErrorLog.keepFor.inDays} dni. W dzienniku mogą '
            'być tytuły utworów i adresy serwera; tokeny i hasła są z niego wycinane. '
            'Aplikacja niczego nie wysyła sama — „Wyślij” otwiera „Udostępnij”, a Ty wybierasz, '
            'komu i jak.',
            style: TextStyle(
              fontSize: AppFontSize.small,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
              shape: palette.pillShape,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.send),
            label: const Text('Wyślij'),
            onPressed: report == null ? null : _send,
          ),
          const SectionTitle('Podgląd raportu'),
          if (report == null)
            const Center(child: CircularProgressIndicator())
          else
            SelectableText(
              report,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontFamily: 'monospace',
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

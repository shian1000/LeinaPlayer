import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// "Ustawienia › Informacje i pomoc": the terms the app may be shared under. Mostly a reminder
/// for the owner — the app is for private use only and must never go to an app store.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final sourceUrl = Uri.parse(
    'https://github.com/shian1000/MusicDatabaseApp',
  );

  Future<void> _openSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      sourceUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć przeglądarki.')),
      );
    }
  }

  Future<void> _copySource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: sourceUrl.toString()));
    messenger.showSnackBar(
      const SnackBar(content: Text('Skopiowano link do kodu źródłowego')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: palette.textSecondary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Informacje i pomoc'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Tylko do użytku prywatnego'),
          paragraph(
            'Aplikacja pobiera i odtwarza dźwięk z YouTube poza jego oficjalnym '
            'odtwarzaczem, co jest niezgodne z regulaminem YouTube i zasadami sklepów. '
            'Nie publikuj jej w Google Play ani w żadnym innym sklepie.',
          ),
          paragraph(
            'Można ją za darmo udostępniać wąskiemu gronu znajomych — razem z dostępem do '
            'kodu źródłowego (link poniżej).',
          ),
          paragraph(
            'Odtwarzanie i wyszukiwanie w YouTube może przestać działać po zmianach po '
            'stronie YouTube. Naprawa wymaga wtedy nowej wersji aplikacji.',
          ),
          const SectionTitle('Licencja'),
          paragraph(
            'GNU General Public License v3 (GPLv3) — wymaga tego biblioteka NewPipeExtractor, '
            'z której korzysta odtwarzanie z YouTube na Androidzie. Każdy, kto dostaje '
            'aplikację, ma prawo do jej kodu źródłowego na tej samej licencji.',
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Kod źródłowy'),
            subtitle: Text(sourceUrl.toString()),
            trailing: IconButton(
              tooltip: 'Kopiuj link',
              icon: const Icon(Icons.copy),
              onPressed: () => _copySource(context),
            ),
            onTap: () => _openSource(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licencje bibliotek'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'MusicDatabase',
            ),
          ),
        ],
      ),
    );
  }
}

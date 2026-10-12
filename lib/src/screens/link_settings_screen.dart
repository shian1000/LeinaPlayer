import 'package:flutter/material.dart';

import '../app_name.dart';
import '../data/incoming_links.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Ustawienia › Otwieranie linków": what a tapped YouTube or Spotify link does — the sheet
/// asking each time (`LinkChooserActivity.kt`) or a remembered choice — and how to make the
/// phone give these links to the app at all.
class LinkSettingsScreen extends StatefulWidget {
  const LinkSettingsScreen({super.key});

  @override
  State<LinkSettingsScreen> createState() => _LinkSettingsScreenState();
}

class _LinkSettingsScreenState extends State<LinkSettingsScreen> {
  Map<LinkService, LinkChoice>? _choices;

  @override
  void initState() {
    super.initState();
    readLinkChoices().then((choices) {
      if (mounted) setState(() => _choices = choices);
    });
  }

  Future<void> _pick(LinkService service) async {
    final current = _choices?[service] ?? LinkChoice.ask;
    final picked = await showDialog<LinkChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Linki ${_from(service)}'),
        children: [
          for (final choice in LinkChoice.values)
            ListTile(
              title: Text(linkChoiceLabel(service, choice)),
              trailing: choice == current
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(choice),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await saveLinkChoice(service, picked);
    if (mounted) setState(() => _choices = {...?_choices, service: picked});
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
    final choices = _choices;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Otwieranie linków'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          for (final service in LinkService.values)
            ListTile(
              enabled: choices != null,
              leading: Icon(
                service == LinkService.youtube
                    ? Icons.smart_display_outlined
                    : Icons.graphic_eq,
              ),
              title: Text('Linki ${_from(service)}'),
              subtitle: Text(
                linkChoiceLabel(service, choices?[service] ?? LinkChoice.ask),
              ),
              onTap: () => _pick(service),
            ),
          paragraph(
            'Po kliknięciu linku z YouTube albo Spotify $appName pyta, czym go otworzyć: '
            '$appName, aplikacją YouTube lub Spotify albo przeglądarką. Zaznaczając tam '
            '„Zapamiętaj wybór” ustawiasz go tutaj.',
          ),
          const SectionTitle('W $appName'),
          paragraph(
            'Film z YouTube i utwór ze Spotify od razu grają — z telefonu albo z bazy danych, '
            'jeśli jest tam ten utwór; utwór ze Spotify, którego nie ma, jest wyszukiwany na '
            'YouTube. Playlista albo album trafia do Biblioteki. Tak samo działa wysłanie linku '
            'do $appName przez „Udostępnij” — wtedy bez pytania.',
          ),
          const SectionTitle('Ustawienia telefonu'),
          paragraph(
            'Żeby linki w ogóle trafiały do $appName, w ustawieniach telefonu: Aplikacje › '
            'YouTube (i Spotify) › Otwieraj domyślnie — wyłącz „Otwieraj obsługiwane linki”; '
            'potem Aplikacje › $appName › Otwieraj domyślnie — włącz je i zaznacz wszystkie '
            'linki. Na starszych telefonach system sam zapyta, czym otworzyć link. Gdy '
            '$appName odsyła link do YouTube lub Spotify, zawsze otwiera ich aplikację.',
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text('Otwieraj linki w $appName'),
            subtitle: const Text('Ustawienia telefonu › Otwieraj domyślnie'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!await openLinkSettings()) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Nie udało się otworzyć ustawień telefonu.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

String _from(LinkService service) =>
    service == LinkService.youtube ? 'z YouTube' : 'ze Spotify';

/// "Pytaj za każdym razem", "Aplikacja Spotify"…
String linkChoiceLabel(LinkService service, LinkChoice choice) =>
    switch (choice) {
      LinkChoice.ask => 'Pytaj za każdym razem',
      LinkChoice.leina => appName,
      LinkChoice.app => 'Aplikacja ${service.label}',
      LinkChoice.browser => 'Przeglądarka',
    };

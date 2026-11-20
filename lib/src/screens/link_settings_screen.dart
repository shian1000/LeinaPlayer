import 'package:flutter/material.dart';

import '../app_name.dart';
import '../data/incoming_links.dart';
import '../l10n.dart';
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
        title: Text(_linksFrom(service)),
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
        title: Text(l10n.linkSettingsScreenTitle),
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
              title: Text(_linksFrom(service)),
              subtitle: Text(
                linkChoiceLabel(service, choices?[service] ?? LinkChoice.ask),
              ),
              onTap: () => _pick(service),
            ),
          paragraph(l10n.linkSettingsScreenIntro(appName)),
          SectionTitle(l10n.linkSettingsScreenPhoneSettings),
          paragraph(l10n.linkSettingsScreenPhoneSettingsHowTo(appName)),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.linkSettingsScreenOpenLinksIn(appName)),
            subtitle: Text(l10n.linkSettingsScreenOpenByDefaultPath),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!await openLinkSettings()) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.linkSettingsScreenSettingsFailed),
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

String _linksFrom(LinkService service) => service == LinkService.youtube
    ? l10n.linkSettingsScreenYouTubeLinks
    : l10n.linkSettingsScreenSpotifyLinks;

/// "Pytaj za każdym razem", "Aplikacja Spotify"…
String linkChoiceLabel(LinkService service, LinkChoice choice) =>
    switch (choice) {
      LinkChoice.ask => l10n.linkSettingsScreenAskEveryTime,
      LinkChoice.leina => appName,
      LinkChoice.app => l10n.linkSettingsScreenServiceApp(service.label),
      LinkChoice.browser => l10n.linkSettingsScreenBrowser,
    };

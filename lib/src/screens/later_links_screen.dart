import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/incoming_links.dart';
import '../data/later_links.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/menu_sheet.dart';
import 'app_shell.dart';

const _id = 'Na później';

/// "Na później" (Menu profilu › Wiadomości): links people sent, saved from the "Otwórz w…"
/// sheet with who sent them. Tapping one opens it like a link given to the app.
class LaterLinksScreen extends StatefulWidget {
  const LaterLinksScreen({super.key, this.onOpen});

  /// Opening a link; [AppShell.openLink] when not given (tests give their own).
  final void Function(String url)? onOpen;

  @override
  State<LaterLinksScreen> createState() => _LaterLinksScreenState();
}

class _LaterLinksScreenState extends State<LaterLinksScreen> {
  /// The person whose links are shown; `null`: everyone's.
  String? _personId;

  /// Links whose title was already looked for since the screen opened.
  final _described = <String>{};
  bool _describing = false;
  LaterLinks? _later;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final later = LaterLinksScope.of(context);
    if (_later == null) {
      _later = later;
      unawaited(later.load());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _describe());
  }

  /// Finds titles for links that have none, one at a time; a link that can't be told stays
  /// as its kind ("Film z YouTube") and is tried again next time the screen opens.
  Future<void> _describe() async {
    if (_describing || !mounted) return;
    final later = LaterLinksScope.of(context);
    LaterLink? next() => later.links
        .where((l) => l.title == null && !_described.contains(l.id))
        .firstOrNull;
    if (next() == null) return;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final playlists = PlaylistLibraryScope.of(context);
    final search = YouTubeScope.searchOf(context);
    final spotify = YouTubeScope.spotifyOf(context);
    final settings = SourceSettingsScope.of(context);
    _describing = true;
    try {
      while (mounted) {
        final link = next();
        if (link == null) break;
        _described.add(link.id);
        final found = await describeLaterLink(
          link,
          catalog: catalog,
          library: library,
          youTube: youTube,
          playlists: playlists,
          search: search,
          spotify: spotify,
          settings: settings,
        );
        if (found != null) {
          await later.setDescription(link, found.title, found.artist);
        }
      }
    } finally {
      _describing = false;
    }
  }

  void _open(LaterLink link) {
    unawaited(LaterLinksScope.of(context).setOpened(link, true));
    (widget.onOpen ?? AppShell.of(context).openLink)(link.url);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final later = LaterLinksScope.of(context);
    final people = later.people;
    if (_personId != null && !people.any((p) => p.id == _personId)) {
      _personId = null;
    }
    final links = [
      for (final link in later.links)
        if (_personId == null || link.personId == _personId) link,
    ];
    int countOf(LaterPerson person) =>
        later.links.where((l) => l.personId == person.id).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.background,
        centerTitle: true,
        title: const Text(_id),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (people.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  PillChip(
                    label: 'Wszyscy',
                    selected: _personId == null,
                    onTap: () => setState(() => _personId = null),
                  ),
                  for (final person in people) ...[
                    const SizedBox(width: 8),
                    PillChip(
                      label: '${person.name} (${countOf(person)})',
                      selected: _personId == person.id,
                      onTap: () => setState(
                        () => _personId = _personId == person.id
                            ? null
                            : person.id,
                      ),
                      onLongPress: () => _personMenu(person),
                    ),
                  ],
                ],
              ),
            ),
          if (links.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Text(
                later.links.isEmpty
                    ? 'Nic tu jeszcze nie ma.\n\nGdy ktoś przyśle Ci link z YouTube albo '
                          'Spotify, stuknij go i w okienku „Otwórz w…” wybierz „Zapisz na '
                          'później” — potem wskaż, od kogo jest.\n\nOkienko pokazuje się, gdy '
                          'linki otwiera Leina Radio i nie zapamiętano wyboru (Ustawienia › '
                          'Otwieranie linków).'
                    : 'Nic od tej osoby.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          for (final link in links)
            _LaterRow(
              link: link,
              person: later.personOf(link)?.name,
              onTap: () => _open(link),
              onMenu: () => _linkMenu(link),
            ),
        ],
      ),
    );
  }

  Future<void> _linkMenu(LaterLink link) {
    final later = LaterLinksScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(link.url);
    final app = link.service.label;
    return showMenuSheet(
      context,
      idPrefix: '$_id › Link',
      header: MenuSheetHeader(
        cover: _ServiceIcon(service: link.service),
        title: link.title ?? link.kind,
        subtitle: link.url,
      ),
      entries: [
        MenuSheetEntry(
          Icons.play_arrow,
          'Otwórz w Leina Radio',
          onTap: () => _open(link),
        ),
        MenuSheetEntry(
          link.opened
              ? Icons.radio_button_unchecked
              : Icons.check_circle_outline,
          link.opened ? 'Oznacz jako nieodsłuchany' : 'Oznacz jako odsłuchany',
          onTap: () => later.setOpened(link, !link.opened),
        ),
        MenuSheetEntry(
          Icons.person_outline,
          'Zmień, od kogo jest',
          onTap: () => _choosePerson(link),
        ),
        MenuSheetEntry(
          Icons.open_in_new,
          'Otwórz w aplikacji $app',
          onTap: () => _openOutside(link.service, uri),
        ),
        MenuSheetEntry(
          Icons.link,
          'Kopiuj link',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: link.url));
            messenger.showSnackBar(
              const SnackBar(content: Text('Skopiowano link.')),
            );
          },
        ),
        MenuSheetEntry(
          Icons.delete_outline,
          'Usuń z „Na później”',
          onTap: () => later.remove(link),
        ),
      ],
    );
  }

  Future<void> _openOutside(LinkService service, Uri uri) async {
    if (service == LinkService.youtube) {
      await openInYouTube(uri);
      return;
    }
    if (await openInSpotifyApp(uri) != null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _choosePerson(LaterLink link) {
    final later = LaterLinksScope.of(context);
    return showMenuSheet(
      context,
      idPrefix: '$_id › Od kogo',
      header: MenuSheetHeader(
        cover: _ServiceIcon(service: link.service),
        title: 'Od kogo?',
        subtitle: link.title ?? link.kind,
      ),
      entries: [
        MenuSheetEntry(
          Icons.person_add_alt,
          'Nowa osoba',
          onTap: () async {
            final name = await _askName('Nowa osoba', '');
            if (name == null) return;
            await later.setPerson(link, await later.addPerson(name));
          },
        ),
        for (final person in later.people)
          MenuSheetEntry(
            person.id == link.personId ? Icons.check : Icons.person_outline,
            person.name,
            onTap: () => later.setPerson(link, person.id),
          ),
      ],
    );
  }

  Future<String?> _askName(String title, String initial) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: title,
        hint: 'Imię lub nazwa',
        initial: initial,
      ),
    );
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _personMenu(LaterPerson person) {
    final later = LaterLinksScope.of(context);
    return showMenuSheet(
      context,
      idPrefix: '$_id › Osoba',
      header: MenuSheetHeader(
        cover: _Initial(name: person.name),
        title: person.name,
        subtitle:
            'Linków: ${later.links.where((l) => l.personId == person.id).length}',
      ),
      entries: [
        MenuSheetEntry(
          Icons.edit_outlined,
          'Zmień nazwę',
          onTap: () async {
            final name = await _askName('Zmień nazwę', person.name);
            if (name != null) await later.renamePerson(person, name);
          },
        ),
        MenuSheetEntry(
          Icons.delete_outline,
          'Usuń osobę',
          onTap: () => _confirmRemovePerson(person),
        ),
      ],
    );
  }

  Future<void> _confirmRemovePerson(LaterPerson person) async {
    final later = LaterLinksScope.of(context);
    final count = later.links.where((l) => l.personId == person.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Usunąć „${person.name}”?'),
        content: Text(
          count == 0
              ? 'Zniknie z listy osób w okienku „Zapisz na później”.'
              : 'Razem z nią znikną zapisane od niej linki ($count).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await later.removePerson(person);
  }
}

class _LaterRow extends StatelessWidget {
  const _LaterRow({
    required this.link,
    required this.person,
    required this.onTap,
    required this.onMenu,
  });

  final LaterLink link;
  final String? person;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final details = [
      // The icon already tells YouTube from Spotify; the kind only names an untitled link.
      ?link.artist,
      if (person != null) 'od: $person',
      laterDateLabel(link.savedAt, DateTime.now()),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      leading: _ServiceIcon(service: link.service),
      title: Row(
        children: [
          if (!link.opened) ...[
            Tooltip(
              message: 'Nieodsłuchany',
              child: Icon(Icons.circle, size: 10, color: palette.accent),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              link.title ?? link.kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.listTitle,
                color: link.opened ? palette.textSecondary : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        details.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Menu linku (⋮)',
        icon: const Icon(Icons.more_vert),
        onPressed: onMenu,
      ),
      onTap: onTap,
      onLongPress: onMenu,
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.service});

  final LinkService service;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: palette.radius(4),
      ),
      child: Icon(
        service == LinkService.youtube
            ? Icons.smart_display_outlined
            : Icons.graphic_eq,
        color: palette.textSecondary,
        semanticLabel: service.label,
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CircleAvatar(
      radius: 24,
      backgroundColor: palette.chip,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// "dzisiaj", "wczoraj", "3 dni temu", then the date.
String laterDateLabel(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'dzisiaj';
  if (days == 1) return 'wczoraj';
  if (days < 7) return '$days dni temu';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}.${two(at.month)}.${at.year}';
}

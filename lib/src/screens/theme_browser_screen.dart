import 'package:flutter/material.dart';

import '../data/network_errors.dart';
import '../data/theme_repository.dart';
import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/theme_swatch.dart';

/// "Ustawienia › Wygląd › Pobierz motyw": the themes on GitHub, to download, update or remove.
class ThemeBrowserScreen extends StatefulWidget {
  const ThemeBrowserScreen({super.key});

  @override
  State<ThemeBrowserScreen> createState() => _ThemeBrowserScreenState();
}

class _ThemeBrowserScreenState extends State<ThemeBrowserScreen> {
  List<ThemeListing>? _listings;
  String? _error;
  final _busy = <String>{};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final listings = await ThemeScope.of(context).repository.fetchIndex();
      if (mounted) setState(() => _listings = listings);
    } catch (e) {
      debugPrint('Loading the list of themes failed: $e');
      if (mounted) setState(() => _error = _message(e));
    }
  }

  static String _message(Object error) => isNetworkError(error)
      ? 'Nie udało się połączyć z GitHubem.'
      : 'Nie udało się odczytać listy motywów.';

  Future<void> _install(ThemeListing listing) async {
    final controller = ThemeScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(listing.id));
    try {
      final theme = await controller.install(listing.id);
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          content: Text('Pobrano motyw ${listing.name}'),
          action: SnackBarAction(
            label: 'Użyj',
            onPressed: () => theme.brightness == Brightness.dark
                ? controller.setDark(theme)
                : controller.setLight(theme),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Downloading theme ${listing.id} failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(e)
                ? 'Nie udało się połączyć z GitHubem.'
                : 'Nie udało się pobrać motywu.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(listing.id));
    }
  }

  Widget _action(ThemeController controller, ThemeListing listing) {
    if (_busy.contains(listing.id)) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final installed = controller.downloadedVersion(listing.id);
    if (installed == null) {
      return IconButton(
        tooltip: 'Pobierz',
        icon: const Icon(Icons.download_outlined),
        onPressed: () => _install(listing),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (installed < listing.version)
          IconButton(
            tooltip: 'Aktualizuj',
            icon: const Icon(Icons.update),
            onPressed: () => _install(listing),
          ),
        IconButton(
          tooltip: 'Usuń',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => controller.remove(listing.id),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = ThemeScope.of(context);
    final listings = _listings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Pobierz motyw'),
      ),
      body: switch ((listings, _error)) {
        (_, final String error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, style: TextStyle(color: palette.textSecondary)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<ThemeListing> items, _) when items.isEmpty => Center(
          child: Text(
            'Brak motywów do pobrania.',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
        (final List<ThemeListing> items, _) => ListView(
          padding: const EdgeInsets.only(top: 12),
          children: [
            for (final listing in items)
              ListTile(
                leading: ThemeSwatch(listing.preview),
                title: ScrollingText(listing.name),
                subtitle: ScrollingText(
                  [
                    listing.brightness == Brightness.dark ? 'Ciemny' : 'Jasny',
                    if (listing.author.isNotEmpty) listing.author,
                  ].join(' · '),
                ),
                trailing: _action(controller, listing),
              ),
          ],
        ),
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/downloads.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cache_contents_screen.dart';
import 'downloaded_songs_screen.dart';

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Everything the phone keeps to play and show without the internet: YouTube audio, the queue's
/// next songs (downloaded into that audio cache), songs kept with "Pobierz" and album covers, in
/// bytes.
int cacheBytesOf(BuildContext context) =>
    (YouTubeLibraryScope.maybeOf(context)?.cachedBytes ?? 0) +
    (DownloadsScope.maybeOf(context)?.bytes ?? 0) +
    (AlbumCoversScope.maybeOf(context)?.cachedBytes ?? 0);

/// "Ustawienia › Oszczędzanie danych i tryb offline › Pamięć podręczna": every cache setting in
/// one place — YouTube songs, the queue's songs downloaded ahead, what the phone found out on
/// YouTube itself, album covers.
class CacheSettingsScreen extends StatefulWidget {
  const CacheSettingsScreen({super.key});

  @override
  State<CacheSettingsScreen> createState() => _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends State<CacheSettingsScreen> {
  static const _coverLimits = [25, 50, 100, 200, 500];

  Future<bool> _confirm(String title, String text, {String? action}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action ?? l10n.cacheSettingsScreenClear),
            ),
          ],
        ),
      ) ??
      false;

  void _done(String message) {
    if (!mounted) return;
    // Cover sizes aren't a notifier the screen listens to.
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editSongLimit(SourceSettings settings) async {
    final library = YouTubeLibraryScope.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.cacheSettingsScreenSongLimitTitle,
        hint: '${SourceSettings.defaultCacheLimit}',
        initial: '${settings.cacheLimit}',
        number: true,
      ),
    );
    final limit = int.tryParse(result?.trim() ?? '');
    if (limit == null) return;
    await settings.setCacheLimit(limit);
    await library.trim(settings.cacheKeep);
  }

  Future<void> _clearSongs() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      l10n.cacheSettingsScreenClearSongsTitle,
      l10n.cacheSettingsScreenClearSongsBody,
    )) {
      return;
    }
    await library.clearCache();
    _done(l10n.cacheSettingsScreenSongsCleared);
  }

  Future<void> _forgetMatches() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      l10n.cacheSettingsScreenForgetMatchesTitle,
      l10n.cacheSettingsScreenForgetMatchesBody,
      action: l10n.cacheSettingsScreenForget,
    )) {
      return;
    }
    await library.forgetPhoneMatches();
    _done(l10n.cacheSettingsScreenMatchesForgotten);
  }

  Future<void> _forgetNotFound() async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      l10n.cacheSettingsScreenForgetNotFoundTitle,
      l10n.cacheSettingsScreenForgetNotFoundBody,
      action: l10n.cacheSettingsScreenForget,
    )) {
      return;
    }
    await library.forgetNotFound();
    _done(l10n.cacheSettingsScreenNotFoundForgotten);
  }

  Future<void> _pickPrefetch(SourceSettings settings) async {
    final count = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.cacheSettingsScreenPrefetchTitle),
        children: [
          for (var n = 1; n <= SourceSettings.maxQueuePrefetch; n++)
            ListTile(
              title: Text(_nextSongs(n)),
              trailing: n == settings.queuePrefetch
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(n),
            ),
        ],
      ),
    );
    if (count != null) await settings.setQueuePrefetch(count);
  }

  Future<void> _pickCoverLimit(SourceSettings settings) async {
    final mb = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.cacheSettingsScreenCoverLimitTitle),
        children: [
          for (final mb in _coverLimits)
            ListTile(
              title: Text('$mb MB'),
              trailing: mb == settings.coverCacheLimitMb
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(mb),
            ),
        ],
      ),
    );
    if (mb != null) await settings.setCoverCacheLimitMb(mb);
    if (mounted) setState(() {});
  }

  Future<void> _clearCovers(AlbumCovers covers) async {
    if (!await _confirm(
      l10n.cacheSettingsScreenClearCoversTitle,
      l10n.cacheSettingsScreenClearCoversBody,
    )) {
      return;
    }
    await covers.clear();
    _done(l10n.cacheSettingsScreenCoversCleared);
  }

  Future<void> _clearAll(AlbumCovers? covers) async {
    final library = YouTubeLibraryScope.of(context);
    if (!await _confirm(
      l10n.cacheSettingsScreenClearAllTitle,
      l10n.cacheSettingsScreenClearAllBody,
    )) {
      return;
    }
    await library.clearCache();
    await covers?.clear();
    _done(l10n.cacheSettingsScreenAllCleared);
  }

  Future<void> _removeDownloads(Downloads downloads) async {
    if (!await _confirm(
      l10n.cacheSettingsScreenRemoveDownloadsTitle,
      l10n.cacheSettingsScreenRemoveDownloadsBody,
      action: l10n.commonDelete,
    )) {
      return;
    }
    await downloads.removeAll();
    _done(l10n.cacheSettingsScreenDownloadsRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final downloads = DownloadsScope.maybeOf(context);
    final library = YouTubeLibraryScope.of(context);
    final covers = AlbumCoversScope.maybeOf(context);
    final songsOn = settings.playbackMethods.contains(
      YouTubePlaybackMethod.cache,
    );
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.cacheSettingsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.cacheSettingsScreenTotal(_mb(cacheBytesOf(context))),
              style: hint,
            ),
          ),
          if (downloads != null) ...[
            SectionTitle(l10n.cacheSettingsScreenDownloadsSection),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: Text(l10n.cacheSettingsScreenDownloadedSongs),
              subtitle: Text(
                l10n.cacheSettingsScreenSongsAndSize(
                  l10n.songsCount(downloads.count),
                  _mb(downloads.bytes),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadedSongsScreen(),
                ),
              ),
            ),
            ListTile(
              enabled: downloads.count > 0,
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.cacheSettingsScreenRemoveDownloads),
              onTap: () => _removeDownloads(downloads),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(l10n.cacheSettingsScreenDownloadsNote, style: hint),
            ),
          ],
          SectionTitle(l10n.cacheSettingsScreenYouTubeSongsSection),
          ListTile(
            enabled: songsOn,
            leading: const Icon(Icons.library_music_outlined),
            title: Text(l10n.cacheSettingsScreenSongLimit),
            subtitle: Text(
              songsOn
                  ? '${settings.cacheLimit}'
                  : l10n.cacheSettingsScreenSongsOff,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editSongLimit(settings),
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.cacheSettingsScreenUsedSpace),
            subtitle: Text(
              l10n.cacheSettingsScreenSongsAndSize(
                l10n.songsCount(library.cachedCount),
                _mb(library.cachedBytes),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CacheContentsScreen(),
              ),
            ),
          ),
          ListTile(
            enabled: library.cachedCount > 0,
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.cacheSettingsScreenClearSongs),
            onTap: _clearSongs,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(l10n.cacheSettingsScreenEvictionNote, style: hint),
          ),
          SectionTitle(l10n.cacheSettingsScreenQueueSection),
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: Text(l10n.cacheSettingsScreenPrefetch),
            subtitle: Text(
              songsOn
                  ? l10n.cacheSettingsScreenPrefetchOn
                  : l10n.cacheSettingsScreenPrefetchNeedsCache,
            ),
            value: settings.queuePrefetchEnabled,
            onChanged: settings.setQueuePrefetchEnabled,
          ),
          ListTile(
            enabled: settings.queuePrefetchEnabled,
            leading: const Icon(Icons.queue_music),
            title: Text(l10n.cacheSettingsScreenPrefetchCount),
            subtitle: Text(_nextSongs(settings.queuePrefetch)),
            onTap: () => _pickPrefetch(settings),
          ),
          SectionTitle(l10n.cacheSettingsScreenMatchesSection),
          ListTile(
            enabled: library.phoneMatchCount > 0,
            leading: const Icon(Icons.youtube_searched_for),
            title: Text(l10n.cacheSettingsScreenForgetMatches),
            subtitle: Text(
              l10n.cacheSettingsScreenMatchesCount(
                l10n.songsCount(library.phoneMatchCount),
              ),
            ),
            onTap: _forgetMatches,
          ),
          ListTile(
            enabled: library.notFoundCount > 0,
            leading: const Icon(Icons.search_off),
            title: Text(l10n.cacheSettingsScreenForgetNotFound),
            subtitle: Text(
              l10n.cacheSettingsScreenNotFoundCount(
                l10n.songsCount(library.notFoundCount),
              ),
            ),
            onTap: _forgetNotFound,
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0)),
          if (covers != null) ...[
            SectionTitle(l10n.cacheSettingsScreenCoversSection),
            ListTile(
              leading: const Icon(Icons.photo_size_select_large_outlined),
              title: Text(l10n.cacheSettingsScreenCoverSize),
              subtitle: Text('${settings.coverCacheLimitMb} MB'),
              onTap: () => _pickCoverLimit(settings),
            ),
            ListTile(
              enabled: covers.cachedCount > 0,
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.cacheSettingsScreenClearCovers),
              subtitle: Text(
                l10n.cacheSettingsScreenCoversUsed(
                  _mb(covers.cachedBytes),
                  covers.cachedCount,
                ),
              ),
              onTap: () => _clearCovers(covers),
            ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: palette.accent),
            title: Text(l10n.cacheSettingsScreenClearAll),
            subtitle: Text(l10n.cacheSettingsScreenClearAllSubtitle),
            onTap: () => _clearAll(covers),
          ),
        ],
      ),
    );
  }
}

/// "1 następny utwór", "3 następne utwory", "5 następnych utworów".
String _nextSongs(int n) => l10n.cacheSettingsScreenNextSongs(n);

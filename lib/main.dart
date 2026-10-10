import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/data/database_sync.dart';
import 'src/data/local_library.dart';
import 'src/data/song_catalog.dart';
import 'src/playback/player_controller.dart';
import 'src/screens/app_shell.dart';
import 'src/theme.dart';
import 'src/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loaded before the first frame so the app doesn't flash the default theme on start.
  final themeController = ThemeController();
  try {
    await themeController.load();
  } catch (e) {
    debugPrint('Loading appearance settings failed: $e');
  }
  runApp(MusicDatabaseApp(themeController: themeController));
}

class MusicDatabaseApp extends StatefulWidget {
  const MusicDatabaseApp({super.key, this.themeController});

  /// Already-loaded appearance settings; when omitted (tests) defaults are loaded in the
  /// background.
  final ThemeController? themeController;

  @override
  State<MusicDatabaseApp> createState() => _MusicDatabaseAppState();
}

class _MusicDatabaseAppState extends State<MusicDatabaseApp> {
  late final ThemeController _themeController =
      widget.themeController ?? (ThemeController()..load());
  final _databaseSync = DatabaseSync();
  late final _songCatalog = SongCatalog(_databaseSync);
  late final _localLibrary = LocalLibrary(_songCatalog);
  final _player = PlayerController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _startDatabaseSync();
    _localLibrary.load().catchError(
      (Object e) => debugPrint('Loading local library failed: $e'),
    );
    // Android often keeps the app alive for days, so "once a day on start" also has to cover
    // coming back to an app that was only in the background.
    _lifecycle = AppLifecycleListener(onResume: _databaseSync.syncIfDue);
  }

  Future<void> _startDatabaseSync() async {
    try {
      await _databaseSync.load();
      await _databaseSync.syncIfDue();
    } catch (e) {
      debugPrint('Database sync on start failed: $e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _player.dispose();
    _localLibrary.dispose();
    _songCatalog.dispose();
    _databaseSync.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DatabaseSyncScope(
      notifier: _databaseSync,
      child: SongCatalogScope(
        notifier: _songCatalog,
        child: LocalLibraryScope(
          notifier: _localLibrary,
          child: PlayerScope(
            notifier: _player,
            child: ThemeScope(
              notifier: _themeController,
              child: ListenableBuilder(
                listenable: _themeController,
                builder: (context, _) => MaterialApp(
                  title: 'MusicDatabase',
                  debugShowCheckedModeBanner: false,
                  theme: buildAppTheme(_themeController.light),
                  darkTheme: buildAppTheme(_themeController.dark),
                  themeMode: _themeController.themeMode,
                  // Tab screens have no AppBar to set the status-bar icon colour, so match it to
                  // the active theme here (dark icons on light themes and vice versa).
                  builder: (context, child) =>
                      AnnotatedRegion<SystemUiOverlayStyle>(
                        value: Theme.of(context).brightness == Brightness.light
                            ? SystemUiOverlayStyle.dark
                            : SystemUiOverlayStyle.light,
                        child: child!,
                      ),
                  home: const AppShell(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

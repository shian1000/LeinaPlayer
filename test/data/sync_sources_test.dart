import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/sync_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a private server first, the Leina server off and not to be switched on',
    () async {
      final sources = SyncSources();
      await sources.load();
      expect(sources.order(SyncFeature.database), [
        SyncSource.privateServer,
        SyncSource.gitHub,
        SyncSource.leina,
      ]);
      expect(sources.enabled(SyncFeature.database), [
        SyncSource.privateServer,
        SyncSource.gitHub,
      ]);
      await sources.setOn(SyncFeature.library, SyncSource.leina, true);
      expect(sources.isOn(SyncFeature.library, SyncSource.leina), isFalse);
      expect(sources.enabled(SyncFeature.errorReports), isEmpty);
    },
  );

  test(
    'switches and order are each function\'s own and survive a restart',
    () async {
      final sources = SyncSources();
      await sources.load();
      await sources.setOn(SyncFeature.library, SyncSource.privateServer, false);
      await sources.move(SyncFeature.requests, 1, 0);

      final again = SyncSources();
      await again.load();
      expect(
        again.isOn(SyncFeature.library, SyncSource.privateServer),
        isFalse,
      );
      expect(
        again.isOn(SyncFeature.requests, SyncSource.privateServer),
        isTrue,
      );
      expect(again.order(SyncFeature.requests), [
        SyncSource.leina,
        SyncSource.privateServer,
      ]);
      expect(again.order(SyncFeature.library), [
        SyncSource.privateServer,
        SyncSource.leina,
      ]);
    },
  );

  test('the catalog\'s GitHub switch keeps its old key', () async {
    SharedPreferences.setMockInitialValues({'database_sync.github_on': false});
    final sources = SyncSources();
    await sources.load();
    expect(sources.isOn(SyncFeature.database, SyncSource.gitHub), isFalse);
  });

  test(
    'a stored order missing a source gets it back at its default end',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_sources.database.order': ['gitHub', 'unknown'],
      });
      final sources = SyncSources();
      await sources.load();
      expect(sources.order(SyncFeature.database), [
        SyncSource.gitHub,
        SyncSource.privateServer,
        SyncSource.leina,
      ]);
    },
  );
}

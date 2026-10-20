import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/auto_backup_section.dart';
import 'package:beand/services/auto_backup.dart';
import 'package:beand/services/backup_service.dart';
import 'package:beand/sync/crypto/backup_cipher.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:beand/sync/sync_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saf_folder/saf_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('schedule', () {
    // Tuesday, 20 Oct 2026.
    final tuesdayNoon = DateTime(2026, 10, 20, 12);

    test('daily: latest slot today if past, next one tomorrow', () {
      const c = AutoBackupConfig(
        frequency: AutoBackupFrequency.daily,
        minuteOfDay: 3 * 60 + 30,
      );
      expect(c.latestSlot(tuesdayNoon), DateTime(2026, 10, 20, 3, 30));
      expect(c.nextSlot(tuesdayNoon), DateTime(2026, 10, 21, 3, 30));
    });

    test('weekly: lands on the chosen weekday', () {
      const c = AutoBackupConfig(
        frequency: AutoBackupFrequency.weekly,
        weekday: DateTime.sunday,
        minuteOfDay: 22 * 60,
      );
      expect(c.latestSlot(tuesdayNoon), DateTime(2026, 10, 18, 22));
      expect(c.nextSlot(tuesdayNoon), DateTime(2026, 10, 25, 22));
      // On the day itself, before and after the time.
      expect(
        c.nextSlot(DateTime(2026, 10, 25, 21)),
        DateTime(2026, 10, 25, 22),
      );
      expect(c.nextSlot(DateTime(2026, 10, 25, 23)), DateTime(2026, 11, 1, 22));
    });

    test('off has no slots', () {
      const c = AutoBackupConfig();
      expect(c.latestSlot(tuesdayNoon), isNull);
      expect(c.nextSlot(tuesdayNoon), isNull);
      expect(c.isDue(tuesdayNoon), isFalse);
    });

    test('due only for a slot after the last backup and after arming', () {
      final c = AutoBackupConfig(
        frequency: AutoBackupFrequency.daily,
        minuteOfDay: 3 * 60,
        folderUri: 'content://folder',
        // Turned on at 11:00 — the 03:00 slot before that is not missed.
        armedAt: DateTime(2026, 10, 20, 11),
      );
      expect(c.isDue(tuesdayNoon), isFalse);
      // Next morning it is.
      expect(c.isDue(DateTime(2026, 10, 21, 3, 5)), isTrue);
      // ... unless that backup already happened.
      final done = c.copyWith(lastAt: DateTime(2026, 10, 21, 3, 1));
      expect(done.isDue(DateTime(2026, 10, 21, 9)), isFalse);
    });

    test('never due without a folder', () {
      const c = AutoBackupConfig(frequency: AutoBackupFrequency.daily);
      expect(c.isDue(DateTime(2026, 10, 20, 12)), isFalse);
    });
  });

  group('run', () {
    late Directory root;
    late Directory docs;
    late Directory folder;
    late AppDatabase db;
    late List<Duration?> scheduled;
    late DateTime now;
    var failWrite = false;
    late InMemoryAutoBackupPassword password;
    late InMemorySyncKeyStore keys;
    late SyncIdentity identity;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('beand_auto_backup');
      docs = Directory(p.join(root.path, 'docs'))..createSync();
      folder = Directory(p.join(root.path, 'folder'))..createSync();
      SharedPreferences.setMockInitialValues({'theme': 'dark'});
      db = AppDatabase(
        NativeDatabase(File(p.join(docs.path, backupDbFileName))),
      );
      await db.into(db.beans).insert(BeansCompanion.insert(name: 'Guji'));
      scheduled = [];
      now = DateTime(2026, 10, 21, 3, 2);
      failWrite = false;
      password = InMemoryAutoBackupPassword();
      keys = InMemorySyncKeyStore();
      identity = SyncIdentity.generate();
      await keys.writeIdentity(identity);
    });

    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    AutoBackup make() => AutoBackup(
      store: AutoBackupStore(File(p.join(root.path, 'support', 'ab.json'))),
      openService: () async => BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
      ),
      workDir: () async => Directory(p.join(root.path, 'cache')),
      password: password,
      syncInfo: (pw) => readSyncInfo(
        pw,
        keyStore: keys,
        stateStore: InMemorySyncStateStore(),
      ),
      writeToFolder: (uri, name, source) async {
        if (failWrite) throw const BackupException('Folder is gone');
        File(source).copySync(p.join(folder.path, name));
      },
      schedule: (delay) async => scheduled.add(delay),
      now: () => now,
    );

    Future<void> arm(AutoBackup backup) => backup.store.save(
      AutoBackupConfig(
        frequency: AutoBackupFrequency.daily,
        minuteOfDay: 3 * 60,
        folderUri: 'content://folder',
        armedAt: DateTime(2026, 10, 20, 12),
      ),
    );

    test('a missed slot writes the backup and queues the next one', () async {
      final backup = make();
      await arm(backup);

      final config = await backup.run();

      final file = File(p.join(folder.path, AutoBackup.fileName));
      expect(file.existsSync(), isTrue);
      final manifest = await BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
      ).readManifest(file);
      expect(manifest.beans, 1);
      expect(manifest.syncNpub, isNull, reason: 'no password, no sync key');
      expect(config.lastAt, now);
      expect(config.lastBytes, file.lengthSync());
      expect(config.lastError, isNull);
      // Next: tomorrow 03:00.
      expect(scheduled.last, DateTime(2026, 10, 22, 3).difference(now));
      // The work folder is cleaned up.
      expect(Directory(p.join(root.path, 'cache')).existsSync(), isFalse);
    });

    test('not due: nothing written, only queued', () async {
      final backup = make();
      await arm(backup);
      now = DateTime(2026, 10, 20, 13);

      final config = await backup.run();

      expect(
        File(p.join(folder.path, AutoBackup.fileName)).existsSync(),
        isFalse,
      );
      expect(config.lastAt, isNull);
      expect(scheduled.last, DateTime(2026, 10, 21, 3).difference(now));
    });

    test('the same file is overwritten each time', () async {
      final backup = make();
      await arm(backup);
      await backup.run();
      await db.into(db.beans).insert(BeansCompanion.insert(name: 'Sidamo'));
      now = DateTime(2026, 10, 22, 3, 1);

      await backup.run();

      expect(folder.listSync(), hasLength(1));
      final manifest = await BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
      ).readManifest(File(p.join(folder.path, AutoBackup.fileName)));
      expect(manifest.beans, 2);
    });

    test('a failure is recorded and retried later', () async {
      final backup = make();
      await arm(backup);
      failWrite = true;

      final config = await backup.run();

      expect(config.lastError, 'Folder is gone');
      expect(config.lastErrorAt, now);
      expect(config.lastAt, isNull);
      expect(scheduled.last, AutoBackup.retryDelay);
      // Still due, so the next app start tries again.
      expect(config.isDue(now), isTrue);

      // The next success clears the error.
      failWrite = false;
      final ok = await backup.run();
      expect(ok.lastError, isNull);
      expect(ok.lastAt, now);
    });

    test('"Back up now" runs even when not due', () async {
      final backup = make();
      await arm(backup);
      now = DateTime(2026, 10, 20, 13);

      final config = await backup.run(force: true);

      expect(
        File(p.join(folder.path, AutoBackup.fileName)).existsSync(),
        isTrue,
      );
      expect(config.lastAt, now);
    });

    test('turned off: the queued run is cancelled', () async {
      final backup = make();
      await backup.store.save(
        const AutoBackupConfig(folderUri: 'content://folder'),
      );
      await backup.run();
      expect(scheduled.last, isNull);
    });

    test('with a password the sync key goes in, locked with it', () async {
      final backup = make();
      await arm(backup);
      await password.write('correct horse');

      await backup.run();

      final file = File(p.join(folder.path, AutoBackup.fileName));
      final service = BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
      );
      expect((await service.readManifest(file)).syncNpub, identity.npub);
      final info = await service.readSyncInfo(file);
      final key = await SyncService.decryptBackupKey(info!, 'correct horse');
      expect(key, identity.privateKeyBytes);
    });

    test('encrypted: the whole file is locked, under its own name', () async {
      final backup = make();
      await backup.store.save(
        AutoBackupConfig(
          frequency: AutoBackupFrequency.daily,
          minuteOfDay: 3 * 60,
          folderUri: 'content://folder',
          encrypt: true,
          armedAt: DateTime(2026, 10, 20, 12),
        ),
      );
      await password.write('correct horse');

      final config = await backup.run();

      expect(config.lastError, isNull);
      final file = File(p.join(folder.path, AutoBackup.encryptedFileName));
      expect(isEncryptedBackup(file), isTrue);
      final service = BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
      );
      final plain = await service.decryptBackup(
        file,
        'correct horse',
        targetDir: Directory(p.join(root.path, 'plain')),
      );
      expect((await service.readManifest(plain)).beans, 1);
    });

    test(
      'encrypted without a stored password: fails, writes nothing',
      () async {
        final backup = make();
        await backup.store.save(
          AutoBackupConfig(
            frequency: AutoBackupFrequency.daily,
            folderUri: 'content://folder',
            encrypt: true,
            armedAt: DateTime(2026, 10, 20, 0, 1),
          ),
        );

        final config = await backup.run();

        expect(config.lastError, contains('password'));
        expect(folder.listSync(), isEmpty);
      },
    );

    testWidgets('section: picking schedule and folder saves and queues', (
      tester,
    ) async {
      // File access runs for real: let it finish and the results arrive.
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      late AutoBackup backup;
      await tester.runAsync(() async {
        backup = make();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              children: [
                AutoBackupSection(
                  backup: () async => backup,
                  pickFolder: () async =>
                      const SafFolder(uri: 'content://picked', name: 'Backups'),
                ),
              ],
            ),
          ),
        ),
      );
      await settle();

      // Off: only the schedule.
      expect(find.text('Folder'), findsNothing);
      await tester.tap(find.text('Weekly'));
      await settle();
      expect(find.text('Su'), findsOneWidget);
      // Without sync no dialog pops up; the row says what is missing.
      expect(find.text('Not set'), findsOneWidget);

      await tester.tap(find.text('Folder'));
      await settle();
      expect(find.text('Backups'), findsOneWidget);

      final saved = await tester.runAsync(() => backup.store.load());
      expect(saved!.frequency, AutoBackupFrequency.weekly);
      expect(saved.folderUri, 'content://picked');
      expect(saved.armedAt, isNotNull);
      expect(scheduled.last, isNotNull);
    });
  });
}

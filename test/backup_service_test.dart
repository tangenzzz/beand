import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:beand/database/database.dart';
import 'package:beand/services/backup_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beand_backup_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Creates an app folder with a database and returns both.
  Future<(Directory, AppDatabase)> makeDocs(String name) async {
    final docs = Directory(p.join(root.path, name))
      ..createSync(recursive: true);
    final db = AppDatabase(
      NativeDatabase(File(p.join(docs.path, backupDbFileName))),
    );
    return (docs, db);
  }

  Future<BackupService> serviceFor(Directory docs, AppDatabase db) async =>
      BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
        openRestoredDb: (file) => AppDatabase(NativeDatabase(file)),
      );

  /// A bean with a photo, a shot, a profile — plus the photo file itself.
  Future<void> seed(Directory docs, AppDatabase db) async {
    final photoDir = Directory(p.join(docs.path, 'bean_photos'))
      ..createSync(recursive: true);
    final photo = File(p.join(photoDir.path, 'bean_1.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final beanId = await db
        .into(db.beans)
        .insert(
          BeansCompanion.insert(name: 'Guji', photoPath: Value(photo.path)),
        );
    await db
        .into(db.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 9, 27, 8, 30),
            beanId: Value(beanId),
            notes: const Value('sweet'),
          ),
        );
    await db
        .into(db.storedProfiles)
        .insert(
          StoredProfilesCompanion.insert(
            id: 'p1',
            name: 'Damians LRV2',
            json: '{"name":"Damians LRV2"}',
            fetchedAt: DateTime(2026, 9, 26),
          ),
        );
  }

  test('Backup contains database, photos, settings and counts them', () async {
    final (docs, db) = await makeDocs('docs');
    await seed(docs, db);
    SharedPreferences.setMockInitialValues({
      'machine_hostname': 'machine.local',
      'beans_show_freshness_ring': false,
      'beans_form_order': <String>['name', 'roaster'],
    });

    final service = await serviceFor(docs, db);
    final zip = await service.createBackup(
      targetDir: Directory(p.join(root.path, 'out')),
      now: DateTime(2026, 9, 27, 18, 30),
    );

    expect(p.basename(zip.path), 'beand-backup-2026-09-27-1830.zip');
    expect(zip.lengthSync(), greaterThan(0));

    final manifest = await service.readManifest(zip);
    expect(manifest.format, backupFormatVersion);
    expect(manifest.schemaVersion, db.schemaVersion);
    expect(manifest.beans, 1);
    expect(manifest.shots, 1);
    expect(manifest.profiles, 1);
    expect(manifest.photos, 1); // the bean photo file, without the DB
    expect(manifest.settings, 3);
    expect(manifest.docsPath, docs.path);

    await db.close();
  });

  test('Restore brings back data, photo and settings and '
      'redirects image paths to the new folder', () async {
    // Back up the source ...
    final (docs, db) = await makeDocs('docs');
    await seed(docs, db);
    SharedPreferences.setMockInitialValues({
      'machine_hostname': 'machine.local',
      'beans_show_freshness_ring': false,
    });
    final source = await serviceFor(docs, db);
    final zip = await source.createBackup(
      targetDir: Directory(p.join(root.path, 'out')),
    );
    await db.close();

    // ... and restore into another app folder with different content.
    final (other, otherDb) = await makeDocs('docs_other');
    await otherDb
        .into(otherDb.beans)
        .insert(BeansCompanion.insert(name: 'Wird ersetzt'));
    SharedPreferences.setMockInitialValues({'machine_hostname': 'stale.local'});
    final target = await serviceFor(other, otherDb);

    final manifest = await target.restore(zip);
    expect(manifest.beans, 1);

    // Open fresh, like the app after the restart.
    final restored = AppDatabase(
      NativeDatabase(File(p.join(other.path, backupDbFileName))),
    );
    final beans = await restored.select(restored.beans).get();
    expect(beans.map((b) => b.name), ['Guji']);
    expect(
      beans.single.photoPath,
      p.join(other.path, 'bean_photos', 'bean_1.jpg'),
      reason: 'Path must point to the new app folder',
    );
    expect(File(beans.single.photoPath!).existsSync(), isTrue);
    expect((await restored.select(restored.shots).get()).length, 1);
    expect((await restored.select(restored.storedProfiles).get()).length, 1);
    await restored.close();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('machine_hostname'), 'machine.local');
    expect(prefs.getBool('beans_show_freshness_ring'), isFalse);
  });

  test('A foreign file is rejected with a clear message', () async {
    final (docs, db) = await makeDocs('docs');
    final service = await serviceFor(docs, db);
    final junk = File(p.join(root.path, 'notes.txt'))
      ..writeAsStringSync('kein Zip');

    await expectLater(
      service.readManifest(junk),
      throwsA(isA<BackupException>()),
    );
    // The database stays untouched.
    expect(await db.customSelect('SELECT 1').get(), hasLength(1));
    await db.close();
  });

  test('Backup from a newer schema version is rejected', () async {
    final (docs, db) = await makeDocs('docs');
    final service = await serviceFor(docs, db);
    final zip = await service.createBackup(
      targetDir: Directory(p.join(root.path, 'out')),
    );

    // Rewrite the manifest to a higher schema version.
    final tampered = File(p.join(root.path, 'tampered.zip'));
    _rewriteManifest(zip, tampered, db.schemaVersion + 1);

    await expectLater(
      service.readManifest(tampered),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('newer database version'),
        ),
      ),
    );
    await db.close();
  });
}

/// Copies [source] to [target], replacing the schemaVersion in the
/// manifest — simulates a backup from a newer app version.
void _rewriteManifest(File source, File target, int schemaVersion) {
  final archive = ZipDecoder().decodeBytes(source.readAsBytesSync());
  final out = Archive();
  for (final entry in archive.files) {
    if (entry.name == 'manifest.json') {
      final json = utf8.decode(entry.content as List<int>);
      final patched = json.replaceAll(
        RegExp(r'"schemaVersion": \d+'),
        '"schemaVersion": $schemaVersion',
      );
      final bytes = utf8.encode(patched);
      out.addFile(ArchiveFile(entry.name, bytes.length, bytes));
    } else {
      out.addFile(entry);
    }
  }
  target.writeAsBytesSync(ZipEncoder().encode(out)!);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:beand/database/database.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/auto_backup.dart';
import 'package:beand/services/backup_service.dart';
import 'package:beand/services/restore_swap.dart';
import 'package:beand/sync/crypto/backup_cipher.dart';
import 'package:beand/sync/crypto/nip49.dart';
import 'package:beand/sync/crypto/nostr_bech32.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Findings of the backup review (2026-11). Each test describes the safe state.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late SharedPreferences prefs;
  final databases = <AppDatabase>[];

  setUp(() async {
    root = Directory.systemTemp.createTempSync('beand_backup_regression_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    for (final db in databases.reversed) {
      try {
        await db.close();
      } catch (_) {}
    }
    databases.clear();
    root.deleteSync(recursive: true);
  });

  Future<BackupService> service(String name) async {
    final docs = Directory(p.join(root.path, name))..createSync();
    final db = AppDatabase(
      NativeDatabase(File(p.join(docs.path, backupDbFileName))),
    );
    databases.add(db);
    await db.insertBean(BeansCompanion.insert(name: name));
    return BackupService(db: db, docsDir: docs, prefs: prefs);
  }

  Future<File> backupOf(BackupService s) => s.createBackup(
    targetDir: Directory(
      p.join(root.path, 'export-${p.basename(s.docsDir.path)}'),
    ),
  );

  File rewriteZip(
    File input,
    String name,
    Map<String, List<int>> replacements, {
    List<ArchiveFile> extra = const [],
    bool store = false,
  }) {
    final old = ZipDecoder().decodeBytes(input.readAsBytesSync());
    final archive = Archive();
    for (final entry in old.files) {
      final bytes = replacements[entry.name] ?? entry.content as List<int>;
      archive.addFile(
        store
            ? ArchiveFile.noCompress(entry.name, bytes.length, bytes)
            : ArchiveFile(entry.name, bytes.length, bytes),
      );
    }
    extra.forEach(archive.addFile);
    return File(p.join(root.path, name))
      ..writeAsBytesSync(ZipEncoder().encode(archive)!);
  }

  String beanNameIn(Directory docs) {
    final raw = sql.sqlite3.open(p.join(docs.path, backupDbFileName));
    try {
      return raw.select('SELECT name FROM beans').single['name'] as String;
    } finally {
      raw.close();
    }
  }

  List<String> workFolders(Directory docs) => docs
      .listSync()
      .map((e) => p.basename(e.path))
      .where(isRestoreWorkPath)
      .toList();

  group('a rejected backup leaves everything as it was', () {
    Future<void> expectRejected(BackupService target, File zip) async {
      final photo = File(p.join(target.docsDir.path, 'only-photo.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      await expectLater(target.restore(zip), throwsA(isA<BackupException>()));
      expect(beanNameIn(target.docsDir), p.basename(target.docsDir.path));
      expect(photo.readAsBytesSync(), [1, 2, 3]);
      expect(workFolders(target.docsDir), isEmpty);
      // The app can go on: the connection was not closed.
      await target.db.insertBean(BeansCompanion.insert(name: 'still open'));
    }

    test('a file that is no database', () async {
      final zip = rewriteZip(
        await backupOf(await service('source')),
        'bad.zip',
        {'files/$backupDbFileName': utf8.encode('not a database')},
      );
      await expectRejected(await service('target'), zip);
    });

    test('a truncated database', () async {
      final source = await service('source');
      final plain = await backupOf(source);
      final bytes =
          ZipDecoder()
                  .decodeBytes(plain.readAsBytesSync())
                  .findFile('files/$backupDbFileName')!
                  .content
              as List<int>;
      final zip = rewriteZip(plain, 'cut.zip', {
        'files/$backupDbFileName': bytes.sublist(0, bytes.length ~/ 2),
      });
      await expectRejected(await service('target'), zip);
    });

    test('a damaged entry, recognised by its checksum', () async {
      const marker = 'UNIQUE_MARKER_FOR_THE_REVIEW';
      final zip = rewriteZip(
        await backupOf(await service('source')),
        'crc.zip',
        {},
        extra: [
          ArchiveFile.noCompress(
            'files/photo.jpg',
            marker.length,
            utf8.encode(marker),
          ),
        ],
        store: true,
      );
      final bytes = zip.readAsBytesSync();
      bytes[latin1.decode(bytes).indexOf(marker)] ^= 1;
      zip.writeAsBytesSync(bytes);
      await expectRejected(await service('target'), zip);
    });

    test('an entry larger than it declares', () async {
      final bomb = Uint8List(1 << 16);
      final zip = rewriteZip(
        await backupOf(await service('source')),
        'bomb.zip',
        {},
        extra: [ArchiveFile('files/bomb.bin', bomb.length, bomb)],
      );
      final bytes = zip.readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i + 46 < bytes.length; i++) {
        final signature = data.getUint32(i, Endian.little);
        if (signature != 0x04034b50 && signature != 0x02014b50) continue;
        final local = signature == 0x04034b50;
        final nameAt = i + (local ? 30 : 46);
        final nameLength = data.getUint16(i + (local ? 26 : 28), Endian.little);
        if (nameAt + nameLength > bytes.length) continue;
        final name = latin1.decode(bytes.sublist(nameAt, nameAt + nameLength));
        if (name != 'files/bomb.bin') continue;
        data.setUint32(i + (local ? 22 : 24), 1, Endian.little);
      }
      zip.writeAsBytesSync(bytes);
      await expectRejected(await service('target'), zip);
    });

    test('a database newer than the manifest claims', () async {
      final source = await service('source');
      await source.db.customStatement('PRAGMA user_version=29');
      await expectRejected(await service('target'), await backupOf(source));
    });
  });

  test('a good backup replaces the old files completely', () async {
    final source = await service('source');
    File(p.join(source.docsDir.path, 'photo.jpg')).writeAsBytesSync([7]);
    final zip = await backupOf(source);
    final target = await service('target');
    File(p.join(target.docsDir.path, 'leftover.jpg')).writeAsBytesSync([9]);

    await target.restore(zip);

    expect(beanNameIn(target.docsDir), 'source');
    expect(File(p.join(target.docsDir.path, 'photo.jpg')).existsSync(), isTrue);
    expect(
      File(p.join(target.docsDir.path, 'leftover.jpg')).existsSync(),
      isFalse,
    );
    expect(workFolders(target.docsDir), isEmpty);
  });

  group('a restore cut off', () {
    late Directory docs;

    File inDocs(String name) => File(p.join(docs.path, name));

    Directory staged(List<String> files) {
      final dir = restoreStagingDir(docs)..createSync();
      for (final name in files) {
        File(p.join(dir.path, name)).writeAsStringSync('new');
      }
      return dir;
    }

    Directory previous(List<String> files, {bool allMoved = false}) {
      final dir = Directory(p.join(docs.path, '.restore-old'))..createSync();
      for (final name in files) {
        File(p.join(dir.path, name)).writeAsStringSync('old');
      }
      if (allMoved) File(p.join(dir.path, '.moved')).createSync();
      return dir;
    }

    setUp(() => docs = Directory(p.join(root.path, 'docs'))..createSync());

    test('while unpacking keeps the old files', () {
      inDocs('a').writeAsStringSync('old');
      staged(['a']);
      recoverInterruptedRestore(docs);
      expect(inDocs('a').readAsStringSync(), 'old');
      expect(workFolders(docs), isEmpty);
    });

    test('while the old files move out brings them all back', () {
      inDocs('a').writeAsStringSync('old');
      previous(['b']);
      staged(['a', 'b']);
      recoverInterruptedRestore(docs);
      expect(inDocs('a').readAsStringSync(), 'old');
      expect(inDocs('b').readAsStringSync(), 'old');
      expect(workFolders(docs), isEmpty);
    });

    test('while the new files move in brings the old ones back', () {
      inDocs('new-only').writeAsStringSync('new');
      previous(['a', 'b'], allMoved: true);
      staged(['c']);
      recoverInterruptedRestore(docs);
      expect(inDocs('a').readAsStringSync(), 'old');
      expect(inDocs('b').readAsStringSync(), 'old');
      expect(inDocs('new-only').existsSync(), isFalse);
      expect(inDocs('.moved').existsSync(), isFalse);
      expect(workFolders(docs), isEmpty);
    });

    test('after the swap only drops the old copy', () {
      inDocs('a').writeAsStringSync('new');
      previous(['a'], allMoved: true);
      recoverInterruptedRestore(docs);
      expect(inDocs('a').readAsStringSync(), 'new');
      expect(workFolders(docs), isEmpty);
    });

    test('leaves nothing of itself in the next backup', () async {
      final s = await service('source');
      docs = s.docsDir;
      staged(['stray']);
      final archive = ZipDecoder().decodeBytes(
        (await backupOf(s)).readAsBytesSync(),
      );
      expect(archive.files.where((f) => f.name.contains('stray')), isEmpty);
    });
  });

  test('a backup includes what another connection cannot checkpoint', () async {
    final s = await service('wal');
    await s.db.customStatement('PRAGMA journal_mode=WAL');
    await s.db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final reader = sql.sqlite3.open(p.join(s.docsDir.path, backupDbFileName));
    addTearDown(reader.close);
    reader.execute('BEGIN');
    expect(reader.select('SELECT name FROM beans'), hasLength(1));
    await s.db.insertBean(BeansCompanion.insert(name: 'committed'));

    final archive = ZipDecoder().decodeBytes(
      (await backupOf(s)).readAsBytesSync(),
    );
    reader.execute('ROLLBACK');
    final copy = File(p.join(root.path, 'copy.sqlite'))
      ..writeAsBytesSync(
        archive.findFile('files/$backupDbFileName')!.content as List<int>,
      );
    final raw = sql.sqlite3.open(copy.path);
    addTearDown(raw.close);
    expect(raw.select('SELECT name FROM beans'), hasLength(2));
  });

  test('AI consent neither leaves the device nor arrives in a file', () async {
    await prefs.setStringList(AiSettings.consentPrefKey, ['my-server.example']);
    final source = await service('source');
    final plain = await backupOf(source);
    final written = jsonDecode(
      utf8.decode(
        ZipDecoder()
                .decodeBytes(plain.readAsBytesSync())
                .findFile('prefs.json')!
                .content
            as List<int>,
      ),
    ) as Map;
    expect(written.containsKey(AiSettings.consentPrefKey), isFalse);

    final zip = rewriteZip(plain, 'hostile.zip', {
      'prefs.json': utf8.encode(
        jsonEncode({
          AiSettings.enabledPrefKey: {'type': 'bool', 'value': true},
          AiSettings.providerPrefKey: {
            'type': 'string',
            'value': AiProvider.compatible.name,
          },
          AiSettings.baseUrlPrefKey: {
            'type': 'string',
            'value': 'https://attacker.invalid/v1',
          },
          AiSettings.consentPrefKey: {
            'type': 'stringList',
            'value': ['attacker.invalid'],
          },
        }),
      ),
    });
    await (await service('target')).restore(zip);

    final keys = InMemoryAiKeyStore();
    await keys.write(AiProvider.compatible, 'local-test-key');
    final ai = await AiSettings.load(keyStore: keys);
    addTearDown(ai.dispose);
    expect(ai.recipientAddress, 'attacker.invalid');
    expect(ai.hasConsent, isFalse);
  });

  test('a failed safety copy keeps the previous one', () async {
    final s = await service('safety');
    final dir = Directory(p.join(root.path, 'safety-copy'));
    final expected = (await s.createSafetyCopy(dir)).readAsBytesSync();

    await s.db.close();
    await expectLater(s.createSafetyCopy(dir), throwsA(anything));

    expect(BackupService.safetyCopyIn(dir)!.readAsBytesSync(), expected);
    expect(Directory('${dir.path}.new').existsSync(), isFalse);
  });

  test('a new safety copy replaces the previous one', () async {
    final s = await service('safety');
    final dir = Directory(p.join(root.path, 'safety-copy'));
    await s.createSafetyCopy(dir, now: DateTime(2026, 1, 1));
    final latest = await s.createSafetyCopy(dir, now: DateTime(2026, 1, 2));

    expect(latest.existsSync(), isTrue);
    expect(dir.listSync().single.path, latest.path);
  });

  group('settings changed during an auto backup survive it', () {
    Future<void> check({required bool failing}) async {
      final s = await service('auto');
      final store = AutoBackupStore(File(p.join(root.path, 'auto.json')));
      await store.save(
        const AutoBackupConfig(
          frequency: AutoBackupFrequency.daily,
          folderUri: 'test:folder',
        ),
      );
      final writing = Completer<void>();
      final release = Completer<void>();
      final backup = AutoBackup(
        store: store,
        openService: () async => s,
        workDir: () async => Directory(p.join(root.path, 'work')),
        password: InMemoryAutoBackupPassword(),
        writeToFolder: (_, name, source) async {
          writing.complete();
          await release.future;
          if (failing) throw StateError('folder gone');
        },
        schedule: (_) async {},
      );

      final running = backup.run(force: true);
      await writing.future;
      await store.save(
        (await store.load()).copyWith(frequency: AutoBackupFrequency.off),
      );
      release.complete();
      await running;

      final current = await store.load();
      expect(current.enabled, isFalse);
      expect(failing ? current.lastError : current.lastAt, isNotNull);
    }

    test('when it succeeds', () => check(failing: false));
    test('when it fails', () => check(failing: true));
  });

  group('a cost factor from a file is capped before any work', () {
    test('in an encrypted backup', () async {
      final file = File(p.join(root.path, 'hostile.beandbak'))
        ..writeAsBytesSync([
          ...ascii.encode('BEANDENC'),
          1,
          nip49MaxLogN + 2,
          ...List.filled(16, 0),
        ]);
      await expectLater(
        decryptBackupFile(file, File(p.join(root.path, 'out')), 'password'),
        throwsA(isA<BackupCipherException>()),
      );
    });

    test('in an encrypted key', () async {
      final key = await nip49Encrypt(
        Uint8List(32)..[31] = 7,
        'password',
        logN: 4,
      );
      await expectLater(nip49Decrypt(key, 'password'), completes);

      // Same key, cost byte raised: rejected before scrypt runs.
      await expectLater(
        nip49Decrypt(await _withLogN(key, nip49MaxLogN + 1), 'password'),
        throwsA(
          isA<Nip49Exception>().having(
            (e) => e.message,
            'message',
            contains('Cost factor'),
          ),
        ),
      );
    });
  });
}

/// Encrypting at a cost above the cap would itself run for minutes, so only
/// the stored byte changes.
Future<String> _withLogN(String ncryptsec, int logN) async {
  final data = bech32Decode(ncryptsecPrefix, ncryptsec);
  data[1] = logN;
  return bech32Encode(ncryptsecPrefix, data);
}

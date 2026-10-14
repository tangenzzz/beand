import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:beand/database/database.dart';
import 'package:beand/services/backup_service.dart';
import 'package:beand/sync/crypto/backup_cipher.dart';
import 'package:beand/sync/crypto/nip49.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:beand/sync/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// Sync key in the backup (NIP-49) and optionally the whole backup
// encrypted.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('beand_backup_key');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('backup_cipher', () {
    // log_n 4: fast in tests, same format.
    Future<void> roundTrip(int size) async {
      final plain = File(p.join(root.path, 'plain-$size'))
        ..writeAsBytesSync(
          Uint8List.fromList(
            List.generate(size, (i) => Random(i).nextInt(256)),
          ),
        );
      final enc = File(p.join(root.path, 'enc-$size'));
      final out = File(p.join(root.path, 'out-$size'));
      await encryptBackupFile(plain, enc, 'correct horse', logN: 4);
      expect(isEncryptedBackup(enc), isTrue);
      expect(isEncryptedBackup(plain), isFalse);
      await decryptBackupFile(enc, out, 'correct horse');
      expect(out.readAsBytesSync(), plain.readAsBytesSync());
    }

    test('round trip: empty, small, several chunks', () async {
      await roundTrip(0);
      await roundTrip(1000);
      await roundTrip((1 << 20) * 2 + 17);
    });

    test('wrong password, truncated, tampered', () async {
      final plain = File(p.join(root.path, 'plain'))
        ..writeAsBytesSync(List.filled((1 << 20) + 100, 7));
      final enc = File(p.join(root.path, 'enc'));
      final out = File(p.join(root.path, 'out'));
      await encryptBackupFile(plain, enc, 'correct horse', logN: 4);
      final bytes = enc.readAsBytesSync();

      expect(
        () => decryptBackupFile(enc, out, 'wrong horse'),
        throwsA(
          isA<BackupCipherException>().having(
            (e) => e.message,
            'message',
            'Wrong password.',
          ),
        ),
      );

      // Last chunk missing.
      final cut = File(p.join(root.path, 'cut'))
        ..writeAsBytesSync(bytes.sublist(0, 26 + 5 + 24 + (1 << 20) + 16));
      expect(
        () => decryptBackupFile(cut, out, 'correct horse'),
        throwsA(isA<BackupCipherException>()),
      );

      // One byte flipped in the second chunk.
      final tampered = Uint8List.fromList(bytes);
      tampered[tampered.length - 30] ^= 1;
      final bad = File(p.join(root.path, 'bad'))..writeAsBytesSync(tampered);
      expect(
        () => decryptBackupFile(bad, out, 'correct horse'),
        throwsA(
          isA<BackupCipherException>().having(
            (e) => e.message,
            'message',
            'This backup is damaged.',
          ),
        ),
      );
    });
  });

  group('backup with sync key', () {
    late Directory docs;
    late AppDatabase db;
    late BackupService service;
    late SyncIdentity identity;
    late BackupSyncInfo info;

    setUp(() async {
      docs = Directory(p.join(root.path, 'docs'))..createSync();
      db = AppDatabase(
        NativeDatabase(File(p.join(docs.path, backupDbFileName))),
      );
      await db.insertBean(BeansCompanion.insert(name: 'Guji'));
      service = BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
        openRestoredDb: (file) => AppDatabase(NativeDatabase(file)),
      );
      identity = SyncIdentity.generate();
      info = BackupSyncInfo(
        ncryptsec: await nip49Encrypt(
          identity.privateKeyBytes,
          'backup password',
          logN: 4,
        ),
        npub: identity.npub,
        enabled: true,
        relays: const ['wss://relay.example'],
        blobServers: const ['https://blossom.example'],
      );
    });
    tearDown(() async {
      try {
        await db.close();
      } catch (_) {}
    });

    test('key is in the zip only encrypted', () async {
      final zip = await service.createBackup(
        targetDir: Directory(p.join(root.path, 'out')),
        sync: info,
      );
      final manifest = await service.readManifest(zip);
      expect(manifest.syncNpub, identity.npub);
      final read = await service.readSyncInfo(zip);
      expect(read!.ncryptsec, info.ncryptsec);
      expect(read.relays, ['wss://relay.example']);
      expect(read.blobServers, ['https://blossom.example']);
      expect(read.enabled, isTrue);
      // Neither nsec nor hex key anywhere in the file.
      final raw = String.fromCharCodes(zip.readAsBytesSync());
      expect(raw.contains(identity.nsec), isFalse);

      final key = await SyncService.decryptBackupKey(read, 'backup password');
      expect(SyncIdentity.fromPrivateKey(key).npub, identity.npub);
      expect(
        () => SyncService.decryptBackupKey(read, 'nope nope'),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('without sync: no sync.json', () async {
      final zip = await service.createBackup(
        targetDir: Directory(p.join(root.path, 'out')),
      );
      expect((await service.readManifest(zip)).syncNpub, isNull);
      expect(await service.readSyncInfo(zip), isNull);
    });

    test('fully encrypted: readable only with the password', () async {
      final file = await service.createBackup(
        targetDir: Directory(p.join(root.path, 'out')),
        sync: info,
        encryptPassword: 'backup password',
        now: DateTime(2026, 10, 11, 18, 30),
      );
      expect(p.basename(file.path), 'beand-backup-2026-10-11-1830.beandbak');
      expect(isEncryptedBackup(file), isTrue);
      // No zip left lying around next to it.
      expect(file.parent.listSync(), hasLength(1));
      expect(() => service.readManifest(file), throwsA(isA<BackupException>()));

      await expectLater(
        service.decryptBackup(
          file,
          'wrong password',
          targetDir: Directory(p.join(root.path, 'dec')),
        ),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            'Wrong password.',
          ),
        ),
      );
      final zip = await service.decryptBackup(
        file,
        'backup password',
        targetDir: Directory(p.join(root.path, 'dec')),
      );
      expect((await service.readManifest(zip)).beans, 1);
      expect((await service.readSyncInfo(zip))!.npub, identity.npub);
    });
  });

  test('take over the key from the backup: account and servers, nothing '
      'started', () async {
    final db = AppDatabase(NativeDatabase.memory())..deviceId = 'device-b';
    final state = InMemorySyncStateStore();
    await state.save(SyncStateData(relays: ['wss://old.example']));
    final keys = InMemorySyncKeyStore();
    final sync = SyncService(db: db, keyStore: keys, stateStore: state);
    await sync.init();
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });

    final identity = SyncIdentity.generate();
    await sync.afterRestore();
    await sync.adoptFromBackup(
      BackupSyncInfo(
        ncryptsec: 'ncryptsec1unused',
        npub: identity.npub,
        enabled: true,
        relays: const ['wss://relay.example'],
        blobServers: const ['https://blossom.example'],
      ),
      identity.privateKeyBytes,
    );

    expect(sync.identity!.npub, identity.npub);
    expect((await keys.readIdentity())!.npub, identity.npub);
    final saved = await state.load();
    expect(saved.enabled, isTrue);
    expect(saved.relays, ['wss://relay.example']);
    expect(saved.blobServers, ['https://blossom.example']);
    expect(saved.resendAll, isTrue);
    expect(saved.lastSync, isEmpty);
    // The database is closed after restoring: no sync now.
    expect(sync.phase, SyncPhase.off);
  });
}

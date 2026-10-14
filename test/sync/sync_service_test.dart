import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/sync_settings_screen.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:beand/sync/sync_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_blossom.dart';
import '../support/test_relay.dart';

// SyncService: on/off, key, server list, triggers — and the
// Settings → Sync page.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestRelay relay;
  late AppDatabase db;
  late InMemorySyncStateStore state;
  late InMemorySyncKeyStore keys;
  late SyncService sync;

  Future<SyncService> service({
    AppDatabase? database,
    InMemorySyncKeyStore? keyStore,
    InMemorySyncStateStore? stateStore,
  }) async {
    final s = SyncService(
      devicePresence: false,
      db: database ?? db,
      keyStore: keyStore ?? keys,
      stateStore: stateStore ?? state,
      changeDelay: const Duration(milliseconds: 50),
    );
    await s.init();
    return s;
  }

  setUp(() async {
    relay = await TestRelay.start();
    db = AppDatabase(NativeDatabase.memory())..deviceId = 'device-a';
    state = InMemorySyncStateStore();
    // Only the test relay, no public servers in tests.
    await state.save(SyncStateData(relays: [relay.url]));
    keys = InMemorySyncKeyStore();
    sync = await service();
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    await relay.close();
  });

  test('off: no key, no connection', () async {
    expect(sync.enabled, isFalse);
    expect(sync.phase, SyncPhase.off);
    expect(sync.identity, isNull);
    await db.insertBean(BeansCompanion.insert(name: 'Guji'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(relay.events, isEmpty);
  });

  test('turning on: key is created, existing data is uploaded', () async {
    await db.insertBean(BeansCompanion.insert(name: 'Guji'));
    await sync.enable();
    expect(sync.identity, isNotNull);
    expect((await keys.readIdentity())!.npub, sync.identity!.npub);
    expect(relay.events, hasLength(1));
    expect(sync.phase, SyncPhase.idle);
    expect(sync.lastSuccessAt, isNotNull);
    expect((await state.load()).enabled, isTrue);
  });

  test('own change goes out by itself after a short pause', () async {
    await sync.enable();
    await db.insertBean(BeansCompanion.insert(name: 'Kiambu'));
    for (var i = 0; i < 50 && relay.events.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(relay.events, hasLength(1));
  });

  test('turning off keeps the key; on again = the same one', () async {
    await sync.enable();
    final npub = sync.identity!.npub;
    await sync.disable();
    expect(sync.phase, SyncPhase.off);
    await sync.enable();
    expect(sync.identity!.npub, npub);
  });

  test('new server gets the whole data set, not just new items', () async {
    await db.insertBean(BeansCompanion.insert(name: 'Guji'));
    await sync.enable();
    expect(relay.events, hasLength(1));

    final second = await TestRelay.start();
    addTearDown(second.close);
    await sync.addRelay(second.url);
    await sync.syncNow();
    expect(second.events, hasLength(1), reason: 'data set went to the new one');
    expect(
      relay.events,
      hasLength(1),
      reason: 'old server: replaced, not duplicated',
    );
    expect((await db.allBeans()).single.syncState, SyncState.synced);
  });

  test('public photo servers: added once, removal sticks', () async {
    expect(sync.blobServers, defaultBlobServers);
    await sync.removeBlobServer(defaultBlobServers.first);
    final again = await service();
    addTearDown(again.dispose);
    expect(again.blobServers, [defaultBlobServers.last]);
    expect(
      SyncService.normalizeBlobServerUrl('192.168.1.50:3000'),
      'http://192.168.1.50:3000',
    );
    expect(
      SyncService.normalizeBlobServerUrl('nostr.download'),
      'https://nostr.download',
    );
  });

  test('server list: address is validated and normalized', () async {
    expect(
      SyncService.normalizeRelayUrl('relay.example.com'),
      'wss://relay.example.com',
    );
    expect(
      SyncService.normalizeRelayUrl('wss://relay.example.com/'),
      'wss://relay.example.com',
    );
    expect(
      SyncService.normalizeRelayUrl('ws://192.168.1.50:7777'),
      'ws://192.168.1.50:7777',
    );
    // Without a scheme: unencrypted on the local network, otherwise wss.
    expect(
      SyncService.normalizeRelayUrl('192.168.1.50:7777'),
      'ws://192.168.1.50:7777',
    );
    expect(
      SyncService.normalizeRelayUrl('100.101.102.103:7777'),
      'ws://100.101.102.103:7777',
    );
    expect(SyncService.normalizeRelayUrl('beand:7777'), 'ws://beand:7777');
    expect(
      SyncService.normalizeRelayUrl('pi.local:7777'),
      'ws://pi.local:7777',
    );
    expect(SyncService.normalizeRelayUrl('8.8.8.8:7777'), 'wss://8.8.8.8:7777');
    expect(SyncService.normalizeRelayUrl('https://example.com'), isNull);
    expect(SyncService.normalizeRelayUrl('  '), isNull);

    expect(await sync.addRelay('wss://relay.example.com'), isTrue);
    expect(
      await sync.addRelay('relay.example.com'),
      isFalse,
      reason: 'duplicate',
    );
    expect(sync.relays, [relay.url, 'wss://relay.example.com']);
    await sync.removeRelay('wss://relay.example.com');
    expect((await state.load()).relays, [relay.url]);
  });

  test('transferring the key to a second device: data merges', () async {
    await db.insertBean(BeansCompanion.insert(name: 'Von A'));
    await sync.enable();
    final exported = await sync.exportKey('Kaffee123');
    expect(exported, startsWith('ncryptsec1'));

    final dbB = AppDatabase(NativeDatabase.memory())..deviceId = 'device-b';
    final stateB = InMemorySyncStateStore();
    await stateB.save(SyncStateData(relays: [relay.url]));
    final keysB = InMemorySyncKeyStore();
    final b = await service(database: dbB, keyStore: keysB, stateStore: stateB);
    addTearDown(() async {
      b.dispose();
      await dbB.close();
    });
    await dbB.insertBean(BeansCompanion.insert(name: 'Von B'));
    await b.enable(); // own key first
    expect(b.identity!.npub, isNot(sync.identity!.npub));

    await b.importKey(exported, 'Kaffee123');
    expect(b.identity!.npub, sync.identity!.npub);
    await sync.syncNow();
    final namesA = (await db.allBeans()).map((x) => x.name).toSet();
    final namesB = (await dbB.allBeans()).map((x) => x.name).toSet();
    expect(namesA, {'Von A', 'Von B'});
    expect(namesB, {'Von A', 'Von B'});
  });

  test('wrong password when adopting changes nothing', () async {
    await sync.enable();
    final npub = sync.identity!.npub;
    final other = await service(
      database: db,
      keyStore: InMemorySyncKeyStore(),
      stateStore: InMemorySyncStateStore(),
    );
    addTearDown(other.dispose);
    await other.enable();
    final exported = await other.exportKey('richtig123');
    await expectLater(
      sync.importKey(exported, 'falsch12345'),
      throwsA(anything),
    );
    expect(sync.identity!.npub, npub);
  });

  test('after a restore: everything anew on next start', () async {
    await db.insertBean(BeansCompanion.insert(name: 'Guji'));
    await sync.enable();
    expect((await db.allBeans()).single.syncState, SyncState.synced);
    await sync.afterRestore();
    final saved = await state.load();
    expect(saved.lastSync, isEmpty);
    expect(saved.resendAll, isTrue);

    final restarted = await service();
    addTearDown(restarted.dispose);
    expect((await state.load()).resendAll, isFalse);
    // After the restart: uploaded again (pending → synced).
    await restarted.syncNow();
    expect((await db.allBeans()).single.syncState, SyncState.synced);
  });

  test('after a restore the backup wins over newer deletions', () async {
    final bean = await db.insertBean(BeansCompanion.insert(name: 'Guji'));
    await sync.enable();
    // "Backup": keep the row as it was before deletion.
    final backup = (await db.select(db.beans).get()).single;
    await db.deleteBean(bean.id);
    await sync.syncNow(); // tombstone is now on the relay.
    expect(await db.allBeans(), isEmpty);

    // "Restore": old row back, then as in the backup dialog.
    await db.update(db.beans).replace(backup);
    await sync.afterRestore();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final restarted = await service();
    addTearDown(restarted.dispose);
    await restarted.syncNow();

    expect((await db.allBeans()).map((b) => b.name), ['Guji']);
    // And the restored state went out — other devices fetch it back
    // instead of staying with the tombstone.
    expect((await db.allBeans()).single.syncState, SyncState.synced);
  });

  test(
    'new photo server is checked right away, not only after the sync',
    () async {
      // Otherwise the test binding answers every HTTP request with 400.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final blossom = await TestBlossom.start();
      addTearDown(blossom.close);
      final docs = Directory.systemTemp.createTempSync('beand_blob_check');
      addTearDown(() => docs.deleteSync(recursive: true));
      final s = SyncService(
        devicePresence: false,
        db: db,
        keyStore: keys,
        stateStore: state,
        changeDelay: const Duration(seconds: 30),
        docsDir: () async => docs,
      );
      addTearDown(s.dispose);
      await s.init();
      await s.enable();
      // Without a sync afterwards: only the immediate check can turn green.
      await s.disable();
      expect(s.blobServerOk(blossom.url), isFalse);
      await s.addBlobServer(blossom.url);
      for (var i = 0; i < 50 && !s.blobServerOk(blossom.url); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(s.blobServerOk(blossom.url), isTrue);
    },
  );

  group('Settings → Sync page', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<SyncService>.value(
          value: sync,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const SyncSettingsScreen(),
          ),
        ),
      );
    }

    testWidgets('off: only the switch', (tester) async {
      await pump(tester);
      expect(find.text('Sync between your devices'), findsOneWidget);
      expect(find.text('Servers'), findsNothing);
      expect(find.text('Sync now'), findsNothing);
    });

    testWidgets('on: status, servers with state, public key', (tester) async {
      await tester.runAsync(sync.enable);
      await pump(tester);
      await tester.pump();
      expect(find.text('Sync now'), findsOneWidget);
      // Servers and key only under "Advanced settings".
      expect(find.text('127.0.0.1 · home network'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sync-advanced')));
      await tester.pump();
      expect(find.textContaining('Up to date'), findsOneWidget);
      expect(find.text('127.0.0.1 · home network'), findsOneWidget);
      expect(
        find.textContaining(sync.identity!.npub.substring(0, 12)),
        findsOneWidget,
      );
      // The key itself is not shown openly (only "Your nsec" masked).
      expect(find.text(sync.identity!.nsec), findsNothing);
    });

    testWidgets('invalid server address: hint instead of entry', (
      tester,
    ) async {
      await tester.runAsync(sync.enable);
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('sync-advanced')));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'https://nope');
      await tester.tap(find.text('Add').first);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.textContaining('Enter a server address'), findsOneWidget);
      expect(sync.relays, [relay.url]);
    });
  });

  test('time label of the status line', () {
    final now = DateTime(2026, 10, 10, 12);
    expect(
      syncAgoLabel(now.subtract(const Duration(seconds: 5)), now),
      'just now',
    );
    expect(
      syncAgoLabel(now.subtract(const Duration(minutes: 3)), now),
      '3 min ago',
    );
    expect(
      syncAgoLabel(now.subtract(const Duration(hours: 2)), now),
      '2 h ago',
    );
  });
}

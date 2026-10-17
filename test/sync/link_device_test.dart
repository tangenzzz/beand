import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/sync_settings_screen.dart';
import 'package:beand/sync/crypto/nip49.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:beand/sync/sync_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/test_relay.dart';

// Sync: linking devices (QR, plain text only after fingerprint/PIN, screen
// protection, adopting the key while sync is off).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestRelay relay;
  late AppDatabase db;
  late SyncService sync;

  setUp(() async {
    relay = await TestRelay.start();
    db = AppDatabase(NativeDatabase.memory())..deviceId = 'device-b';
    final state = InMemorySyncStateStore();
    await state.save(SyncStateData(relays: [relay.url]));
    sync = SyncService(
      devicePresence: false,
      db: db,
      keyStore: InMemorySyncKeyStore(),
      stateStore: state,
      changeDelay: const Duration(milliseconds: 50),
    );
    await sync.init();
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    await relay.close();
  });

  test('unprotected key (nsec) is adopted without a password', () async {
    final other = SyncIdentity.generate();
    await sync.importKey(other.nsec, '');
    expect(sync.identity!.npub, other.npub);
    expect(
      () => sync.importKey('nsec1kaputt', ''),
      throwsA(isA<Nip49Exception>()),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<bool> Function()? authenticate,
    Future<String?> Function(BuildContext)? scan,
    Future<void> Function()? safetyCopy,
  }) => tester.pumpWidget(
    ChangeNotifierProvider<SyncService>.value(
      value: sync,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: SyncSettingsScreen(
          authenticate: authenticate ?? () async => false,
          scan: scan,
          safetyCopy: safetyCopy,
        ),
      ),
    ),
  );

  // Let async work (scrypt in an isolate, relay) actually run.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Let the sync timers (fake clock) run out.
  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(sync.disable);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  }

  testWidgets('off: only the switch and "Scan QR code", nothing about Nostr', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Advanced settings'), findsNothing);
    expect(find.textContaining('Nostr'), findsNothing);
    expect(find.textContaining('relay'), findsNothing);
  });

  testWidgets('new device: scan protected code, password, sync is on', (
    tester,
  ) async {
    final other = SyncIdentity.generate();
    late String protected;
    await tester.runAsync(() async {
      protected = await nip49Encrypt(other.privateKeyBytes, 'kaffee1', logN: 4);
    });
    await pump(tester, scan: (_) async => protected);
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This code is locked.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'kaffee1');
    await tester.tap(find.text('OK'));
    await waitFor(tester, () => sync.enabled);
    expect(sync.enabled, isTrue);
    expect(sync.identity!.npub, other.npub);
    await finish(tester);
  });

  testWidgets('scan unprotected code: no password needed', (tester) async {
    final other = SyncIdentity.generate();
    await pump(tester, scan: (_) async => other.nsec);
    await tester.tap(find.text('Scan QR code'));
    await waitFor(tester, () => sync.enabled);
    expect(find.text('Password'), findsNothing);
    expect(sync.identity!.npub, other.npub);
    await finish(tester);
  });

  testWidgets(
    'on: QR only after confirmation, without password; no password path',
    (tester) async {
      final calls = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('beand/secure_screen'),
        (call) async {
          calls.add(call.arguments);
          return null;
        },
      );
      await tester.runAsync(sync.enable);
      var allow = false;
      await pump(tester, authenticate: () async => allow);
      await tester.pump();
      expect(find.text('Advanced settings'), findsOneWidget);
      expect(find.text('Servers'), findsNothing);

      // Declined: no QR.
      await tester.tap(find.text('Show QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Not confirmed.'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      expect(find.byType(QrImageView), findsNothing);

      // Confirmed: QR without password, with warning, screen protected.
      allow = true;
      await tester.tap(find.text('Show QR code'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('This code is your sync key'), findsOneWidget);
      expect(find.text('Use a password instead'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(calls.last, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls.last, isFalse);

      await finish(tester);
    },
  );

  testWidgets('Advanced: npub visible, nsec only after confirmation', (
    tester,
  ) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('beand/secure_screen'),
      (call) async {
        calls.add(call.arguments);
        return null;
      },
    );
    tester.view.physicalSize = const Size(1200, 3600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(sync.enable);
    var allow = false;
    await pump(tester, authenticate: () async => allow);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync-advanced')));
    await tester.pump();
    final nsec = sync.identity!.nsec;
    expect(find.text('Your npub'), findsOneWidget);
    expect(find.text('Your nsec'), findsOneWidget);
    expect(find.text(nsec), findsNothing);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Not confirmed.'), findsOneWidget);
    expect(find.text(nsec), findsNothing);
    expect(calls, isEmpty);

    allow = true;
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text(nsec), findsOneWidget);
    expect(calls.last, isTrue);

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text(nsec), findsNothing);
    expect(calls.last, isFalse);
    await finish(tester);
  });

  testWidgets('Advanced: expanding shows servers, ⓘ explains Nostr', (
    tester,
  ) async {
    await tester.runAsync(sync.enable);
    await pump(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync-advanced')));
    await tester.pump();
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('QR code with password'), findsNothing);
    expect(find.text('Enter key by hand'), findsNothing);
    expect(nostrExplanation, contains('Nostr'));
    // Must say plainly that the upload is encrypted.
    expect(nostrExplanation, contains('encrypted on this device'));
    await finish(tester);
  });

  group('device already has data: merge or replace', () {
    // Bean "Real" sits on the relay under the other device's key; here
    // there is a separate test bean and a tombstone.
    late SyncIdentity other;
    late AppDatabase otherDb;

    setUp(() async {
      other = SyncIdentity.generate();
      otherDb = AppDatabase(NativeDatabase.memory())..deviceId = 'device-a';
      final otherState = InMemorySyncStateStore();
      await otherState.save(SyncStateData(relays: [relay.url]));
      final keys = InMemorySyncKeyStore();
      await keys.writeIdentity(other);
      final a = SyncService(
        devicePresence: false,
        db: otherDb,
        keyStore: keys,
        stateStore: otherState,
      );
      await a.init();
      await otherDb.insertBean(BeansCompanion.insert(name: 'Real'));
      await a.enable();
      a.dispose();

      final test = await db.insertBean(BeansCompanion.insert(name: 'Test'));
      await db.deleteBean(test.id);
      await db.insertBean(BeansCompanion.insert(name: 'Test 2'));
    });

    tearDown(() => otherDb.close());

    Future<List<String>> names(AppDatabase d) async =>
        (await d.allBeans()).map((b) => b.name).toList()..sort();

    testWidgets('Replace: own data gone, safety copy, state of the '
        'other device present', (tester) async {
      var copies = 0;
      await pump(
        tester,
        scan: (_) async => other.nsec,
        safetyCopy: () async => copies++,
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.text('This device already has data'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await waitFor(tester, () => sync.enabled && sync.phase.name == 'idle');
      await waitFor(tester, () => false); // let the sync run out

      expect(copies, 1);
      expect(sync.identity!.npub, other.npub);
      final here = (await tester.runAsync(() => names(db)))!;
      expect(here, ['Real']);
      // Nothing from here went to the other device, not even a deletion.
      expect(relay.events.length, 1);
      await finish(tester);
    });

    testWidgets('Merge: both combined (as before)', (tester) async {
      await pump(tester, scan: (_) async => other.nsec);
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge'));
      await waitFor(tester, () => false);
      final here = (await tester.runAsync(() => names(db)))!;
      expect(here, ['Real', 'Test 2']);
      await finish(tester);
    });

    testWidgets('Cancel: nothing adopted', (tester) async {
      await pump(tester, scan: (_) async => other.nsec);
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sync.identity, isNull);
      expect((await tester.runAsync(() => names(db)))!, ['Test 2']);
      await finish(tester);
    });
  });
}

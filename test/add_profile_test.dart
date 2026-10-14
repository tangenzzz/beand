import 'dart:convert';
import 'dart:io';

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_sync_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/screens/live/add_profile_dialog.dart';
import 'package:beand/screens/live/profile_carousel.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/profile_store.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  final uploaded = <Map<String, dynamic>>[];
  ({bool ok, String? error}) answer = (ok: true, error: null);

  @override
  Future<({bool ok, String? error})> saveProfile(
    Map<String, dynamic> profile,
  ) async {
    uploaded.add(profile);
    return answer;
  }
}

void main() {
  _providersBelowMaterialApp();

  late AppDatabase db;
  late FakeSocket socket;
  late ProfileSyncService sync;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    socket = FakeSocket();
    sync = ProfileSyncService(
      database: db,
      socket: socket,
      imageDir: Directory.systemTemp.createTempSync('profile_images'),
      // No real network traffic in the test: the machine has no profiles.
      client: MockClient((_) async => http.Response('[]', 200)),
    );
  });

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
      // The same machine again under the shared interface: the pre-shot
      // card talks to it through that.
      ChangeNotifierProvider<EspressoMachine>.value(value: socket),
      ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
      Provider<ProfileSyncService>.value(value: sync),
      Provider<ProfileStore>.value(value: sync),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('Profile row: name only, "+" opposite the heading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'p1',
          name: 'Soup Test',
          json: jsonEncode({
            'id': 'p1',
            'name': 'Soup Test',
            'temperature': 82,
            'final_weight': 36,
          }),
          fetchedAt: DateTime(2026, 9, 26),
        ),
      );
    });

    await tester.pumpWidget(wrap(const ProfileCarousel()));
    await settle(tester);

    expect(find.text('Soup Test'), findsOneWidget);
    // Temperature and yield are no longer shown below the name.
    expect(find.textContaining('°C'), findsNothing);
    expect(find.textContaining('36g'), findsNothing);

    // "+" sits on the right, level with the heading.
    final plus = find.byTooltip('Add profile');
    expect(plus, findsOneWidget);
    expect(
      tester.getCenter(plus).dx,
      greaterThan(tester.getCenter(find.text('Profile')).dx),
    );
    expect(
      (tester.getCenter(plus).dy - tester.getCenter(find.text('Profile')).dy)
          .abs(),
      lessThan(12),
    );

    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.text('Add profile'), findsOneWidget);
    expect(find.text('Upload .json file'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  testWidgets(
    'Dialog: create new opens the editor, sites open in the browser',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddProfileDialog(
                context,
                openUrl: (url) async {
                  opened.add(url);
                  return true;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Since the profile editor exists, the entry is enabled.
      expect(find.text('Create new profile'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);

      expect(find.text('Download profile from'), findsOneWidget);
      await tester.tap(find.text('metprofiles.link'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://metprofiles.link/')]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('community.meticuloushome.com'));
      await tester.pumpAndSettle();
      expect(
        opened.last,
        Uri.parse('https://community.meticuloushome.com/brew-profiles'),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(db.close);
    },
  );

  testWidgets('Dialog: JSON file is sent to the machine', (tester) async {
    final file = File(
      '${Directory.systemTemp.createTempSync('profile_json').path}/soup.json',
    )..writeAsStringSync(jsonEncode({'name': 'Soup Test', 'temperature': 82}));

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddProfileDialog(
              context,
              pickJsonFile: () async => file.path,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload .json file'));
    // Not pumpAndSettle: while uploading, a progress ring spins that never
    // "settles".
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }

    expect(socket.uploaded.single['name'], 'Soup Test');
    expect(find.textContaining('Uploaded "Soup Test"'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  testWidgets('Dialog: machine error is shown in plain text', (tester) async {
    socket.answer = (ok: false, error: 'HTTP 400: name missing');
    final file = File(
      '${Directory.systemTemp.createTempSync('profile_json').path}/bad.json',
    )..writeAsStringSync(jsonEncode({'temperature': 82}));

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddProfileDialog(
              context,
              pickJsonFile: () async => file.path,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload .json file'));
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }

    expect(find.textContaining('HTTP 400: name missing'), findsOneWidget);
    // The dialog stays open so one can try again.
    expect(find.text('Add profile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}

// The dialog lives in its OWN route. If the providers sit — as in the app —
// BELOW the MaterialApp (each home screen provides its machine and its
// profile store itself), it cannot see them. That is exactly what crashed
// it on the device; the other tests here did not notice, because they put
// their providers above it.
void _providersBelowMaterialApp() {
  testWidgets('Dialog finds machine and store even from its own route', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final socket = FakeSocket();
    final sync = ProfileSyncService(
      database: db,
      socket: socket,
      imageDir: Directory.systemTemp.createTempSync('profile_images'),
      client: MockClient((_) async => http.Response('[]', 200)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<EspressoMachine>.value(value: socket),
            Provider<ProfileStore>.value(value: sync),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddProfileDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Add profile'), findsOneWidget);
    // The sources come from the home screen's machine.
    expect(find.text('metprofiles.link'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  testWidgets('GaggiMate home offers mybrewfolio as a source', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final machine = offlineGaggiMate();
    final store = GaggiMateProfileSyncService(database: db, machine: machine);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<EspressoMachine>.value(value: machine),
            Provider<ProfileStore>.value(value: store),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddProfileDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('mybrewfolio.com'), findsOneWidget);
    expect(find.text('metprofiles.link'), findsNothing);
    // Since gaggimate_profile_codec.dart the editor also translates the
    // GaggiMate phase format — the entry is enabled here as well.
    expect(find.text('Create new profile'), findsOneWidget);
    expect(find.text('Build stages and curves yourself'), findsOneWidget);
    expect(find.text('Not available for GaggiMate yet'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    store.dispose();
    await db.close();
  });
}

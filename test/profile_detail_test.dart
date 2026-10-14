import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/machine_profile.dart';
import 'package:beand/models/profile_detail.dart';
import 'package:beand/screens/live/profile_carousel.dart';
import 'package:beand/screens/profile/editor/profile_editor_screen.dart';
import 'package:beand/screens/profile/profile_detail_screen.dart';
import 'package:beand/widgets/app_button.dart';
import 'package:beand/services/profile_store.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// The tests check the default appearance: dark with teal.
final _theme = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

// Three real machine profiles: Bailey (variables in stages, author +
// predecessor), Damian's LRv2 (7 stages, several triggers), Turbo (long
// description, curve with three points).
Map<String, Map<String, dynamic>> _fixtures() => {
  for (final p in jsonDecode(
    File('test/fixtures/profiles_sample.json').readAsStringSync(),
  ) as List)
    (p as Map)['name'] as String: Map<String, dynamic>.from(p),
};

ProfileDetail _profile(String name) =>
    ProfileDetail.fromJson(_fixtures()[name]!);

class FakeMachine extends MeticulousSocketService {
  FakeMachine() : super(hostname: 'machine.local');

  final hovered = <String>[];
  final deleted = <String>[];
  // The machine's response to deleting; null = succeeded.
  String? deleteError;

  @override
  void hoverProfile(String id, String name) => hovered.add(id);

  @override
  Future<ProfileSaveResult> deleteProfile(String id) async {
    deleted.add(id);
    final error = deleteError;
    return error == null
        ? ProfileSaveResult.ok(id)
        : ProfileSaveResult.failed(error);
  }
}

// The machine as an HTTP server: profile list, single profile, images.
class FakeMachineHttp {
  bool offline = false;
  final requests = <String>[];

  http.Client client() => MockClient((request) async {
    requests.add('${request.method} ${request.url.path}?${request.url.query}');
    if (offline) throw const SocketException('unreachable');
    final path = request.url.path;
    if (path == '/api/v1/profile/list') {
      return http.Response(jsonEncode(_fixtures().values.toList()), 200);
    }
    if (path.startsWith('/api/v1/profile/get/')) {
      final id = path.split('/').last;
      final match = _fixtures().values.where((f) => f['id'] == id);
      return match.isEmpty
          ? http.Response('nope', 404)
          : http.Response(jsonEncode(match.first), 200);
    }
    if (path.startsWith('/api/v1/profile/image/')) {
      return http.Response.bytes([1, 2, 3], 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('ProfileDetail.fromJson', () {
    test(
      'Bailey: variables are resolved in stages, the variable name stays',
      () {
        final p = _profile('Bailey - PSPH / Soup');
        expect(p.temperature, 87.5);
        expect(p.finalWeight, 50);
        expect(p.author, 'Bailey Manson');
        expect(p.previousAuthors, ['mimoja']);
        expect(p.lastChanged, isNotNull);
        expect(p.variables, hasLength(7));
        expect(p.stages.map((s) => s.name), [
          'Initial Saturation',
          'Puck Saturation',
          'Percolation Ramp',
          'Percolation',
        ]);

        final initial = p.stages[0];
        expect(initial.type, 'power');
        expect(initial.startValue, 100);
        expect(initial.isConstant, isTrue);
        expect(initial.interpolation, 'curve');
        // Trigger: pressure ≥ 0.1 (variable) and time ≥ 0.3 s (variable,
        // relative).
        expect(initial.exitTriggers.map((t) => t.type), ['pressure', 'time']);
        expect(initial.exitTriggers[0].value.value, 0.1);
        expect(
          initial.exitTriggers[0].value.variable,
          'Initial Saturation Exit Trigger',
        );
        expect(initial.exitTriggers[1].value.value, 0.3);
        expect(initial.exitTriggers[1].relative, isTrue);
        expect(initial.limits.single.type, 'pressure');
        expect(initial.limits.single.value.value, 1);
        expect(
          initial.limits.single.value.variable,
          isNull,
          reason: 'fixed number, no variable',
        );

        final puck = p.stages[1];
        expect(puck.type, 'flow');
        expect(
          puck.startValue,
          1,
          reason:
              'start value comes from the variable Puck Saturation Flowrate',
        );
        expect(puck.endValue, 1.5);
        expect(puck.isConstant, isFalse);
        expect(puck.curveSeconds, 5);
        expect(puck.exitTriggers.single.type, 'weight');
        expect(puck.exitTriggers.single.value.value, 6);

        expect(p.stages[3].exitTriggers, isEmpty);
        expect(p.stages[3].startValue, 5);
        expect(p.stages[3].limits.single.value.value, 6);
      },
    );

    test(
      "Damian's LRv2: 7 stages, constant multi-point curve, descending curve",
      () {
        final p = _profile("Damian's LRv2");
        expect(p.stages, hasLength(7));
        expect(p.variables, isEmpty);
        expect(p.description, isNull);
        expect(p.stages.map((s) => s.number), [1, 2, 3, 4, 5, 6, 7]);
        final infuse = p.stages[2];
        expect(infuse.points, hasLength(3));
        expect(infuse.isConstant, isTrue, reason: 'all three points at 2 bar');
        final decline = p.stages[4];
        expect(decline.startValue, 9);
        expect(decline.endValue, 3);
        expect(decline.curveSeconds, 55);
        expect(decline.exitTriggers.map((t) => t.type), ['time', 'flow']);
        expect(p.stages.last.type, 'flow');
      },
    );

    test('Turbo: description, short description, author', () {
      final p = _profile('Turbo');
      expect(p.description, contains('Immediately ramps-up'));
      expect(p.shortDescription, startsWith('Fast extraction'));
      expect(p.author, 'meticulous');
      expect(p.previousAuthors, isEmpty);
      expect(p.stages.single.points, hasLength(3));
      expect(p.stages.single.startValue, 6, reason: 'variable pressure_1');
      expect(p.stages.single.endValue, 2);
      expect(p.stages.single.limits.single.value.variable, 'Flow Limit');
    });

    test('unknown variable and edge cases do not break', () {
      final p = ProfileDetail.fromJson({
        'id': 'x',
        'name': 'Odd',
        'stages': [
          {
            'name': ' ',
            'type': 'flow',
            'dynamics': {
              'points': [
                [0, r'$missing'],
              ],
            },
            'exit_triggers': [
              {
                'type': 'time',
                'value': 3,
                'relative': false,
                'comparison': '>=',
              },
            ],
            'limits': [],
          },
          'not a map',
        ],
      });
      expect(p.stages, hasLength(1));
      expect(p.stages.single.startValue, isNull);
      expect(p.stages.single.exitTriggers.single.relative, isFalse);
      expect(p.description, isNull);
      expect(p.temperature, 0);
    });

    test('formatting', () {
      expect(formatNumber(100), '100');
      expect(formatNumber(1.5), '1.5');
      expect(formatNumber(0.30), '0.3');
      expect(formatNumber(4.75), '4.75');
      expect(unitFor('pressure'), 'bar');
      expect(unitFor('flow'), 'ml/s');
      expect(unitFor('power'), '%');
    });
  });

  late AppDatabase db;
  late FakeMachine machine;
  late FakeMachineHttp http_;
  late ProfileSyncService sync;
  late Directory imageDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    machine = FakeMachine();
    http_ = FakeMachineHttp();
    imageDir = Directory.systemTemp.createTempSync('profile_imgs');
    sync = ProfileSyncService(
      database: db,
      socket: machine,
      imageDir: imageDir,
      client: http_.client(),
    );
  });

  tearDown(() => imageDir.deleteSync(recursive: true));

  Widget app(Widget home) => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<MeticulousSocketService>.value(value: machine),
      // The same machine again under the shared interface: the Pre-Shot
      // card talks to it through that.
      ChangeNotifierProvider<EspressoMachine>.value(value: machine),
      ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
      Provider<ProfileSyncService>.value(value: sync),
      // The profile row and profile view talk to the store through the
      // shared interface.
      Provider<ProfileStore>.value(value: sync),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: home),
  );

  // Drift queries and HTTP run in real time; several rounds, because a
  // future result only becomes visible in the next frame.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Stores the fixture profiles in the DB the way sync would.
  Future<void> seedStored(WidgetTester tester, {Iterable<String>? names}) =>
      tester.runAsync(() async {
        var position = 0;
        for (final f in _fixtures().values) {
          if (names != null && !names.contains(f['name'])) continue;
          await db.upsertStoredProfile(
            StoredProfilesCompanion.insert(
              id: f['id'] as String,
              name: f['name'] as String,
              json: jsonEncode(f),
              position: Value(position++),
              fetchedAt: DateTime(2026, 9, 21, 12, 30),
            ),
          );
        }
      });

  MachineProfile summary(String name) {
    final f = _fixtures()[name]!;
    return MachineProfile(
      id: f['id'] as String,
      name: name,
      temperature: (f['temperature'] as num).toDouble(),
      finalWeight: (f['final_weight'] as num).toDouble(),
      accentColor: Colors.orange,
    );
  }

  testWidgets(
    'profile view: header, description, stages with triggers/limits, variables, info',
    (tester) async {
      bigScreen(tester);
      await tester.runAsync(() async {
        // Usage of this profile in the app: 2 shots, one rated.
        for (final (i, rating) in [(1, 4), (2, null)]) {
          await db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 9, 20 + i),
              profileName: const Value('Turbo'),
              rating: Value(rating),
            ),
            const [],
          );
        }
      });
      await seedStored(tester);
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Turbo'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      // Immediately: name from the card; then the rest.
      expect(find.text('Turbo'), findsOneWidget);
      await settle(tester);

      expect(
        find.textContaining('Fast extraction with courser'),
        findsOneWidget,
      );
      expect(find.textContaining('Immediately ramps-up'), findsOneWidget);
      expect(find.text('Stage breakdown'), findsOneWidget);
      expect(find.text('1 stage'), findsOneWidget);
      expect(find.text('no ramp (6bar down ramp) turbo'), findsOneWidget);
      // Ramp 6 → 2 bar over 22.7 s; exit after 30 s; limit: flow 4 ml/s
      // (variable).
      expect(find.textContaining('over 22.7 s · curve'), findsOneWidget);
      expect(find.text('30 s'), findsOneWidget);
      expect(find.text('4 ml/s'), findsOneWidget);
      expect(find.text('VARIABLES'), findsOneWidget);
      expect(find.text('Flow Limit'), findsOneWidget);
      // Info
      expect(find.text('meticulous'), findsOneWidget);
      expect(find.text('2 shots · Ø 4.0 ★ · last Tue 22 Sep'), findsOneWidget);
      expect(find.text(_fixtures()['Turbo']!['id'] as String), findsOneWidget);

      await teardown(tester);
    },
  );

  testWidgets(
    'usage counts only shots of THIS machine, not same-named profiles of others',
    (tester) async {
      bigScreen(tester);
      await tester.runAsync(() async {
        // Two shots with "Turbo" on the Meticulous (column default) …
        for (final i in [1, 2]) {
          await db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 9, 20 + i),
              profileName: const Value('Turbo'),
              rating: const Value(4),
            ),
            const [],
          );
        }
        // … and one with the same name on the GaggiMate, which must not count
        // here.
        await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 9, 30),
            profileName: const Value('Turbo'),
            rating: const Value(1),
            machine: const Value('gaggimate'),
          ),
          const [],
        );
      });
      await seedStored(tester);
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Turbo'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      await settle(tester);

      // Without the restriction it would be 3 shots, Ø 3.0 and 30.9. as last.
      expect(find.text('2 shots · Ø 4.0 ★ · last Tue 22 Sep'), findsOneWidget);

      await teardown(tester);
    },
  );

  testWidgets(
    'profile view Bailey: trigger and limit chips, author + predecessor',
    (tester) async {
      bigScreen(tester);
      await seedStored(tester);
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Bailey - PSPH / Soup'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      await settle(tester);

      expect(find.text('4 stages'), findsOneWidget);
      for (final name in [
        'Initial Saturation',
        'Puck Saturation',
        'Percolation Ramp',
        'Percolation',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('100 %'), findsOneWidget, reason: 'power stage: 100 %');
      expect(find.text('0.1 bar'), findsOneWidget, reason: 'exit: pressure');
      expect(
        find.text('0.3 s'),
        findsNWidgets(2),
        reason: 'exit: time (Initial Saturation + Ramp)',
      );
      expect(find.text('6 g'), findsOneWidget, reason: 'exit: weight');
      expect(
        find.text('6 bar'),
        findsNWidgets(2),
        reason: 'limit of the Ramp and Percolation stages (variable)',
      );
      expect(find.text('1 bar'), findsOneWidget);
      expect(find.text('Bailey Manson'), findsOneWidget);
      expect(find.text('mimoja'), findsOneWidget);
      expect(find.text('Not used yet'), findsOneWidget);
      expect(find.text('Percolation Pressure Limit'), findsOneWidget);
      // The legend shows only types that occur.
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);

      await teardown(tester);
    },
  );

  testWidgets('offline: stored profile is fully available, copy is marked', (
    tester,
  ) async {
    bigScreen(tester);
    await seedStored(tester);
    http_.offline = true;
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Stage breakdown'), findsOneWidget);
    expect(find.textContaining('Immediately ramps-up'), findsOneWidget);
    expect(find.text('Offline copy from Mon 21 Sep · 12:30'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('online: view updates the copy from the machine', (tester) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Synced'), findsOneWidget);
    expect(
      http_.requests.any((r) => r.startsWith('GET /api/v1/profile/get/')),
      isTrue,
    );
    await teardown(tester);
  });

  testWidgets('not stored yet and machine unreachable: notice + Try again', (
    tester,
  ) async {
    bigScreen(tester);
    http_.offline = true;
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('not saved yet'), findsOneWidget);
    expect(
      find.text('Turbo'),
      findsOneWidget,
      reason: 'header stays from the card',
    );

    http_.offline = false;
    await tester.tap(find.text('Retry'));
    // Fetch + save + stream update need several rounds.
    await settle(tester);
    await settle(tester);
    expect(find.text('Stage breakdown'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('everything in ONE large card, only the stages have their own', (
    tester,
  ) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Bailey - PSPH / Soup'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    // Card containers with the card background: the large one + 4 stage
    // cards have a different color (0xFF2A2A2D), sections no card of their own.
    bool isBigTile(Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == _theme.card &&
        (w.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(AppRadii.tile);
    expect(find.byWidgetPredicate(isBigTile), findsOneWidget);
    bool isStageCard(Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color ==
            _theme.textPrimary.withValues(alpha: 0.06);
    expect(find.byWidgetPredicate(isStageCard), findsNWidgets(4));
    await teardown(tester);
  });

  testWidgets(
    'Home: cards come from the local copy (also offline); tapping opens the view without sending anything',
    (tester) async {
      bigScreen(tester);
      await seedStored(tester);
      http_.offline = true; // machine unreachable
      await tester.pumpWidget(app(const Scaffold(body: ProfileCarousel())));
      await settle(tester);
      // In the machine's order.
      expect(find.text("Damian's LRv2"), findsOneWidget);
      expect(find.text('Bailey - PSPH / Soup'), findsOneWidget);
      expect(find.text('Turbo'), findsOneWidget);

      await tester.tap(find.text('Turbo'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(find.byType(ProfileDetailScreen), findsOneWidget);
      expect(
        machine.hovered,
        isEmpty,
        reason: 'view only: send nothing to the machine',
      );
      expect(find.text('Stage breakdown'), findsOneWidget);
      // Only GETs against the machine, never a load/heat.
      expect(http_.requests.every((r) => r.startsWith('GET ')), isTrue);
      expect(http_.requests.any((r) => r.contains('/profile/load')), isFalse);
      await teardown(tester);
    },
  );

  testWidgets('Home without stored profiles: notice instead of cards', (
    tester,
  ) async {
    bigScreen(tester);
    await tester.pumpWidget(app(const Scaffold(body: ProfileCarousel())));
    await settle(tester);
    expect(
      find.textContaining('saved once the machine is connected'),
      findsOneWidget,
    );
    await teardown(tester);
  });

  // Tear down the widget tree so no stream query holds the DB lock any more.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  // DB read in real time; first let the pending stream queries in the
  // widget tree finish, otherwise both block each other (drift lock).
  Future<StoredProfile> stored(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final result = await tester.runAsync(() async {
      final all = await db.storedProfilesById();
      return all.values.firstWhere((p) => p.name == name);
    });
    return result!;
  }

  testWidgets('enter a custom description, survives sync, can be reset', (
    tester,
  ) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Bailey - PSPH / Soup'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    // Bailey has no description on the machine.
    expect(
      find.text('No description yet. Tap the pencil to add one.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      '  Pure pressure soup. Aim for a peak of 1–5 bar.  ',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(
      find.text('Pure pressure soup. Aim for a peak of 1–5 bar.'),
      findsOneWidget,
    );
    expect(find.text('DESCRIPTION · EDITED'), findsOneWidget);
    expect(
      find.text('Show more'),
      findsNothing,
      reason: 'short text is not collapsed',
    );

    // Syncing with the machine does not overwrite the custom text.
    // (Start in the same time window as the widget tree, not in runAsync:
    // otherwise the drift lock blocks.)
    unawaited(sync.sync());
    await settle(tester);
    await settle(tester);
    expect(
      find.text('Pure pressure soup. Aim for a peak of 1–5 bar.'),
      findsOneWidget,
    );

    // Cancel changes nothing.
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(
      find.text('Pure pressure soup. Aim for a peak of 1–5 bar.'),
      findsOneWidget,
    );
    expect(find.text('draft'), findsNothing);

    // Back to the machine's text (here: none).
    await tester.tap(find.byTooltip('Edit description'));
    await tester.pump();
    await tester.tap(find.text('Use machine text'));
    await settle(tester);
    expect(
      find.text('No description yet. Tap the pencil to add one.'),
      findsOneWidget,
    );
    expect(find.text('DESCRIPTION'), findsOneWidget);

    await unmount(tester);
    expect(
      (await stored(tester, 'Bailey - PSPH / Soup')).customDescription,
      isNull,
    );
    await tester.runAsync(db.close);
  });

  testWidgets(
    'long description is collapsed after a few lines and expandable',
    (tester) async {
      bigScreen(tester);
      await seedStored(tester);
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Turbo'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Show more'), findsOneWidget);
      // Collapsed: the last paragraph is not rendered visibly (max. 4 lines).
      double descriptionHeight() => tester
          .getSize(
            find.textContaining('Immediately ramps-up', findRichText: true),
          )
          .height;
      final collapsed = descriptionHeight();
      await tester.tap(find.text('Show more'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
      expect(descriptionHeight(), greaterThan(collapsed));
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(find.text('Show more'), findsOneWidget);
      expect(descriptionHeight(), collapsed);

      // The custom text replaces the machine's (and is short -> no toggle).
      await tester.tap(find.byTooltip('Edit description'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'My note');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('My note'), findsOneWidget);
      expect(find.textContaining('Immediately ramps-up'), findsNothing);
      expect(find.text('Show more'), findsNothing);
      await teardown(tester);
    },
  );

  // Image.file with cacheWidth wraps the FileImage in a ResizeImage.
  bool showsFile(WidgetTester tester, String path) =>
      tester.widgetList<Image>(find.byType(Image)).any((i) {
        final provider = i.image is ResizeImage
            ? (i.image as ResizeImage).imageProvider
            : i.image;
        return provider is FileImage && provider.file.path == path;
      });

  testWidgets(
    'pick a custom photo, takes precedence over the machine one, reset',
    (tester) async {
      bigScreen(tester);
      await seedStored(tester);
      final photo = File('${imageDir.path}/my_photo.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
          ),
        );
      final sources = <String>[];
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            machine: machine,
            store: sync,
            summary: summary('Turbo'),
            pickPhoto: (source) async {
              sources.add(source);
              return photo.path;
            },
          ),
        ),
      );
      await settle(tester);
      expect(showsFile(tester, photo.path), isFalse);

      await tester.tap(find.byTooltip('Change photo'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      expect(
        find.text('Use the machine image'),
        findsNothing,
        reason: 'no custom photo yet',
      );
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(sources, ['gallery']);
      expect(
        showsFile(tester, photo.path),
        isTrue,
        reason: 'custom photo in the header',
      );

      // Syncing leaves it untouched.
      unawaited(sync.sync());
      await settle(tester);
      await settle(tester);
      expect(showsFile(tester, photo.path), isTrue);

      await unmount(tester);
      final custom = await stored(tester, 'Turbo');
      expect(custom.customImagePath, photo.path);
      // Cards in the Home tab show the custom photo (precedence over the
      // machine one).
      expect(MachineProfile.fromStored(custom).localImagePath, photo.path);

      // Reset: machine image, custom file is deleted.
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Turbo'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use the machine image'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(photo.existsSync(), isFalse, reason: 'custom copy is deleted');
      expect(showsFile(tester, photo.path), isFalse);

      await unmount(tester);
      expect((await stored(tester, 'Turbo')).customImagePath, isNull);
      await tester.runAsync(db.close);
    },
  );

  // Delete button at the bottom of the page. It goes through
  // the shared machine interface and so applies to every machine.
  testWidgets('delete removes the profile on the machine and in the app', (
    tester,
  ) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);
    final id = summary('Turbo').id;
    expect(await db.storedProfilesById(), contains(id));

    await tester.ensureVisible(find.text('Delete profile'));
    await tester.pump();
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    // Ask first.
    expect(find.text('Delete profile?'), findsOneWidget);
    expect(find.textContaining('stay in your history'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(machine.deleted, [id], reason: 'deleted on the machine');
    expect(await db.storedProfilesById(), isNot(contains(id)));
    // The screen closes afterwards.
    expect(find.byType(ProfileDetailScreen), findsNothing);
    await teardown(tester);
  });

  testWidgets(
    'the pencil at the top opens the editor with the profile values',
    (tester) async {
      bigScreen(tester);
      await seedStored(tester);
      await tester.pumpWidget(
        app(
          ProfileDetailScreen(
            summary: summary('Turbo'),
            machine: machine,
            store: sync,
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();

      // The editor is shown and has taken over the machine's values.
      expect(find.byType(ProfileEditorScreen), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Turbo'), findsOneWidget);

      await teardown(tester);
    },
  );

  testWidgets('delete sits at the very bottom, no longer in the header', (
    tester,
  ) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    // The header now holds the pencil, no trash can any more.
    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(find.byTooltip('Delete profile'), findsNothing);

    // The trash can is a labeled button at the end of the page.
    final delete = find.widgetWithText(AppButton, 'Delete profile');
    expect(delete, findsOneWidget);
    expect(
      tester.widget<AppButton>(delete).variant,
      AppButtonVariant.destructive,
    );

    await teardown(tester);
  });

  testWidgets('cancel deletes nothing', (tester) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    await tester.ensureVisible(find.text('Delete profile'));
    await tester.pump();
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(machine.deleted, isEmpty);
    expect(await db.storedProfilesById(), contains(summary('Turbo').id));
    expect(find.byType(ProfileDetailScreen), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('if the machine refuses, the copy stays too', (tester) async {
    bigScreen(tester);
    await seedStored(tester);
    // Otherwise the profile would be gone from the app but still on the
    // machine — and would come back on the next sync.
    machine.deleteError = 'profile is in use';
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          summary: summary('Turbo'),
          machine: machine,
          store: sync,
        ),
      ),
    );
    await settle(tester);

    await tester.ensureVisible(find.text('Delete profile'));
    await tester.pump();
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(await db.storedProfilesById(), contains(summary('Turbo').id));
    expect(find.byType(ProfileDetailScreen), findsOneWidget);
    expect(find.textContaining('profile is in use'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('photo picking fails: notice, nothing saved', (tester) async {
    bigScreen(tester);
    await seedStored(tester);
    await tester.pumpWidget(
      app(
        ProfileDetailScreen(
          machine: machine,
          store: sync,
          summary: summary('Turbo'),
          pickPhoto: (_) async => throw Exception('no camera'),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load photo'), findsOneWidget);

    await unmount(tester);
    expect((await stored(tester, 'Turbo')).customImagePath, isNull);
    await tester.runAsync(db.close);
  });
}

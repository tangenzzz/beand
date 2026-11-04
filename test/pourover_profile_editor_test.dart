import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/live/pourover/add_pourover_profile.dart';
import 'package:beand/screens/live/pourover/pourover_profile_editor.dart';
import 'package:beand/screens/profile/pourover_profile_detail_screen.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MachineScale extends SimulatedScale {
  @override
  bool get isMachineScale => true;
}

void main() {
  late Directory dir;
  late AppDatabase db;
  late BrewRecipeStore store;
  late PourOverBrewService brew;
  late GearStore gear;
  late List<Map<String, dynamic>> uploaded;
  late bool machineOffline;

  Future<void> setUp0(WidgetTester tester, {bool machineMode = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dir = Directory.systemTemp.createTempSync('beand_editor');
    addTearDown(() => dir.deleteSync(recursive: true));
    db = AppDatabase(NativeDatabase.memory());
    uploaded = [];
    machineOffline = false;
    gear = GearStore.inMemory();
    await tester.runAsync(() async {
      store = BrewRecipeStore(
        cacheFile: File('${dir.path}/no-cache.json'),
        loadBundled: () async => jsonEncode(
          BrewRecipeBundle(
            commit: 'x',
            fetchedAt: DateTime(2026),
            raw: const [],
          ).toJson(),
        ),
      );
      await store.load();
      if (machineMode) {
        store.machineSource = MeticulousPourOverProfiles(
          host: () => 'machine',
          client: MockClient((request) async {
            if (machineOffline) throw const SocketException('offline');
            if (request.method == 'POST') {
              uploaded.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response('{}', 200);
            }
            if (request.url.path.endsWith('/list')) {
              return http.Response(jsonEncode({'profiles': uploaded}), 200);
            }
            return http.Response('', 404);
          }),
        );
      }
      brew = PourOverBrewService(
        scale: machineMode ? _MachineScale() : SimulatedScale(),
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
    });
  }

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
      ChangeNotifierProvider<PourOverBrewService>.value(value: brew),
      ChangeNotifierProvider<GearStore>.value(value: gear),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: home),
  );

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets('"+" → Create new profile: saved in the app, nothing sent', (
    tester,
  ) async {
    await setUp0(tester);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAddPourOverProfile(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new profile'));
    await tester.pumpAndSettle();
    expect(find.byType(PourOverProfileEditor), findsOneWidget);
    // Prefilled, one page, one card: the two starting pours are there.
    expect(find.text('Bloom'), findsOneWidget);
    expect(find.text('Pour 2'), findsOneWidget);
    expect(find.text('1:16.0'), findsOneWidget);
    expect(find.text('2:30 – 3:00'), findsOneWidget);

    // No Save without a name.
    final saveButton = find.widgetWithText(TextButton, 'Save');
    expect(tester.widget<TextButton>(saveButton).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'Morning',
    );
    await tester.pump();
    await save(tester);

    expect(find.byType(PourOverProfileEditor), findsNothing);
    expect(store.ownRecipes.single.name, 'Morning');
    expect(store.ownRecipes.single.fromMachine, isFalse);
    expect(uploaded, isEmpty);
    await finish(tester);
  });

  testWidgets('pours fold out in place, one at a time, and change the page', (
    tester,
  ) async {
    await setUp0(tester);
    await tester.pumpWidget(app(const PourOverProfileEditor()));
    await tester.pump();
    expect(find.byKey(const ValueKey('pour-flow-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pour-row-0')));
    await tester.pumpAndSettle();
    expect(find.text('4.5 g/s'), findsOneWidget);
    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pour-temp-exact-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pour-row-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pour-flow-0')), findsNothing);
    expect(find.byKey(const ValueKey('pour-flow-1')), findsOneWidget);
    // The last pour's wait is the drawdown.
    expect(find.text('Drawdown'), findsOneWidget);

    // Add up to five; then the limit shows instead of "+".
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('profile-add-pour')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('profile-add-pour')), findsNothing);
    expect(find.text('5 at most'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pour-delete-4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-add-pour')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Machine mode: goes onto the machine by itself, clean', (
    tester,
  ) async {
    await setUp0(tester, machineMode: true);
    await tester.pumpWidget(app(const PourOverProfileEditor()));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'Dial',
    );
    await tester.pump();
    await save(tester);
    expect(uploaded.single['name'], 'Dial');
    expect(uploaded.single.containsKey('beand'), isFalse);
    // In both lists, shown once.
    expect(store.ownRecipes.where((r) => r.name == 'Dial').length, 1);
    await finish(tester);
  });

  testWidgets('Machine mode, machine away: kept in the app, says so', (
    tester,
  ) async {
    await setUp0(tester, machineMode: true);
    machineOffline = true;
    await tester.pumpWidget(app(const Scaffold(body: PourOverProfileEditor())));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'Offline',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(store.importedRecipes.single.name, 'Offline');
    expect(uploaded, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(db.close);
  });

  testWidgets('Edit from the profile page keeps ID and the rest', (
    tester,
  ) async {
    await setUp0(tester);
    final id = store.importProfile({
      'version': 1,
      'brew_type': 'pour_over',
      'id': '9b2f9d4e-1111-4222-8333-944455556666',
      'name': 'Old',
      'author': 'Someone',
      'author_id': '50e75a28-2b94-400a-bc6b-f4b9e6f3709a',
      'recipe': {
        'coffee_dose_g': 16,
        'total_water_g': 50,
        'water_temperature_c': 94,
        'target_total_time_s': 60,
        'water': {'name': 'Lotus'},
      },
      'stages': [
        {
          'key': 'p1',
          'name': 'Bloom',
          'starts_at_s': 0,
          'pour': {
            'water_g': 50,
            'duration_s': 10,
            'target_cumulative_water_g': 50,
            'flow_rate_g_s': 5,
          },
        },
      ],
    }).id;
    final recipe = store.importedRecipes.single;
    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<AppDatabase>.value(value: db)],
        child: app(PourOverProfileDetailScreen(recipe: recipe)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'New name',
    );
    await tester.pump();
    await save(tester);

    final updated = store.importedRecipes.single;
    expect(updated.id, id);
    expect(updated.name, 'New name');
    final raw = store.editableProfile(id)!;
    expect(raw['author'], 'Someone');
    expect(((raw['recipe'] as Map)['water'] as Map)['name'], 'Lotus');
    await finish(tester);
  });

  testWidgets('leaving with changes asks first', (tester) async {
    await setUp0(tester);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PourOverProfileEditor(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Nothing changed: out right away.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PourOverProfileEditor), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'x',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(PourOverProfileEditor), findsNothing);
    expect(store.importedRecipes, isEmpty);
    await finish(tester);
  });

  test('own profiles travel with the sync', () {
    expect(syncedSettingKeys(), contains(BrewRecipeStore.importedPrefKey));
  });

  testWidgets('choosing a chain names its brewer and filter', (tester) async {
    await setUp0(tester);
    final brewer = gear.save(
      const Gear(id: '', type: GearType.brewer, model: 'V60'),
    );
    final filter = gear.save(
      const Gear(id: '', type: GearType.filter, model: 'Cafec'),
    );
    final chain = gear.saveChain(
      BrewChain(id: '', name: 'Home', gearIds: [brewer.id, filter.id]),
    );
    await tester.pumpWidget(app(const PourOverProfileEditor()));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name')).first,
      'Chained',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-chain')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await save(tester);
    final raw = store.importedRecipes.single;
    final stored = store.editableProfile(raw.id)!;
    expect(((stored['recipe'] as Map)['brewer'] as Map)['name'], 'V60');
    expect(((stored['recipe'] as Map)['filter'] as Map)['name'], 'Cafec');
    expect((stored['beand'] as Map)['chain_id'], chain.id);
    await finish(tester);
  });
}

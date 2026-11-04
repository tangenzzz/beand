import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/live/pourover/add_pourover_profile.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = {
  'version': 1,
  'brew_type': 'pour_over',
  'id': '9b2f9d4e-1111-4222-8333-944455556666',
  'name': 'Community Cone',
  'author': 'Someone',
  'author_id': '50e75a28-2b94-400a-bc6b-f4b9e6f3709a',
  'recipe': {
    'coffee_dose_g': 16,
    'total_water_g': 256,
    'water_temperature_c': 94,
    'target_total_time_s': 180,
  },
  'stages': [
    {
      'key': 'p1',
      'name': 'Bloom',
      'starts_at_s': 0,
      'pour': {
        'water_g': 50,
        'duration_s': 8,
        'target_cumulative_water_g': 50,
        'flow_rate_g_s': 6,
      },
    },
  ],
};

void main() {
  testWidgets('"+": a .json file from the device becomes an own profile; '
      'an espresso profile is turned away', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('beand_po');
    addTearDown(() => dir.deleteSync(recursive: true));
    final good = File('${dir.path}/cone.json')
      ..writeAsStringSync(jsonEncode(_profile));
    final espresso = File('${dir.path}/espresso.json')
      ..writeAsStringSync(jsonEncode({'name': 'Shot', 'stages': []}));

    final db = AppDatabase(NativeDatabase.memory());
    late BrewRecipeStore store;
    late PourOverBrewService brew;
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
      brew = PourOverBrewService(
        scale: SimulatedScale(),
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
    });

    var pick = good.path;
    final opened = <Uri>[];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
          ChangeNotifierProvider<PourOverBrewService>.value(value: brew),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddPourOverProfile(
                  context,
                  pickJsonFile: () async => pick,
                  openUrl: (u) async {
                    opened.add(u);
                    return true;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Upload .json file'), findsOneWidget);
    expect(find.text('Brew-recipes'), findsOneWidget);
    expect(find.text('community.meticuloushome.com'), findsOneWidget);
    expect(find.text('github.com/HotThoughts/brew-recipes'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Upload .json file'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.ownRecipes.map((r) => r.name), ['Community Cone']);
    expect(find.text('Added "Community Cone"'), findsOneWidget);

    // Let the first message go (messages queue up).
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // An espresso profile is no pour over profile.
    pick = espresso.path;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Upload .json file'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Not a pour over profile'), findsOneWidget);
    expect(store.ownRecipes.length, 1);

    // The community site opens in the browser.
    await tester.tap(find.text('community.meticuloushome.com'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'community.meticuloushome.com');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('"+" → Brew-recipes: a recipe opens like a profile card, '
      'back leads to the "+" dialog again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('beand_po2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    late BrewRecipeStore store;
    late PourOverBrewService brew;
    await tester.runAsync(() async {
      store = BrewRecipeStore(
        cacheFile: File('${dir.path}/no-cache.json'),
        loadBundled: () async => jsonEncode(
          BrewRecipeBundle(
            commit: 'x',
            fetchedAt: DateTime(2026),
            raw: [
              {
                'id': 'two-pours',
                'name': 'Two Pours',
                'brewer': 'V60',
                'dose_g': 15,
                'water_ml': 250,
                'water_temp_c': 94,
                'grind_size': 'medium',
                'phases': [
                  {'label': 'Bloom', 'water_g': 50, 'wait_seconds': 30},
                  {'label': 'Main', 'water_g': 200},
                ],
                'source': {'name': 'Test'},
              },
            ],
          ).toJson(),
        ),
      );
      await store.load();
      brew = PourOverBrewService(
        scale: SimulatedScale(),
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
          ChangeNotifierProvider<PourOverBrewService>.value(value: brew),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddPourOverProfile(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a profile from this device'), findsOneWidget);
    await tester.tap(find.text('Brew-recipes'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Brew-recipes'), findsOneWidget);

    // The row opens the recipe; the box adds it.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(store.isEnabled('two-pours'), isTrue);
    await tester.tap(find.text('Two Pours'));
    await tester.pumpAndSettle();
    expect(find.text('Bloom'), findsWidgets);

    // Back twice: the "+" dialog again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Add profile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

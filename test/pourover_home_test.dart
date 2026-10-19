import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/brew_recipe.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/live/pourover/live_brew_card.dart';
import 'package:beand/screens/live/pourover/pourover_home.dart';
import 'package:beand/screens/live/pourover/pre_brew_card.dart';
import 'package:beand/screens/live/sensor_stack.dart';
import 'package:beand/screens/profile/pourover_profile_detail_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:beand/services/gear_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

final _recipe = BrewRecipe.fromJson({
  'id': 'two-pours',
  'name': 'Two Pours',
  'brewer': 'V60',
  'dose_g': 15,
  'water_ml': 250,
  'ratio': '1:16.7',
  'water_temp_c': 94,
  'grind_size': 'medium',
  'phases': [
    {
      'label': 'Bloom',
      'water_g': 50,
      'wait_seconds': 30,
      'note': 'Swirl gently',
    },
    {'label': 'Main', 'water_g': 200, 'wait_seconds': 0},
  ],
  'source': {'name': 'Test'},
});

void main() {
  late AppDatabase db;
  late SimulatedScale scale;
  late BrewRecipeStore store;
  late PourOverBrewService brew;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    scale = SimulatedScale();
    store = BrewRecipeStore(
      cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
      loadBundled: () async => jsonEncode(
        BrewRecipeBundle(
          commit: 'x',
          fetchedAt: DateTime(2026),
          raw: [_recipe.toJson()],
        ).toJson(),
      ),
    );
    await store.load();
    // After a fresh install nothing is checked; here the user adds the
    // test profile to the view.
    store.setEnabled(_recipe.id, true);
    brew = PourOverBrewService(
      scale: scale,
      recipes: store,
      setup: ShotSetup.inMemory(machineKey: 'pourover'),
      database: db,
    )..start();
    brew.selectRecipe(_recipe);
  });

  Widget wrap() => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      // With a gear store the brew chain row shows below the grind row.
      ChangeNotifierProvider<GearStore>.value(value: GearStore.inMemory()),
      ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
      ChangeNotifierProvider<AiSettings>.value(
        value: AiSettings(keyStore: InMemoryAiKeyStore()),
      ),
      ChangeNotifierProvider<BrewScale>.value(value: scale),
      ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
      ChangeNotifierProvider<PourOverBrewService>.value(value: brew),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SingleChildScrollView(child: PourOverHome())),
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  // Time and weight next to the ring are large (read while pouring), on a
  // phone-width screen without overflowing.
  testWidgets('hero: time and weight are shown large', (tester) async {
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      final time = tester.widget<Text>(
        find.descendant(
          of: find.byType(SensorStack),
          matching: find.text('0:00'),
        ),
      );
      expect(time.style?.fontSize, 28);
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    });
  });

  testWidgets('connects the scale, brews a recipe and lands on Post Brew', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      // The scale connects on opening; Pre Brew shows the recipe.
      expect(scale.isConnected, isTrue);
      // Once in Pre Brew, once in the profile row below.
      expect(find.text('Two Pours'), findsNWidgets(2));
      expect(find.text('250 g  ·  1:16.7'), findsOneWidget);
      expect(find.text('Start Brew'), findsOneWidget);
      expect(find.text('PRE'), findsOneWidget);
      expect(find.text('Brew'), findsWidgets);

      await tester.ensureVisible(find.text('Start Brew'));
      await tester.tap(find.text('Start Brew'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
      expect(brew.stage, ShotStage.running);
      expect(
        find.textContaining('START POURING', findRichText: true),
        findsOneWidget,
      );

      scale.setGrams(20);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      scale.setGrams(50);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      expect(brew.phase, BrewState.waiting);
      expect(find.textContaining('WAIT', findRichText: true), findsOneWidget);
      expect(find.byType(LiveBrewCard), findsOneWidget);

      await tester.ensureVisible(find.text('Finish'));
      await tester.tap(find.text('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(brew.stage, ShotStage.purging);
      final shots = await db.select(db.shots).get();
      expect(shots.single.machine, 'pourover');
      expect(shots.single.finalWeight, closeTo(50, 0.2));

      // The scale stays connected when the view goes away (pill switch).
      await disposeTree(tester);
      expect(scale.isConnected, isTrue);
      await scale.disconnect();
    });
  });

  testWidgets('without a scale the start button connects instead', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      await scale.disconnect();
      await tester.pump();
      expect(find.text('Connect Scale'), findsOneWidget);
      expect(find.text('Start Brew'), findsNothing);
      expect(find.byType(PreBrewCard), findsOneWidget);
      await disposeTree(tester);
    });
  });

  testWidgets(
    'profile detail shows the pours; Delete removes it from the selection',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
            ],
            child: MaterialApp(
              theme: buildAppTheme(),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PourOverProfileDetailScreen(recipe: _recipe),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.text('Pour breakdown'), findsOneWidget);
        expect(find.text('Bloom'), findsOneWidget);
        expect(find.text('2 pours'), findsOneWidget);
        expect(find.byTooltip('Change photo'), findsOneWidget);
        expect(store.isEnabled(_recipe.id), isTrue);

        await tester.scrollUntilVisible(find.text('Delete profile'), 200);
        await tester.tap(find.text('Delete profile'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(store.isEnabled(_recipe.id), isFalse);
        expect(find.text('open'), findsOneWidget); // view closed
        await disposeTree(tester);
      });
    },
  );
}

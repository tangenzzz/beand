import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/brew_recipe.dart';
import 'package:beand/models/grind_scale.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/screens/live/grind_from_zero.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BrewRecipe _recipe(String id, String name) => BrewRecipe.fromJson({
  'id': id,
  'name': name,
  'brewer': 'V60',
  'dose_g': 15,
  'water_ml': 250,
  'ratio': '1:16.7',
  'water_temp_c': 94,
  'grind_size': 'medium',
  'phases': [
    {'label': 'Main', 'water_g': 250, 'wait_seconds': 0},
  ],
  'source': {'name': 'Test'},
});

class _IdleScale extends BrewScale {
  @override
  ScaleConnection get connection => ScaleConnection.disconnected;
  @override
  String? get deviceName => null;
  @override
  double? get grams => null;
  @override
  String? get error => null;
  @override
  Stream<ScaleReading> get readings => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> tare() async {}
  @override
  Future<void> startTimer() async {}
  @override
  Future<void> stopTimer() async {}
  @override
  Future<void> resetTimer() async {}
}

// Bugs 2026-11-22: a 1Zpresso-style grinder stores 77 clicks, the history
// list showed "77" instead of "7.7"; and pour over never took the grind of
// the last brew with the chosen recipe/bean.
void main() {
  group('grindDisplayText', () {
    test('clicks counted in rotations read as on the grinder', () {
      final g = Grinder(
        id: 'zp',
        name: 'ZP6',
        scale: GrindScale.rotary(clicksPerRotation: 90, clicksPerNumber: 10),
      );
      expect(grindDisplayText('77', g), '7.7');
    });

    test('without a grinder or scale the stored text stays', () {
      expect(grindDisplayText('3.25', null), '3.25');
      expect(grindDisplayText('3.2', const Grinder(id: 'x', name: 'X')), '3.2');
      expect(grindDisplayText(null, null), isNull);
    });
  });

  group('pour over: grind from the last brew', () {
    late AppDatabase db;
    late PourOverBrewService service;
    late ShotSetup setup;
    final a = _recipe('a', 'Recipe A');
    final b = _recipe('b', 'Recipe B');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      final store = BrewRecipeStore(
        cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
        loadBundled: () async => jsonEncode(
          BrewRecipeBundle(
            commit: 'x',
            fetchedAt: DateTime(2026),
            raw: [a.toJson(), b.toJson()],
          ).toJson(),
        ),
      );
      setup = ShotSetup.inMemory(machineKey: 'pourover');
      service = PourOverBrewService(
        scale: _IdleScale(),
        recipes: store,
        setup: setup,
        database: db,
      );
    });
    tearDown(() => db.close());

    Future<int> bean(String name) =>
        db.into(db.beans).insert(BeansCompanion.insert(name: name));

    Future<void> brew(
      String recipe,
      String grind, {
      int? beanId,
      DateTime? at,
      String machine = 'pourover',
    }) => db
        .into(db.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: at ?? DateTime(2026, 11, 20),
            machine: Value(machine),
            profileName: Value(recipe),
            beanId: Value(beanId),
            doseGrams: const Value(15),
            grindSize: Value(grind),
          ),
        );

    Future<void> settle() => Future<void>.delayed(Duration.zero)
        .then((_) => Future<void>.delayed(const Duration(milliseconds: 10)));

    test('a recipe change brings back its last grind', () async {
      await brew('Recipe A', '22', at: DateTime(2026, 11, 19));
      await brew('Recipe B', '30', at: DateTime(2026, 11, 20));
      service.selectRecipe(a);
      await settle();
      expect(setup.grindSize, 22);
      service.selectRecipe(b);
      await settle();
      expect(setup.grindSize, 30);
    });

    test('the selected coffee first, else the recipe alone', () async {
      final kenya = await bean('Kenya');
      final peru = await bean('Peru');
      await brew('Recipe A', '18', beanId: kenya, at: DateTime(2026, 11, 18));
      await brew('Recipe A', '24', beanId: peru, at: DateTime(2026, 11, 19));
      setup.setBean(kenya);
      service.selectRecipe(a);
      await settle();
      expect(setup.grindSize, 18);
      // A coffee never brewed with it: the recipe's last grind.
      setup.setBean(await bean('Brazil'));
      await service.applyLastGrind();
      expect(setup.grindSize, 24);
    });

    test('espresso shots and shots without grind do not count', () async {
      await brew('Recipe A', '12', at: DateTime(2026, 11, 18));
      await brew('Recipe A', '5', machine: 'meticulous');
      await brew('Recipe A', '', at: DateTime(2026, 11, 21));
      service.selectRecipe(a);
      await settle();
      expect(setup.grindSize, 12);
    });

    test('never brewed with the recipe: the grind stays', () async {
      setup.setGrind(16);
      service.selectRecipe(a);
      await settle();
      expect(setup.grindSize, 16);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/brew_plan.dart';
import 'package:beand/models/brew_recipe.dart';
import 'package:beand/scale/acaia_protocol.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    {'label': 'Bloom', 'water_g': 50, 'wait_seconds': 30},
    {'label': 'Main', 'water_g': 200, 'wait_seconds': 0},
  ],
  'source': {'name': 'Test'},
});

/// Scale whose values the test sends by hand.
class _ManualScale extends BrewScale {
  final _ctrl = StreamController<ScaleReading>.broadcast(sync: true);
  int tares = 0;
  @override
  ScaleConnection connection = ScaleConnection.connected;
  @override
  String? get deviceName => 'TEST';
  @override
  double? grams;
  @override
  String? get error => null;
  @override
  Stream<ScaleReading> get readings => _ctrl.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> tare() async => tares++;

  final timer = <String>[];
  @override
  Future<void> startTimer() async => timer.add('start');
  @override
  Future<void> stopTimer() async => timer.add('stop');
  @override
  Future<void> resetTimer() async => timer.add('reset');

  void send(double g, DateTime at) {
    grams = g;
    _ctrl.add(ScaleReading(g, at));
  }
}

BrewRecipeStore _storeWith(List<BrewRecipe> recipes) => BrewRecipeStore(
  cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
  loadBundled: () async => jsonEncode(
    BrewRecipeBundle(
      commit: 'x',
      fetchedAt: DateTime(2026),
      raw: [for (final r in recipes) r.toJson()],
    ).toJson(),
  ),
);

BrewRecipe _renamed(String id) =>
    BrewRecipe.fromJson({..._recipe.toJson(), 'id': id, 'name': id});

void main() {
  group('Profile selection', () {
    test(
      'fresh install: nothing selected; new ones later are not either',
      () async {
        SharedPreferences.setMockInitialValues({});
        final first = _storeWith([_recipe]);
        await first.load();
        expect(first.enabledRecipes, isEmpty);
        expect(first.newCount, 0);
        first.setEnabled('two-pours', true);
        expect(first.enabledRecipes.map((r) => r.id), ['two-pours']);
        first.setEnabled('two-pours', false);
        expect(first.enabledRecipes, isEmpty);
        await Future<void>.delayed(Duration.zero);

        // Next start with an additional profile (e.g. from GitHub).
        final later = _storeWith([_recipe, _renamed('fresh-one')]);
        await later.load();
        expect(later.isEnabled('two-pours'), isFalse); // stays unchecked
        expect(later.isEnabled('fresh-one'), isFalse);
        expect(later.isNew('fresh-one'), isTrue);
        later.markAllSeen();
        expect(later.newCount, 0);
      },
    );
  });

  group('Acaia protocol', () {
    test('parses a complete weight frame', () {
      // EF DD 0C len 05 | 0x04D2 = 1234 → 123.4 g (1 decimal place)
      final p = [0xef, 0xdd, 0x0c, 0x08, 0x05, 0xd2, 0x04, 0, 0, 1, 0, 0, 0];
      expect(AcaiaFrameParser().feed(p).single, closeTo(123.4, 1e-9));
      final neg = List.of(p)..[10] = 0x02;
      expect(AcaiaFrameParser().feed(neg).single, closeTo(-123.4, 1e-9));
      // Other event (battery etc.) → no weight.
      final other = List.of(p)..[4] = 0x06;
      expect(AcaiaFrameParser().feed(other), isEmpty);
    });

    test('joins frames split across packets (older firmware)', () {
      final parser = AcaiaFrameParser();
      expect(parser.feed([0xef, 0xdd, 0x0c]), isEmpty);
      // Rest: len 05 | 10000 / 100 = 100 g | more bytes, then the next
      // header already cut off.
      expect(parser.feed([0x09, 0x05, 0x10, 0x27, 0, 0, 2, 0, 0, 0, 0xef]), [
        100,
      ]);
      expect(parser.feed([0xdd, 0x0c, 0x09, 0x05, 0x20, 0x4e, 0, 0, 2, 2, 0]), [
        -200,
      ]);
    });

    test('several frames in one packet, junk in between', () {
      final parser = AcaiaFrameParser();
      final frame = [0xef, 0xdd, 0x0c, 0x08, 0x05, 0x64, 0, 0, 0, 1, 0, 0, 0];
      final ack = [0xef, 0xdd, 0x08, 0x01, 0x02, 0x03];
      expect(parser.feed([0x01, 0x02, ...frame, ...ack, ...frame]), [10, 10]);
    });

    test('headerless fallback', () {
      expect(
        parseHeaderlessWeight([0x09, 0x05, 0x10, 0x27, 0, 0, 2, 0, 0, 0]),
        100,
      );
      expect(
        parseHeaderlessWeight([0x09, 0x07, 0x10, 0x27, 0, 0, 2, 0, 0, 0]),
        isNull,
      );
    });

    test('recognises Acaia names', () {
      expect(isAcaiaName('LUNAR-123ABC'), isTrue);
      expect(isAcaiaName('pearls'), isTrue);
      expect(isAcaiaName('Decent Scale'), isFalse);
    });

    test('short model names from the advertised name', () {
      // Both read off real scales.
      expect(scaleShortName('PROCHBT001'), 'Pearl');
      expect(scaleShortName('ACAIAL13006'), 'Lunar');
      expect(scaleShortName('PEARLS-12AB'), 'Pearl S');
      expect(scaleShortName('Something'), 'Something');
      expect(scaleShortName(null), 'Scale');
    });
  });

  group('BrewPlan', () {
    test('scales steps with dose', () {
      final plan = BrewPlan(_recipe, doseG: 18);
      expect(plan.steps.map((s) => s.targetTotalG), [60, 300]);
      expect(plan.totalWaterG, 300);
    });

    test('target curve: pour at ideal flow, then wait', () {
      final plan = BrewPlan(_recipe);
      expect(plan.targetAt(5), 25);
      expect(plan.targetAt(10), 50); // bloom fully poured
      expect(plan.targetAt(39), 50); // pause
      expect(plan.targetAt(40), 50);
      expect(plan.targetAt(80), 250);
      expect(plan.plannedSeconds, 10 + 30 + 40);
    });

    test('flow zones', () {
      expect(flowZone(5), FlowZone.green);
      expect(flowZone(7), FlowZone.yellow);
      expect(flowZone(0), FlowZone.red);
    });

    test('flow estimator follows a steady pour', () {
      final f = FlowEstimator();
      for (var ms = 0; ms <= 2000; ms += 100) {
        f.add(ms, ms / 1000 * 4);
      }
      expect(f.gramsPerSecond, closeTo(4, 1e-6));
    });
  });

  group('PourOverBrewService', () {
    late AppDatabase db;
    late _ManualScale scale;
    late PourOverBrewService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      scale = _ManualScale();
      final store = BrewRecipeStore(
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
      service = PourOverBrewService(
        scale: scale,
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
      service.selectRecipe(_recipe);
    });

    tearDown(() => db.close());

    test('cannot start without a connected scale', () async {
      scale.connection = ScaleConnection.disconnected;
      scale.notifyListeners();
      expect(service.stabilized, isFalse);
      expect(await service.startShot(), isFalse);
    });

    test('runs through pours, waits and saves a pour-over shot', () {
      fakeAsync((async) {
        expect(service.stabilized, isTrue);
        service.startShot();
        async.flushMicrotasks();
        expect(scale.tares, 1);
        expect(service.stage, ShotStage.running);
        expect(service.activeCard, ActiveCard.live);
        expect(service.phase, BrewState.armed);

        var t = clock.now();
        void at(double g, {int ms = 200}) {
          t = t.add(Duration(milliseconds: ms));
          async.elapse(Duration(milliseconds: ms));
          scale.send(g, t);
        }

        at(0.0);
        at(0.5);
        expect(service.phase, BrewState.armed);
        // Start resets the scale's timer, the first water starts it.
        expect(scale.timer, ['reset']);
        at(5);
        expect(service.phase, BrewState.pouring);
        for (var g = 10.0; g <= 50; g += 5) {
          at(g);
        }
        expect(service.phase, BrewState.waiting);
        expect(service.stepIndex, 1);
        expect(service.currentStep!.label, 'Main');
        expect(service.waitLeftSeconds, closeTo(30, 0.5));

        // Pause runs out (scale keeps reporting 50 g).
        for (var i = 0; i < 160; i++) {
          at(50);
        }
        expect(service.phase, BrewState.pouring);

        for (var g = 55.0; g <= 250; g += 5) {
          at(g);
        }
        expect(service.phase, BrewState.drawdown);

        // Weight is steady while the water drips through — the brew keeps
        // running (time and chart) until "Finish".
        for (var i = 0; i < 240; i++) {
          at(250);
        }
        async.flushMicrotasks();
        expect(service.stage, ShotStage.running);
        expect(service.phase, BrewState.drawdown);
        expect(service.elapsedMs, greaterThan(60000));
        expect(scale.timer, ['reset', 'start']);
        service.stopShot();
        async.flushMicrotasks();
        expect(service.stage, ShotStage.purging);
        expect(scale.timer, ['reset', 'start', 'stop']);
        expect(service.activeCard, ActiveCard.post);
      });

      return db.select(db.shots).get().then((shots) {
        expect(shots, hasLength(1));
        final s = shots.single;
        expect(s.machine, 'pourover');
        expect(s.profileName, 'Two Pours');
        expect(s.doseGrams, 15);
        expect(s.finalWeight, 250);
        expect(s.profileTemp, 94);
        service.confirmPostShot();
        expect(service.stage, ShotStage.idle);
        expect(service.activeCard, ActiveCard.pre);
      });
    });

    test('manual mode: one free pour to the target, pauses do not end it', () {
      service.setManual(true);
      service.setManualWater(200);
      expect(service.plan!.steps, hasLength(1));
      expect(service.plan!.totalWaterG, 200);
      expect(service.temperature, isNull); // nothing from the recipe

      fakeAsync((async) {
        service.startShot();
        async.flushMicrotasks();
        var t = clock.now();
        void at(double g, {int ms = 200}) {
          t = t.add(Duration(milliseconds: ms));
          async.elapse(Duration(milliseconds: ms));
          scale.send(g, t);
        }

        at(0.0);
        for (var g = 5.0; g <= 40; g += 5) {
          at(g);
        }
        // Bloom: weight is steady for 30 s — the brew keeps running.
        for (var i = 0; i < 150; i++) {
          at(40);
        }
        expect(service.stage, ShotStage.running);
        expect(service.phase, BrewState.pouring);

        for (var g = 45.0; g <= 200; g += 5) {
          at(g);
        }
        expect(service.phase, BrewState.drawdown);
        for (var i = 0; i < 60; i++) {
          at(200);
        }
        async.flushMicrotasks();
        // Target reached, weight still: runs on until "Finish".
        expect(service.stage, ShotStage.running);
        service.stopShot();
        async.flushMicrotasks();
        expect(service.stage, ShotStage.purging);
      });

      return db.select(db.shots).get().then((shots) {
        expect(shots.single.profileName, 'Manual');
        expect(shots.single.finalWeight, 200);
      });
    });

    test('finish before any water discards the brew', () async {
      await service.startShot();
      expect(await service.stopShot(), isTrue);
      expect(service.stage, ShotStage.idle);
      expect(await db.select(db.shots).get(), isEmpty);
    });
  });
}

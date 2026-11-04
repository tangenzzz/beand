import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/brew_recipe.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/meticulous_scale.dart';
import 'package:beand/scale/scale_selector.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/meticulous_dial_brews.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/pourover_setup.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shape of a profile as GET /api/v1/pour-over/profile/list returned it on
// the real machine (2026-11-03), shortened.
final _machineProfile = <String, dynamic>{
  'version': 1,
  'brew_type': 'pour_over',
  'id': '2500765d-a7bd-4ec3-986c-1bb3f47dde8b',
  'name': 'One and Done',
  'author': 'Meticulous',
  'author_id': '50e75a28-2b94-400a-bc6b-f4b9e6f3709a',
  'recipe': {
    'coffee_dose_g': 15,
    'total_water_g': 225,
    'water_temperature_c': 93,
    'target_total_time_s': 150,
  },
  'stages': [
    {
      'key': 'pour-1',
      'name': 'Bloom',
      'starts_at_s': 0,
      'pour': {
        'water_g': 45,
        'duration_s': 6,
        'target_cumulative_water_g': 45,
        'flow_rate_g_s': 7.5,
        'pattern': 'spiral_out',
        'height_cm': 10,
      },
      'note': 'Spiral pour.',
    },
    {
      'key': 'pour-2',
      'name': 'Pour to 90 g',
      'starts_at_s': 30,
      'pour': {
        'water_g': 45,
        'duration_s': 6,
        'target_cumulative_water_g': 90,
        'flow_rate_g_s': 7.5,
      },
    },
    {
      'key': 'pour-3',
      'name': 'Pour to 225 g',
      'starts_at_s': 60,
      'pour': {
        'water_g': 135,
        'duration_s': 13,
        'target_cumulative_water_g': 225,
        'flow_rate_g_s': 10.38,
        'pattern': 'center',
      },
    },
  ],
  'display': {'shortDescription': 'Two small pours, then one more.'},
};

/// Socket without a network: the test sets the status by hand.
class _FakeSocket extends MeticulousSocketService {
  _FakeSocket() : super(hostname: 'test.local');

  final actions = <String>[];

  /// Whether the machine carries out a tare (false = ignores it).
  bool tares = true;

  // Load on the scale and the machine's own zero point.
  double _gross = 0;
  double _zero = 0;

  @override
  void connect() {}

  @override
  Future<bool> triggerAction(String action) async {
    actions.add(action);
    if (action == 'tare' && tares) {
      scheduleMicrotask(() {
        _zero = _gross;
        send(_gross);
      });
    }
    return true;
  }

  /// A press on the dial in its Pour Over mode: the machine tares itself.
  void dialTare() => _zero = _gross;

  /// [gross] = everything on the scale; the status carries it minus the
  /// machine's zero point.
  void send(double gross, {String state = 'idle', String name = 'idle'}) {
    _gross = gross;
    connectionState = MachineConnectionState.connected;
    latestStatus = MachineStatus.fromJson({
      'state': state,
      'name': name,
      'sensors': {'p': 0, 'f': 0, 'w': gross - _zero, 't': 25, 'g': 0},
    });
    notifyListeners();
  }
}

class _Steady {
  _Steady(this.scale);
  final StreamController<ScaleReading> scale;
  DateTime t = DateTime(2026, 11, 3, 12);

  /// [seconds] of steady weight in 100 ms steps.
  void hold(double g, {double seconds = 1.2}) {
    for (var i = 0; i < seconds * 10; i++) {
      t = t.add(const Duration(milliseconds: 100));
      scale.add(ScaleReading(g, t));
    }
  }
}

BrewRecipeStore _store(List<BrewRecipe> recipes) => BrewRecipeStore(
  cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
  loadBundled: () async => jsonEncode(
    BrewRecipeBundle(
      commit: 'x',
      fetchedAt: DateTime(2026),
      raw: [for (final r in recipes) r.toJson()],
    ).toJson(),
  ),
);

final _github = BrewRecipe.fromJson({
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
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Machine Pour Over profiles', () {
    test('map onto the recipe model', () {
      final r = brewRecipeFromMeticulous(_machineProfile);
      expect(r.fromMachine, isTrue);
      expect(r.doseG, 15);
      expect(r.waterTempC, 93);
      expect(r.brewer, 'Other');
      expect(r.sourceName, 'Meticulous');
      expect(r.description, 'Two small pours, then one more.');
      expect(r.steps.map((s) => s.targetTotalG), [45, 90, 225]);
      // Absolute start times → pause after each pour.
      expect(r.phases.map((p) => p.waitSeconds), [24, 24, null]);
      expect(r.phases.first.note, 'Spiral out, 10 cm high. Spiral pour.');
      expect(r.phases[1].note, isNull);
      expect(r.phases[2].note, 'Centre pour');
    });

    test('recognises the brewer and rejects espresso profiles', () {
      final v60 = brewRecipeFromMeticulous({
        ..._machineProfile,
        'recipe': {
          ...(_machineProfile['recipe'] as Map),
          'brewer': {'name': 'Hario V60 02'},
        },
      });
      expect(v60.brewer, 'V60');
      expect(
        () => brewRecipeFromMeticulous({..._machineProfile, 'brew_type': 'x'}),
        throwsA(isA<BrewRecipeFormatException>()),
      );
    });

    test('loads from /api/v1/pour-over/profile/list', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/pour-over/profile/list');
        return http.Response(
          jsonEncode({
            'profiles': [
              _machineProfile,
              {'brew_type': 'pour_over'}, // unreadable → skipped
            ],
          }),
          200,
        );
      });
      final source = MeticulousPourOverProfiles(
        host: () => 'machine.local',
        client: client,
      );
      final list = await source.fetch();
      expect(list.map((r) => r.name), ['One and Done']);
    });

    test('store uses the machine list only with the Meticulous', () async {
      final store = _store([_github]);
      await store.load();
      store.setEnabled('two-pours', true);
      store.machineSource = MeticulousPourOverProfiles(
        host: () => 'machine.local',
        client: MockClient(
          (req) async => req.url.path.contains('/image/')
              ? http.Response('', 404)
              : http.Response(
                  jsonEncode({
                    'profiles': [_machineProfile],
                  }),
                  200,
                ),
        ),
      );
      expect(store.enabledRecipes.map((r) => r.id), ['two-pours']);
      store.setUseMachine(true);
      await store.refreshMachine();
      expect(store.enabledRecipes.map((r) => r.name), ['One and Done']);
      expect(store.byId('two-pours'), isNull);
      expect(store.checkedRecipes.map((r) => r.id), ['two-pours']);
      store.setUseMachine(false);
      expect(store.enabledRecipes.map((r) => r.id), ['two-pours']);
    });
  });

  group('MeticulousScale', () {
    test('weight from every status, connected once data arrives', () async {
      final socket = _FakeSocket();
      final scale = MeticulousScale(socket, minReadingGap: Duration.zero);
      expect(scale.isConnected, isFalse);
      expect(scale.isMachineScale, isTrue);
      final got = <double>[];
      scale.readings.listen((r) => got.add(r.grams));
      socket.send(-136.47);
      socket.send(-136.5);
      // A sensors event (same status object) is not a new weight.
      socket.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(scale.isConnected, isTrue);
      expect(got, [-136.47, -136.5]);
      expect(scale.grams, -136.5);
    });

    test('tare via the machine, confirmed by the weight', () async {
      final socket = _FakeSocket()..send(-136.5);
      final scale = MeticulousScale(socket);
      await scale.tare();
      expect(socket.actions, ['tare']);
      expect(scale.grams, 0);
      socket.send(-136.5 + 312.4);
      expect(scale.grams, closeTo(312.4, 1e-9));
    });

    test('machine does not confirm → tares in the app', () async {
      final socket = _FakeSocket()
        ..tares = false
        ..send(-136.5);
      final scale = MeticulousScale(
        socket,
        tareTimeout: const Duration(milliseconds: 30),
      );
      await scale.tare();
      expect(scale.grams, 0);
      socket.send(-100.5);
      expect(scale.grams, closeTo(36, 1e-9));
    });

    test('no tare while an espresso session runs', () async {
      final socket = _FakeSocket()..send(3, state: 'brewing', name: 'heating');
      final scale = MeticulousScale(socket);
      expect(scale.tare, throwsStateError);
      expect(socket.actions, isEmpty);
    });
  });

  group('ScaleSelector', () {
    test('forwards the chosen scale and remembers the choice', () async {
      final socket = _FakeSocket();
      final bt = SimulatedScale();
      final selector = ScaleSelector(
        bluetooth: bt,
        meticulous: MeticulousScale(socket, minReadingGap: Duration.zero),
      );
      final got = <double>[];
      selector.readings.listen((r) => got.add(r.grams));
      expect(selector.isMachineScale, isFalse);
      socket.send(5); // not the chosen scale
      selector.setSource(ScaleSource.meticulous);
      expect(selector.isMachineScale, isTrue);
      expect(selector.deviceName, 'Meticulous');
      socket.send(7);
      await Future<void>.delayed(Duration.zero);
      expect(got, [7]);

      final next = ScaleSelector(
        bluetooth: SimulatedScale(),
        meticulous: MeticulousScale(_FakeSocket()),
      );
      await Future<void>.delayed(Duration.zero);
      await next.load();
      expect(next.source, ScaleSource.meticulous);
    });
  });

  group('Setup steps', () {
    late StreamController<ScaleReading> readings;
    late _Steady steady;
    late PourOverSetup prep;
    late int tares;

    setUp(() {
      readings = StreamController<ScaleReading>.broadcast(sync: true);
      steady = _Steady(readings);
      tares = 0;
      prep = PourOverSetup(tare: () async => tares++, targetDose: () => 15);
      readings.stream.listen(prep.feed);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('server → brewer → coffee, each records itself and tares', () async {
      // Last brew still on the scale, then taken off: the lowest steady
      // value is the baseline.
      steady.hold(-120);
      steady.hold(-450);
      expect(prep.step, SetupStep.server);
      steady.hold(-450 + 312.4); // empty server
      await settle();
      expect(prep.serverG, closeTo(312.4, 1e-9));
      expect(prep.step, SetupStep.brewer);
      expect(tares, 1);

      steady.hold(0);
      steady.hold(18.2);
      await settle();
      expect(prep.brewerG, 18.2);
      expect(prep.step, SetupStep.coffee);

      steady.hold(0);
      steady.hold(8); // still filling — below 80 % of the dose
      expect(prep.step, SetupStep.coffee);
      steady.hold(15.1);
      await settle();
      expect(prep.coffeeG, 15.1);
      expect(prep.done, isTrue);
      expect(tares, 3);
    });

    test(
      'server taken off again in the brewer step: back to the server',
      () async {
        steady.hold(0);
        steady.hold(300);
        await settle();
        expect(prep.step, SetupStep.brewer);
        // The scale was tared with the server on; now it is off again.
        steady.hold(-300);
        await settle();
        expect(prep.step, SetupStep.server);
        expect(prep.serverG, isNull);
        expect(tares, 2);
        // After that tare the scale reads 0 — a new server counts from there.
        steady.hold(0);
        steady.hold(280);
        await settle();
        expect(prep.serverG, 280);
        expect(prep.step, SetupStep.brewer);
      },
    );

    test('unsteady weight does not count', () async {
      steady.hold(0);
      for (var i = 0; i < 20; i++) {
        steady.hold(i.isEven ? 30 : 300, seconds: 0.2);
      }
      await settle();
      expect(prep.step, SetupStep.server);
      expect(tares, 0);
    });

    test('Tare confirms a step with nothing added (built-in brewer)', () async {
      prep.restart();
      steady.hold(0);
      steady.hold(300);
      await settle();
      steady.hold(0);
      await prep.confirm();
      expect(prep.brewerG, 0);
      expect(prep.step, SetupStep.coffee);
    });

    test('failed tare waits for Tare', () async {
      final failing = PourOverSetup(tare: () async => throw StateError('x'));
      await failing.confirm();
      expect(failing.status, SetupStatus.tareFailed);
      expect(failing.step, SetupStep.server);
    });
  });

  group('Dial tares', () {
    test('a jump to exactly 0.00 that stays flat is a dial tare', () async {
      final socket = _FakeSocket()..send(87.53);
      final scale = MeticulousScale(socket, minReadingGap: Duration.zero);
      final tares = <double>[];
      scale.deviceTares.listen(tares.add);
      socket.send(87.53);
      socket.dialTare();
      for (var i = 0; i < 4; i++) {
        socket.send(87.53);
      }
      await Future<void>.delayed(Duration.zero);
      expect(tares, [87.53]);
      expect(scale.grams, 0);
    });

    test('lifting through zero is no tare', () async {
      final socket = _FakeSocket();
      final scale = MeticulousScale(socket, minReadingGap: Duration.zero);
      final tares = <double>[];
      scale.deviceTares.listen(tares.add);
      for (final w in [87.6, 112.77, 92.11, 36.83, 0.55, 0.27, -12.0, -23.6]) {
        socket.send(w);
      }
      for (var i = 0; i < 5; i++) {
        socket.send(-23.58);
      }
      await Future<void>.delayed(Duration.zero);
      expect(tares, isEmpty);
    });

    test('the app\'s own tare is no dial tare', () async {
      final socket = _FakeSocket()..send(40);
      final scale = MeticulousScale(socket, minReadingGap: Duration.zero);
      final tares = <double>[];
      scale.deviceTares.listen(tares.add);
      await scale.tare();
      for (var i = 0; i < 4; i++) {
        socket.send(40);
      }
      await Future<void>.delayed(Duration.zero);
      expect(tares, isEmpty);
    });

    test('real capture: finds exactly the two dial tares', () async {
      final fixture = jsonDecode(
        File('test/fixtures/meticulous_dial_pourover.json').readAsStringSync(),
      ) as Map;
      final socket = _FakeSocket();
      final start = DateTime(2026, 11, 3, 23, 13, 23);
      var now = start;
      final tares = <(int, double)>[];
      await withClock(Clock(() => now), () async {
        final scale = MeticulousScale(socket);
        scale.deviceTares.listen(
          (g) => tares.add((now.difference(start).inMilliseconds, g)),
        );
        for (final sample in fixture['samples'] as List) {
          now = start.add(Duration(milliseconds: sample[0] as int));
          socket.send((sample[1] as num).toDouble());
        }
        await Future<void>.delayed(Duration.zero);
      });
      expect(tares.map((t) => t.$2), [87.53, 30.64]);
    });
  });

  group('Dial brews', () {
    test('parse the machine\'s brew', () {
      final b = DialBrew.fromJson(
        jsonDecode(
          File('test/fixtures/meticulous_dial_brew.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      expect(b.profileName, 'Manhattan Pour Over');
      expect(b.temperatureC, 99);
      expect(b.doseG, 15);
      expect(b.waterG, 253.1);
      expect(b.beverageG, 199.2);
      expect(b.brewerG, 115.5);
      expect(b.durationMs, 223483);
      expect(b.pours.map((p) => p.number), [1, 2, 3]);
      expect(b.stageAt(10000), 'Pour 1');
      expect(b.stageAt(30000), '');
      expect(b.samples, isNotEmpty);
      expect(b.externalId, startsWith('meticulous-pourover:'));
    });

    test('detector: water after a dial tare starts, setting things down '
        'and coffee do not, a lift ends', () {
      final d = DialBrewDetector();
      var t = DateTime(2026, 11, 4, 8);
      ScaleReading at(double g) {
        t = t.add(const Duration(milliseconds: 100));
        return ScaleReading(g, t);
      }

      // Not armed yet: nothing starts.
      expect(d.feedIdle(at(50)), isNull);
      d.deviceTared();
      // Brewer set down (jump), coffee spooned in (< 40 g), next tare.
      expect(d.feedIdle(at(0)), isNull);
      expect(d.feedIdle(at(115)), isNull);
      for (var g = 115.0; g < 130; g += 1) {
        expect(d.feedIdle(at(g)), isNull);
      }
      d.deviceTared();
      // Water at ~8 g/s.
      List<ScaleReading>? rise;
      for (var g = 0.0; rise == null && g < 100; g += 0.8) {
        rise = d.feedIdle(at(g));
      }
      expect(rise, isNotNull);
      expect(rise!.first.grams, lessThan(2));
      expect(d.running, isTrue);
      // Keeps pouring to 250, then the brewer comes off.
      for (var g = 40.0; g < 250; g += 0.8) {
        expect(d.feedRunning(at(g)), isNull);
      }
      DateTime? lift;
      final liftStart = t;
      for (var i = 0; lift == null && i < 40; i++) {
        lift = d.feedRunning(at(120));
      }
      expect(lift, isNotNull);
      expect(lift!.difference(liftStart).inMilliseconds, lessThan(200));
    });

    test('detector on the real capture: starts with the water poured after '
        'the brewer tare', () async {
      final fixture = jsonDecode(
        File('test/fixtures/meticulous_dial_pourover.json').readAsStringSync(),
      ) as Map;
      final socket = _FakeSocket();
      final start = DateTime(2026, 11, 3, 23, 13, 23);
      var now = start;
      int? startedMs;
      await withClock(Clock(() => now), () async {
        final scale = MeticulousScale(socket);
        final d = DialBrewDetector();
        scale.deviceTares.listen((_) => d.deviceTared());
        scale.readings.listen((r) {
          final rise = d.feedIdle(r);
          if (rise != null) {
            startedMs ??= rise.first.at.difference(start).inMilliseconds;
          }
        });
        for (final sample in fixture['samples'] as List) {
          now = start.add(Duration(milliseconds: sample[0] as int));
          socket.send((sample[1] as num).toDouble());
          await Future<void>.delayed(Duration.zero);
        }
      });
      // Water from 101.6 s (after the brewer tare at 96.7 s).
      expect(startedMs, isNotNull);
      expect(startedMs! / 1000, closeTo(101.6, 0.5));
    });
  });

  group('Brew service with the Meticulous', () {
    late AppDatabase db;
    late _FakeSocket socket;
    late ScaleSelector selector;
    late BrewRecipeStore store;
    late PourOverBrewService service;
    late Map<String, dynamic> dialBrew;
    var now = DateTime(2026, 11, 4, 7, 34);
    var brewOnMachine = false;

    Future<void> setUpService(MeticulousPourMode mode) async {
      SharedPreferences.setMockInitialValues({
        PourOverBrewService.meticulousModePrefKey: mode.name,
        PourOverBrewService.autoPrefKey: true,
      });
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      socket = _FakeSocket()..send(-136.5);
      selector = ScaleSelector(
        bluetooth: SimulatedScale(),
        meticulous: MeticulousScale(socket),
      );
      store = _store([_github]);
      await store.load();
      store.setEnabled('two-pours', true);
      dialBrew = jsonDecode(
        File('test/fixtures/meticulous_dial_brew.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/pour-over/profile/list')) {
          return http.Response(
            jsonEncode({
              'profiles': [_machineProfile],
            }),
            200,
          );
        }
        if (path.endsWith('/history/pour-over/last')) {
          return brewOnMachine
              ? http.Response(
                  jsonEncode({'id': dialBrew['id'], 'file': 'x.json.zst'}),
                  200,
                )
              : http.Response('{}', 404);
        }
        if (path.contains('/history/pour-over/files/')) {
          return http.Response(jsonEncode(dialBrew), 200);
        }
        return http.Response('', 404);
      });
      store.machineSource = MeticulousPourOverProfiles(
        host: () => 'machine.local',
        client: client,
      );
      service =
          PourOverBrewService(
              scale: selector,
              recipes: store,
              setup: ShotSetup.inMemory(machineKey: 'pourover'),
              database: db,
            )
            ..dialBrews = MeticulousDialBrews(
              host: () => 'm.local',
              client: client,
            )
            ..dialPollEvery = const Duration(milliseconds: 20);
      service.start();
      selector.setSource(ScaleSource.meticulous);
      await store.refreshMachine();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.setPrepVisible(true);
    }

    var gross = -136.5;
    Future<void> hold(int ticks) async {
      for (var i = 0; i < ticks; i++) {
        now = now.add(const Duration(milliseconds: 100));
        socket.send(gross);
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('Machine: follows the dial live, then takes the machine\'s brew '
        'combined with Pre Brew', () async {
      await withClock(Clock(() => now), () async {
        brewOnMachine = false;
        gross = -136.5;
        await setUpService(MeticulousPourMode.machine);
        expect(service.dialLeads, isTrue);
        expect(service.prepActive, isFalse);
        service.setup.setBean(7);
        service.setup.setGrind(24);

        // Server, brewer, coffee — each tared on the dial.
        for (final load in [300.0, 115.5, 15.0]) {
          gross += load;
          await hold(10);
          socket.dialTare();
          await hold(5);
        }
        expect(service.stage, ShotStage.idle);
        expect(socket.actions, isEmpty);

        // Water: the brew shows up in the app by itself.
        for (var i = 0; i < 60; i++) {
          gross += 0.8;
          await hold(1);
        }
        expect(service.stage, ShotStage.running);
        expect(service.grams, greaterThan(40));
        expect(service.elapsedMs, greaterThan(5000));

        // Brewer off → waiting for the machine.
        gross -= 200;
        await hold(35);
        expect(service.waitingForMachine, isTrue);

        // The dial finishes and saves its brew.
        brewOnMachine = true;
        dialBrew['startedAt'] = now.toUtc().toIso8601String();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await service.importLastDialBrew(); // no-op while running
        // The poll timer runs on real time — call it like the timer would.
        for (var i = 0; i < 20 && service.stage == ShotStage.running; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(service.stage, isNot(ShotStage.running));
        final shot = (await db.select(db.shots).get()).single;
        expect(shot.profileName, 'Manhattan Pour Over');
        expect(shot.profileTemp, 99);
        expect(shot.finalWeight, 253.1);
        expect(shot.beverageGrams, 199.2);
        expect(shot.doseGrams, 15);
        expect(shot.durationMs, 223483);
        expect(shot.beanId, 7);
        expect(shot.grindSize, isNotNull);
        expect(socket.actions, isEmpty);
        service.dispose();
      });
    });

    test(
      'Machine: a dial brew made while the app was away is taken once',
      () async {
        await withClock(Clock(() => now), () async {
          brewOnMachine = true;
          gross = -136.5;
          await setUpService(MeticulousPourMode.machine);
          // Taken when the view opened.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(await service.importLastDialBrew(), isFalse);
          expect((await db.select(db.shots).get()).length, 1);
          expect(await service.importLastDialBrew(), isFalse);
          expect((await db.select(db.shots).get()).length, 1);
          service.dispose();
        });
      },
    );

    test('Scale only: app steps tare by themselves, brew starts with the '
        'water, ends at the lift and weighs the coffee', () async {
      await withClock(Clock(() => now), () async {
        brewOnMachine = false;
        gross = -136.5;
        await setUpService(MeticulousPourMode.scaleOnly);
        expect(service.dialLeads, isFalse);
        expect(service.prepActive, isTrue);
        // Machine profiles first, checked recipes after them.
        expect(store.enabledRecipes.map((r) => r.id), [
          _machineProfile['id'],
          'two-pours',
        ]);

        await hold(12);
        gross += 300;
        await hold(15);
        expect(service.prep.step, SetupStep.brewer);
        expect(socket.actions, ['tare']);
        gross += 30.6;
        await hold(15);
        gross += 15.2;
        await hold(15);
        expect(service.prep.done, isTrue);
        expect(service.setup.doseGrams, 15.2);
        expect(socket.actions.length, 3);

        gross += 3;
        await hold(1);
        await Future<void>.delayed(Duration.zero);
        expect(service.stage, ShotStage.running);
        for (var poured = 3.0; poured < 225; poured += 7.5) {
          gross += 7.5;
          await hold(1);
        }
        await hold(20);
        final water = service.grams;
        gross -= 30.6 + 15.2 + 40;
        await hold(35);
        expect(service.phase, BrewState.measuring);
        gross = -136.5 + 300 + 185;
        // (zero sits on server + brewer + coffee after the app's tares)
        gross += 0;
        await hold(12);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final shot = (await db.select(db.shots).get()).single;
        expect(shot.finalWeight, closeTo(water, 1e-9));
        expect(shot.beverageGrams, isNotNull);
        service.dispose();
      });
    });
  });

  test('Bluetooth scale with Auto: same steps, start and end as on the '
      'Meticulous', () async {
    SharedPreferences.setMockInitialValues({
      PourOverBrewService.autoPrefKey: true,
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2026, 11, 4, 9);
    await withClock(Clock(() => now), () async {
      final scale = _BtScale();
      final store = _store([_github]);
      await store.load();
      store.setEnabled('two-pours', true);
      final service = PourOverBrewService(
        scale: scale,
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
      service.selectRecipe(_github);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.setPrepVisible(true);
      expect(service.auto, isTrue);
      expect(service.prepActive, isTrue);

      Future<void> hold(int ticks) async {
        for (var i = 0; i < ticks; i++) {
          now = now.add(const Duration(milliseconds: 100));
          scale.tick();
        }
        await Future<void>.delayed(Duration.zero);
      }

      await hold(12);
      scale.gross += 300;
      await hold(15);
      scale.gross += 30;
      await hold(15);
      scale.gross += 16;
      await hold(15);
      expect(service.prep.done, isTrue);
      expect(service.setup.doseGrams, 16);
      expect(scale.tares, 3);

      scale.gross += 3;
      await hold(1);
      await Future<void>.delayed(Duration.zero);
      expect(service.stage, ShotStage.running);
      for (var w = 3.0; w < 250; w += 7.5) {
        scale.gross += 7.5;
        await hold(1);
      }
      await hold(20);
      scale.gross -= 30 + 16 + 45;
      await hold(35);
      expect(service.phase, BrewState.measuring);
      await hold(12);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final shot = (await db.select(db.shots).get()).single;
      expect(shot.doseGrams, 16);
      expect(shot.beverageGrams, closeTo(250.5 - 45, 0.5));
      service.dispose();
    });
  });

  group('Brewer by weight', () {
    Gear brewer(String id, String model, double? weight) => Gear(
      id: id,
      type: GearType.brewer,
      model: model,
      brewModes: const {BrewMode.pourOver},
      specs: {'weight': ?weight},
    );

    test('finds the closest brewer within 3 g / 3 %', () {
      final store = GearStore.inMemory(
        gear: [
          brewer('v60', 'V60 02', 30.6),
          brewer('april', 'April', 115.5),
          brewer('none', 'Kalita', null),
        ],
      );
      expect(store.brewerByWeight(31.9)?.id, 'v60');
      expect(store.brewerByWeight(118.4)?.id, 'april'); // 3 % of 115.5
      expect(store.brewerByWeight(50), isNull);
    });

    test('two brewers that weigh the same: no guess', () {
      final store = GearStore.inMemory(
        gear: [brewer('a', 'A', 30), brewer('b', 'B', 30)],
      );
      expect(store.brewerByWeight(30.2), isNull);
    });

    test('Auto picks the chain the recognised brewer is in', () async {
      SharedPreferences.setMockInitialValues({
        PourOverBrewService.autoPrefKey: true,
      });
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime(2026, 11, 4, 10);
      await withClock(Clock(() => now), () async {
        final gear = GearStore.inMemory(
          gear: [
            brewer('v60', 'V60 02', 30.6),
            brewer('april', 'April', 115.5),
          ],
          chains: const [
            BrewChain(id: 'c-v60', name: 'V60', gearIds: ['v60']),
            BrewChain(id: 'c-april', name: 'April', gearIds: ['april']),
          ],
        );
        final setup = ShotSetup.inMemory(machineKey: 'pourover')
          ..gear = gear
          ..setChain('c-v60');
        final scale = _BtScale();
        final store = _store([_github]);
        await store.load();
        final service = PourOverBrewService(
          scale: scale,
          recipes: store,
          setup: setup,
          database: db,
        )..start();
        service.selectRecipe(_github);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        service.setPrepVisible(true);

        Future<void> hold(int ticks) async {
          for (var i = 0; i < ticks; i++) {
            now = now.add(const Duration(milliseconds: 100));
            scale.tick();
          }
          await Future<void>.delayed(Duration.zero);
        }

        await hold(12);
        scale.gross += 300;
        await hold(15);
        scale.gross += 116; // the April with a wet filter
        await hold(15);
        expect(service.detectedBrewer?.id, 'april');
        expect(setup.chain?.id, 'c-april');
        expect(service.prep.step, SetupStep.coffee);
        final taresBefore = scale.tares;

        // Another brewer after all: the April comes off again (the scale
        // falls by its weight below zero) → tare, back to the brewer step.
        scale.gross -= 116;
        await hold(15);
        expect(service.prep.step, SetupStep.brewer);
        expect(service.prep.brewerG, isNull);
        expect(service.detectedBrewer, isNull);
        expect(scale.tares, taresBefore + 1);
        expect(scale.grams, 0);

        scale.gross += 30.8; // the V60
        await hold(15);
        expect(service.detectedBrewer?.id, 'v60');
        expect(setup.chain?.id, 'c-v60');
        expect(service.prep.step, SetupStep.coffee);
        service.dispose();
      });
    });
  });
}

/// Bluetooth-like scale the test drives tick by tick; tare zeroes it.
class _BtScale extends BrewScale {
  final _ctrl = StreamController<ScaleReading>.broadcast(sync: true);
  double gross = 0;
  double _zero = 0;
  int tares = 0;

  @override
  ScaleConnection get connection => ScaleConnection.connected;
  @override
  String? get deviceName => 'LUNAR-TEST';
  @override
  double? get grams => gross - _zero;
  @override
  String? get error => null;
  @override
  Stream<ScaleReading> get readings => _ctrl.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> tare() async {
    tares++;
    _zero = gross;
  }

  void tick() {
    _ctrl.add(ScaleReading(gross - _zero, clock.now()));
    notifyListeners();
  }
}

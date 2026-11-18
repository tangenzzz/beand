import 'dart:async';

import 'package:beand/database/database.dart';
import 'package:beand/screens/live/espresso/espresso_home.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/sensors/pressure_sensor.dart';
import 'package:beand/services/espresso_shot_service.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scale extends BrewScale {
  _Scale({this.connected = true});
  bool connected;
  int tares = 0;
  @override
  ScaleConnection get connection =>
      connected ? ScaleConnection.connected : ScaleConnection.disconnected;
  @override
  String? get deviceName => 'TEST';
  @override
  double? grams;
  @override
  String? get error => null;
  @override
  Stream<ScaleReading> get readings => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> tare() async {
    tares++;
    grams = 0;
  }
}

class _Sensor extends PressureSensor {
  _Sensor({this.connected = false});
  bool connected;
  @override
  ScaleConnection get connection =>
      connected ? ScaleConnection.connected : ScaleConnection.disconnected;
  @override
  String? get deviceName => 'PRS-TEST';
  @override
  double? bar;
  @override
  String? get error => null;
  @override
  Stream<PressureReading> get readings => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  EspressoShotService service(_Scale scale, _Sensor sensor) =>
      EspressoShotService(
        scale: scale,
        sensor: sensor,
        setup: ShotSetup.inMemory(
          machineKey: EspressoShotService.key,
          doseGrams: 18,
        ),
        database: db,
      )..start();

  test('Pressensor packets: big-endian millibar, signed', () {
    expect(Pressensor.parse([0x23, 0x28]), 9.0); // 9000 mbar
    expect(Pressensor.parse([0xFF, 0x9C]), -0.1); // -100 mbar
    expect(Pressensor.parse([0x01]), isNull);
    expect(Pressensor.matches('PRS-1234'), isTrue);
    expect(Pressensor.matches('LUNAR-1'), isFalse);
  });

  test('a shot with scale and sensor records both and saves', () async {
    final scale = _Scale();
    final sensor = _Sensor(connected: true);
    final shot = service(scale, sensor);
    expect(shot.startsByHand, isTrue);
    expect(shot.setup.profileName, EspressoShotService.profileName);

    await shot.startShot();
    expect(scale.tares, 1);
    expect(shot.stage, ShotStage.running);
    expect(shot.activeCard, ActiveCard.live);

    // Let the sampler run a few seconds with values coming in.
    for (var i = 1; i <= 15; i++) {
      scale.grams = i * 2.4;
      sensor.bar = 9;
      await Future<void>.delayed(EspressoShotService.sampleEvery);
    }
    expect(shot.liveReadings.last.pressure, 9);
    expect(shot.liveReadings.last.weight, closeTo(36, 0.01));

    await shot.stopShot();
    expect(shot.activeCard, ActiveCard.post);

    final saved = await db.lastShot(machine: EspressoShotService.key);
    expect(saved, isNotNull);
    expect(saved!.finalWeight, closeTo(36, 0.01));
    expect(saved.doseGrams, 18);
    expect(saved.profileName, EspressoShotService.profileName);
    expect(saved.durationMs, greaterThan(2000));

    shot.confirmPostShot();
    expect(shot.stage, ShotStage.idle);
    expect(shot.activeCard, ActiveCard.pre);
    shot.dispose();
  });

  test('without any device only the time is saved, no curve', () async {
    final shot = service(_Scale(connected: false), _Sensor());
    await shot.startShot();
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(shot.liveReadings, isNotEmpty);
    expect(shot.liveReadings.every((r) => r.weight == null), isTrue);
    await shot.stopShot();

    final saved = await db.lastShot(machine: EspressoShotService.key);
    expect(saved!.finalWeight, isNull);
    expect(saved.durationMs, greaterThanOrEqualTo(2000));
    expect(await db.readingsFor(saved.id), isEmpty);
    shot.dispose();
  });

  test('a mis-tap under two seconds saves nothing', () async {
    final shot = service(_Scale(), _Sensor());
    await shot.startShot();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await shot.stopShot();
    expect(shot.stage, ShotStage.idle);
    expect(shot.activeCard, ActiveCard.pre);
    expect(await db.lastShot(machine: EspressoShotService.key), isNull);
    shot.dispose();
  });

  group('home', () => homeTests(() => db));
}

// ---- Home view ----

Widget _wrapHome(AppDatabase db, EspressoShotService shot, _Sensor sensor) =>
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<GearStore>.value(value: GearStore.inMemory()),
        ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
        ChangeNotifierProvider<AiSettings>.value(
          value: AiSettings(keyStore: InMemoryAiKeyStore()),
        ),
        ChangeNotifierProvider<EspressoShotService>.value(value: shot),
        ChangeNotifierProvider<PressureSensor>.value(value: sensor),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(child: EspressoHome()),
        ),
      ),
    );

// Runs inside main(): its setUp gives the database.
void homeTests(AppDatabase Function() database) {
  testWidgets('Espresso home: no profile row, Start Shot, three buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = database();
    final sensor = _Sensor();
    final shot = EspressoShotService(
      scale: _Scale(),
      sensor: sensor,
      setup: ShotSetup.inMemory(machineKey: EspressoShotService.key),
      database: db,
    )..start();
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrapHome(db, shot, sensor));
      await tester.pump();
      await tester.pump();
      expect(find.text('Profile'), findsNothing);
      expect(find.text('Bean'), findsOneWidget);
      expect(find.text('Start Shot'), findsOneWidget);
      expect(find.text('Tare'), findsOneWidget);
      expect(find.text('Sensor'), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
      // The Pre card fits without scrolling.
      final pre = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(PreShotCard),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(pre.position.maxScrollExtent, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
    shot.dispose();
  });
}

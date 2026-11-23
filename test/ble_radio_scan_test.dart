import 'dart:async';
import 'dart:typed_data';

import 'package:beand/scale/ble_scale.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/sensors/pressure_sensor.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One radio like the plugin's: a second scanForDevices ends the first.
/// Connections never answer.
class _Radio implements FlutterReactiveBle {
  var scansStarted = 0;
  var scansStopped = 0;
  StreamController<DiscoveredDevice>? _scan;
  final connectedTo = <String>[];

  @override
  Stream<BleStatus> get statusStream => Stream.value(BleStatus.ready);

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) {
    // The plugin's behaviour: the running scan goes quiet.
    unawaited(_scan?.close());
    scansStarted++;
    final c = _scan = StreamController<DiscoveredDevice>(
      onCancel: () => scansStopped++,
    );
    return c.stream;
  }

  void see(String id, String name) => _scan!.add(
    DiscoveredDevice(
      id: id,
      name: name,
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: -50,
      serviceUuids: const [],
    ),
  );

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    connectedTo.add(id);
    return StreamController<ConnectionStateUpdate>().stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'scale and pressure sensor search together in one radio scan '
    '(2026-11-23: the sensor\'s scan used to cut the scale\'s short)',
    () async {
      final radio = _Radio();
      final scale = BleScale(ble: radio);
      final sensor = Pressensor(ble: radio);
      await _tick();

      final scales = <String>[];
      final sensors = <String>[];
      final subScale = scale.scan().listen((c) => scales.add(c.id));
      await _tick();
      final subSensor = sensor.scan().listen((c) => sensors.add(c.id));
      await _tick();
      expect(radio.scansStarted, 1);

      radio
        ..see('acaia', 'PROCHBT001')
        ..see('prs', 'PRS-1234');
      await _tick();
      // Each keeps only its own kind.
      expect(scales, ['acaia']);
      expect(sensors, ['prs']);

      await subSensor.cancel();
      await _tick();
      expect(radio.scansStopped, 0);
      await subScale.cancel();
      await _tick();
      expect(radio.scansStopped, 1);
    },
  );

  test(
    'the sensor connecting finds itself in the scale\'s running scan',
    () async {
      final radio = _Radio();
      final scale = BleScale(ble: radio);
      final sensor = Pressensor(ble: radio);
      await _tick();
      final sub = scale.scan().listen((_) {});
      await _tick();

      unawaited(sensor.connect());
      await _tick();
      expect(radio.scansStarted, 1);
      radio.see('prs', 'PRS-1234');
      await _tick();
      expect(radio.connectedTo, ['prs']);
      expect(sensor.rememberedId, 'prs');
      expect(sensor.knownSensors.map((k) => k.id), ['prs']);

      await sensor.disconnect();
      await sub.cancel();
    },
  );

  test('known sensors: pick one, none, rename, forget', () async {
    final radio = _Radio();
    final sensor = Pressensor(ble: radio);
    await _tick();
    unawaited(
      sensor.connectTo(const ScaleCandidate(id: 'a', name: 'PRS-A', rssi: -50)),
    );
    await _tick();
    unawaited(
      sensor.connectTo(const ScaleCandidate(id: 'b', name: 'PRS-B', rssi: -50)),
    );
    await _tick();
    expect(sensor.knownSensors.map((k) => k.id), ['a', 'b']);
    expect(sensor.rememberedId, 'b');

    await sensor.select('a');
    expect(sensor.rememberedId, 'a');
    expect(sensor.connection, ScaleConnection.disconnected);

    // None: nothing in use, the known ones stay.
    await sensor.select(null);
    expect(sensor.rememberedId, isNull);
    expect(sensor.knownSensors, hasLength(2));

    await sensor.renameSensor('b', 'Group head');
    await sensor.select('b');
    expect(sensor.displayName, 'Group head');

    // Survives a restart.
    final again = Pressensor(ble: _Radio());
    await _tick();
    expect(again.rememberedId, 'b');
    expect(again.knownSensors.map((k) => k.displayName), [
      'PRS-A',
      'Group head',
    ]);

    await sensor.forgetSensor('b');
    expect(sensor.rememberedId, isNull);
    expect(sensor.knownSensors.map((k) => k.id), ['a']);
  });
}

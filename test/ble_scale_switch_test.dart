import 'dart:async';
import 'dart:typed_data';

import 'package:beand/scale/ble_scale.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE stack whose connections never answer — like a scale that is busy
/// or switched off mid-way.
class _SilentBle implements FlutterReactiveBle {
  final connectedTo = <String>[];
  final cancelled = <String>[];

  @override
  Stream<BleStatus> get statusStream => Stream.value(BleStatus.ready);

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    connectedTo.add(id);
    late StreamController<ConnectionStateUpdate> c;
    c = StreamController<ConnectionStateUpdate>(
      onCancel: () => cancelled.add(id),
    );
    return c.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  scanAndKnownTests();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'switching to another scale while one hangs connects the new one '
    '(bug 2026-11-04: after the Decent nothing connected any more)',
    () async {
      final ble = _SilentBle();
      final scale = BleScale(ble: ble);
      const decent = ScaleCandidate(
        id: 'decent',
        name: 'Decent Scale',
        rssi: -50,
      );
      const acaia = ScaleCandidate(id: 'acaia', name: 'PROCHBT001', rssi: -50);

      // The Decent never finishes connecting.
      unawaited(scale.connectTo(decent));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ble.connectedTo, ['decent']);
      expect(scale.connection, ScaleConnection.connecting);

      // Tapping the Acaia drops the Decent and really asks for the Acaia.
      unawaited(scale.connectTo(acaia));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ble.cancelled, contains('decent'));
      expect(ble.connectedTo, ['decent', 'acaia']);
      expect(scale.deviceName, 'PROCHBT001');

      // Disconnect, then the Acaia again: still not stuck.
      await scale.disconnect();
      expect(scale.connection, ScaleConnection.disconnected);
      unawaited(scale.connectTo(acaia));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ble.connectedTo, ['decent', 'acaia', 'acaia']);
      await scale.disconnect();
    },
  );
}

/// BLE stack with a scan the test controls, and connections that never answer.
class _ScanBle extends _SilentBle {
  var scansStarted = 0;
  var scansStopped = 0;
  StreamController<DiscoveredDevice>? radio;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) {
    scansStarted++;
    radio = StreamController<DiscoveredDevice>(onCancel: () => scansStopped++);
    return radio!.stream;
  }

  void see(String id, String name) => radio!.add(
    DiscoveredDevice(
      id: id,
      name: name,
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: -50,
      serviceUuids: const [],
    ),
  );
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void scanAndKnownTests() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a search left running does not end the scale tapped after it',
    () async {
      final ble = _ScanBle();
      final scale = BleScale(ble: ble);
      await _tick();
      unawaited(scale.connect());
      await _tick();
      expect(scale.connection, ScaleConnection.scanning);

      const acaia = ScaleCandidate(id: 'acaia', name: 'PROCHBT001', rssi: -50);
      unawaited(scale.connectTo(acaia));
      await _tick();
      expect(ble.connectedTo, ['acaia']);
      expect(scale.connection, ScaleConnection.connecting);
      expect(scale.error, isNull);
      await _tick();
      expect(ble.cancelled, isEmpty);
      await scale.disconnect();
    },
  );

  test('disconnect stops a search: nothing connects afterwards', () async {
    final ble = _ScanBle();
    final scale = BleScale(ble: ble);
    await _tick();
    unawaited(scale.connect());
    await _tick();
    await scale.disconnect();
    await _tick();
    expect(ble.scansStopped, 1);
    expect(scale.connection, ScaleConnection.disconnected);
    expect(scale.error, isNull);
    expect(ble.connectedTo, isEmpty);
  });

  test(
    'after a disconnect during a search, connecting works straight away',
    () async {
      final ble = _ScanBle();
      final scale = BleScale(ble: ble);
      await _tick();
      unawaited(scale.connect());
      await _tick();
      await scale.disconnect();
      unawaited(scale.connect());
      await _tick();
      expect(scale.connection, ScaleConnection.scanning);
      expect(ble.scansStarted, 2);
      await scale.disconnect();
    },
  );

  test('two scans share one radio scan, one ending leaves the other', () async {
    final ble = _ScanBle();
    final scale = BleScale(ble: ble);
    await _tick();
    final a = <String>[];
    final b = <String>[];
    final subA = scale.scan().listen((c) => a.add(c.id));
    await _tick();
    ble.see('acaia', 'PROCHBT001');
    await _tick();
    // The second one also hears what was already found.
    final subB = scale.scan().listen((c) => b.add(c.id));
    await _tick();
    expect(ble.scansStarted, 1);
    expect(a, ['acaia']);
    expect(b, ['acaia']);

    await subA.cancel();
    await _tick();
    expect(ble.scansStopped, 0);
    ble.see('decent', 'Decent Scale');
    await _tick();
    expect(b, ['acaia', 'decent']);

    await subB.cancel();
    await _tick();
    expect(ble.scansStopped, 1);
  });

  test('too many scan starts wait instead of being silently empty', () async {
    final ble = _ScanBle();
    final scale = BleScale(ble: ble);
    await _tick();
    for (var i = 0; i < 6; i++) {
      final sub = scale.scan().listen((_) {});
      await _tick();
      await sub.cancel();
      await _tick();
    }
    expect(ble.scansStarted, 4);
  });

  test('known scales: from older versions, kept, forgotten', () async {
    SharedPreferences.setMockInitialValues({
      scaleLastDeviceIdPrefKey: 'acaia',
      scaleLastDeviceNamePrefKey: 'PROCHBT001',
    });
    final scale = BleScale(ble: _ScanBle());
    await _tick();
    expect(scale.knownScales.map((k) => k.name), ['PROCHBT001']);

    await scale.forgetScale('acaia');
    expect(scale.knownScales, isEmpty);
    expect(scale.rememberedId, isNull);

    final again = BleScale(ble: _ScanBle());
    await _tick();
    expect(again.knownScales, isEmpty);
  });
}

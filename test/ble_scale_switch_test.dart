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
  final conns = <String, StreamController<ConnectionStateUpdate>>{};

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
    conns[id] = c;
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
      expect(ble.connectedTo, ['decent', 'acaia']);
      expect(scale.deviceName, 'PROCHBT001');

      // Disconnect, then the Acaia again: still not stuck.
      await scale.disconnect();
      expect(scale.connection, ScaleConnection.disconnected);
      unawaited(scale.connectTo(acaia));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Its first attempt ends, then the new one goes out.
      ble.conns['acaia']!.add(
        const ConnectionStateUpdate(
          deviceId: 'acaia',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
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

ConnectionStateUpdate _state(String id, DeviceConnectionState state) =>
    ConnectionStateUpdate(deviceId: id, connectionState: state, failure: null);

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

  test(
    'a new name stays, but the app still talks to the scale by its own',
    () async {
      SharedPreferences.setMockInitialValues({
        scaleLastDeviceIdPrefKey: 'acaia',
        scaleLastDeviceNamePrefKey: 'PROCHBT001',
      });
      final scale = BleScale(ble: _ScanBle());
      await _tick();
      expect(scale.shortName, 'Pearl');

      await scale.renameScale('acaia', '  Pearl upstairs ');
      expect(scale.displayName, 'Pearl upstairs');
      // As given, not shortened to the model.
      expect(scale.shortName, 'Pearl upstairs');
      expect(scale.deviceName, 'PROCHBT001');
      expect(scale.knownScales.single.name, 'PROCHBT001');

      final again = BleScale(ble: _ScanBle());
      await _tick();
      expect(again.displayName, 'Pearl upstairs');

      await again.renameScale('acaia', '   ');
      expect(again.displayName, 'PROCHBT001');
      expect(again.knownScales.single.customName, isNull);
    },
  );

  test(
    'an attempt that has not answered is left to run out, not cancelled '
    '(the plugin would keep it first in its queue and block every other scale)',
    () async {
      final ble = _ScanBle();
      final scale = BleScale(ble: ble);
      await _tick();
      const decent = ScaleCandidate(
        id: 'decent',
        name: 'Decent Scale',
        rssi: 0,
      );
      const acaia = ScaleCandidate(id: 'acaia', name: 'PROCHBT001', rssi: 0);
      unawaited(scale.connectTo(decent));
      await _tick();
      unawaited(scale.connectTo(acaia));
      await _tick();
      expect(ble.connectedTo, ['decent', 'acaia']);
      expect(ble.cancelled, isEmpty);

      // Its answer comes: now it may go.
      ble.conns['decent']!.add(
        const ConnectionStateUpdate(
          deviceId: 'decent',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
      await _tick();
      expect(ble.cancelled, ['decent']);
      expect(scale.deviceName, 'PROCHBT001');
      expect(scale.connection, ScaleConnection.connecting);
      await scale.disconnect();
    },
  );

  test('an attempt ended by a late "disconnected" is cleared before the next scale '
      '(log 2026-11-05: Decent off, Pearl never connected)', () async {
    final ble = _ScanBle();
    final scale = BleScale(ble: ble);
    await _tick();
    const decent = ScaleCandidate(id: 'decent', name: 'Decent Scale', rssi: 0);
    const pearl = ScaleCandidate(id: 'pearl', name: 'PROCHBT001', rssi: 0);
    unawaited(scale.connectTo(decent));
    await _tick();
    // The plugin's stream ends on it before the attempt said "connecting".
    ble.conns['decent']!.add(
      _state('decent', DeviceConnectionState.disconnected),
    );
    await ble.conns['decent']!.close();
    await _tick();

    unawaited(scale.connectTo(pearl));
    await _tick();
    // First a short attempt on the Decent, the Pearl waits for its answer.
    expect(ble.connectedTo.last, 'decent');
    expect(ble.connectedTo, isNot(contains('pearl')));
    ble.conns['decent']!
      ..add(_state('decent', DeviceConnectionState.connecting))
      ..add(_state('decent', DeviceConnectionState.disconnected));
    await _tick();
    expect(ble.connectedTo.last, 'pearl');
    await scale.disconnect();
  });

  test('the same scale again waits for its old attempt to end', () async {
    final ble = _ScanBle();
    final scale = BleScale(ble: ble);
    await _tick();
    const decent = ScaleCandidate(id: 'decent', name: 'Decent Scale', rssi: 0);
    unawaited(scale.connectTo(decent));
    await _tick();
    await scale.disconnect();
    unawaited(scale.connectTo(decent));
    await _tick();
    expect(ble.connectedTo, ['decent']);
    ble.conns['decent']!.add(
      const ConnectionStateUpdate(
        deviceId: 'decent',
        connectionState: DeviceConnectionState.disconnected,
        failure: null,
      ),
    );
    await _tick();
    expect(ble.connectedTo, ['decent', 'decent']);
    await scale.disconnect();
  });

  group('a lost scale', () {
    Future<(BleScale, _ScanBle)> lost() async {
      SharedPreferences.setMockInitialValues({
        scaleKnownPrefKey:
            '[{"id":"decent","name":"Decent Scale"},'
            '{"id":"acaia","name":"PROCHBT001"}]',
      });
      final ble = _ScanBle();
      final scale = BleScale(ble: ble)
        ..autoSwitchGrace = const Duration(milliseconds: 150)
        ..lostSettle = Duration.zero;
      await _tick();
      unawaited(
        scale.connectTo(
          const ScaleCandidate(id: 'decent', name: 'Decent Scale', rssi: 0),
        ),
      );
      await _tick();
      ble.conns['decent']!
        ..add(_state('decent', DeviceConnectionState.connecting))
        ..add(_state('decent', DeviceConnectionState.disconnected));
      await _tick();
      ble.connectedTo.clear();
      unawaited(scale.simulateLost());
      await _tick();
      return (scale, ble);
    }

    test('another known scale takes over when it stays away', () async {
      final (scale, ble) = await lost();
      expect(ble.connectedTo, isEmpty, reason: 'looks first, no blind attempt');
      ble.see('acaia', 'PROCHBT001');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ble.connectedTo, ['acaia']);
      expect(scale.rememberedId, 'acaia');
      expect(scale.deviceName, 'PROCHBT001');
      await scale.disconnect();
    });

    test('it wins when it comes back in time', () async {
      final (scale, ble) = await lost();
      ble.see('acaia', 'PROCHBT001');
      await _tick();
      ble.see('decent', 'Decent Scale');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ble.connectedTo, ['decent']);
      await scale.disconnect();
    });

    test('a scale never connected to is not taken', () async {
      final (scale, ble) = await lost();
      ble.see('new', 'BOOKOO_1');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ble.connectedTo, isEmpty);
      await scale.disconnect();
    });

    test('during a brew it only waits for its own scale', () async {
      final (scale, ble) = await lost();
      await scale.disconnect();
      scale.mayAutoSwitch = () => false;
      unawaited(
        scale.connectTo(
          const ScaleCandidate(id: 'decent', name: 'Decent Scale', rssi: 0),
        ),
      );
      await _tick();
      ble.conns['decent']!.add(
        const ConnectionStateUpdate(
          deviceId: 'decent',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(ble.connectedTo.toSet(), {'decent'});
      await scale.disconnect();
    });
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

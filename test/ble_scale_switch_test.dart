import 'dart:async';

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

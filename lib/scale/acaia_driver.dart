import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'acaia_protocol.dart';
import 'scale_driver.dart';

/// Acaia Lunar/Pearl/Pyxis (old and new firmware). Protocol details:
/// acaia_protocol.dart. The steps and their timing are those of the
/// AcaiaScale that was confirmed on a real Lunar and Pearl (2026-10-09).
class AcaiaDriver extends ScaleDriver {
  AcaiaGeneration? _generation;
  final _parser = AcaiaFrameParser();

  @override
  String get brand => 'Acaia';

  @override
  bool matches(String name) => isAcaiaName(name);

  @override
  ScaleChannels pick(Characteristic? Function(String uuid) find) {
    final modernNotify = find(AcaiaUuids.modernNotify);
    final modernWrite = find(AcaiaUuids.modernWrite);
    final old = find(AcaiaUuids.oldChar);
    if (modernNotify != null && modernWrite != null) {
      _generation = AcaiaGeneration.modern;
      return ScaleChannels(notify: modernNotify, write: modernWrite);
    }
    if (old != null) {
      _generation = AcaiaGeneration.old;
      return ScaleChannels(notify: old, write: old);
    }
    throw const ScaleSetupException(
      'This scale does not speak the Acaia protocol.',
    );
  }

  @override
  Future<void> start(Future<void> Function(Uint8List bytes) write) async {
    // Wait briefly until notifications are really enabled — otherwise the
    // reply to IDENTIFY gets lost.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await write(AcaiaCommands.identify);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await write(AcaiaCommands.notificationRequest);
  }

  @override
  Uint8List get heartbeat => AcaiaCommands.heartbeat;

  @override
  Duration get heartbeatPeriod => acaiaHeartbeatPeriod;

  @override
  Duration get packetTimeout => acaiaPacketTimeout;

  // Battery via the standard service — read only, never subscribed: with
  // battery notifications on before the weight channel, the Pearl (old
  // firmware) stopped sending weight entirely.
  @override
  bool get readsBatteryService => true;

  @override
  void reset() => _parser.reset();

  @override
  ScalePacket parse(List<int> packet) {
    var weights = _parser.feed(packet);
    if (weights.isEmpty) {
      final g = parseHeaderlessWeight(packet);
      if (g != null) weights = [g];
    }
    return ScalePacket(weights: weights);
  }

  @override
  List<Uint8List> get tare => [AcaiaCommands.tare];
  @override
  List<Uint8List> get startTimer => [AcaiaCommands.startTimer];
  @override
  List<Uint8List> get stopTimer => [AcaiaCommands.stopTimer];
  @override
  List<Uint8List> get resetTimer => [AcaiaCommands.resetTimer];

  @override
  String? get details => switch (_generation) {
    AcaiaGeneration.old => 'old firmware',
    AcaiaGeneration.modern => 'new firmware',
    null => null,
  };
}

import 'dart:io';
import 'dart:math' as math;

import 'package:beand/models/machine_sensors.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/temperature_ring.dart';
import 'package:beand/screens/live/temperature_tile.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The hero ring's heating model (ETA, ring fill, stabilized) run over a
// whole simulated heating run, step by step, against a recorded reference.
// Written before the model moved out of TemperatureTile (2026-10-21) so the
// move can prove it changed nothing. To record anew on purpose:
//   BEAND_UPDATE_REFERENCE=1 flutter test test/heating_reference_test.dart

const _referencePath = 'test/data/heating_reference.txt';

class _FakeMachine extends MeticulousSocketService {
  _FakeMachine() : super(hostname: 'unreachable.local');

  String session = 'idle';

  @override
  String get confirmedSessionState => session;

  // The group head ([down]) lags behind the chamber as on the real machine.
  void feed({required String phase, required double up, required double down}) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': session,
      'sensors': {'p': 0.0, 'f': 0.0, 'w': 0.0, 't': up, 'g': 0.0},
      'time': 0,
      'profile_time': 0,
      'extracting': false,
      'loaded_profile': 'Soup',
      'id': '',
    });
    latestSensors = MachineSensors.fromJson({
      't_bar_up': up,
      't_bar_mu': up - 0.3,
      't_bar_md': up - 0.6,
      't_bar_down': down,
    });
    notifyListeners();
  }
}

// Heating from 28° to ~90°: slow start, full rate, flattening approach —
// the S shape of the real captures. A little deterministic ripple on top.
double _chamberAt(double t) {
  final ramp = 1 / (1 + math.exp(-(t - 120) / 38));
  return 28 + 62.5 * ramp + 0.15 * math.sin(t / 3);
}

void main() {
  testWidgets('heating model matches the recorded reference', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final machine = _FakeMachine()..targetTemperature = 90;
    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: machine,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: TemperatureTile()),
          ),
        ),
      ),
    );

    final lines = <String>[];
    String round(double v) => v.toStringAsFixed(4);
    void record(String label) {
      final ring = tester.widget<TemperatureRing>(find.byType(TemperatureRing));
      lines.add(
        '$label | ${ring.heroValue == null ? '-' : round(ring.heroValue!)}'
        ' | ${ring.statusText ?? '-'} | ${round(ring.progress)}'
        ' | ${round(ring.outerProgress ?? -1)} | ${ring.showCheck}',
      );
    }

    const step = Duration(milliseconds: 500);
    // Resting before the session.
    for (var i = 0; i < 40; i++) {
      machine.feed(phase: 'idle', up: 28, down: 27);
      await tester.pump(step);
      if (i % 10 == 9) record('idle $i');
    }
    // Profile start: heating until the mean reaches target − 2, then the
    // machine's "click to start", then holding near the target.
    machine.session = 'brewing';
    var phase = 'heating';
    for (var i = 0; i < 900; i++) {
      final t = i * 0.5;
      final up = _chamberAt(t);
      final down = up - 3.5 * math.exp(-t / 200) - 1.2;
      final mean = (up + (up - 0.3) + (up - 0.6) + down) / 4;
      if (phase == 'heating' && mean >= 88) phase = 'click to start';
      machine.feed(phase: phase, up: up, down: down);
      await tester.pump(step);
      if (i % 5 == 4) record('$phase ${t.toStringAsFixed(1)}');
    }
    // Shot, then back to idle.
    for (var i = 0; i < 20; i++) {
      machine.feed(phase: 'Percolation', up: 89, down: 87);
      await tester.pump(step);
    }
    record('shot');
    machine.session = 'idle';
    for (var i = 0; i < 10; i++) {
      machine.feed(phase: 'idle', up: 88, down: 86);
      await tester.pump(step);
    }
    record('idle after');

    final file = File(_referencePath);
    if (Platform.environment['BEAND_UPDATE_REFERENCE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${lines.join('\n')}\n');
      return;
    }
    final expected = file.readAsLinesSync();
    expect(lines.length, expected.length);
    for (var i = 0; i < lines.length; i++) {
      expect(lines[i], expected[i], reason: 'step $i');
    }
  });
}

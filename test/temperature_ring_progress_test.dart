import 'package:beand/models/machine_sensors.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/temperature_ring.dart';
import 'package:beand/screens/live/temperature_tile.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Inner hero ring: profile started on the machine, app opened only later →
// ring stood at 0 or hung and jumped (10 s interval).

class _FakeMachine extends MeticulousSocketService {
  _FakeMachine() : super(hostname: 'unreachable.local');

  String session = 'idle';

  @override
  String get confirmedSessionState => session;

  void feed({required String phase, required double bars}) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': session,
      'sensors': {'p': 0.0, 'f': 0.0, 'w': 0.0, 't': bars, 'g': 0.0},
      'time': 0,
      'profile_time': 0,
      'extracting': false,
      'loaded_profile': 'Soup',
      'id': '',
    });
    latestSensors = MachineSensors.fromJson({
      't_bar_up': bars,
      't_bar_mu': bars,
      't_bar_md': bars,
      't_bar_down': bars,
    });
    notifyListeners();
  }
}

void main() {
  late _FakeMachine machine;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
  }

  double progress(WidgetTester tester) =>
      tester.widget<TemperatureRing>(find.byType(TemperatureRing)).progress;

  // The same temperature several times so the smoothing (EMA) gets there.
  Future<void> hold(WidgetTester tester, String phase, double bars) async {
    for (var i = 0; i < 30; i++) {
      machine.feed(phase: phase, bars: bars);
      await tester.pump();
    }
  }

  setUp(() {
    machine = _FakeMachine()..targetTemperature = 82;
  });

  testWidgets('app joins mid-preheat: ring is not at 0', (tester) async {
    machine.session = 'brewing';
    await pump(tester);
    await hold(tester, 'heating', 75);
    // Start unknown → room temperature assumed: (75−25)/(80−25).
    expect(progress(tester), closeTo(50 / 55, 0.02));
  });

  testWidgets('start seen by the app: ring counts from start temperature', (
    tester,
  ) async {
    await pump(tester);
    await hold(tester, 'idle', 40);
    machine.session = 'brewing';
    await hold(tester, 'heating', 40);
    expect(progress(tester), closeTo(0, 0.02));
    await hold(tester, 'heating', 60);
    // Updated immediately (before, only after 10 s).
    expect(progress(tester), closeTo(20 / 40, 0.05));
  });

  testWidgets('Ready: Ring voll', (tester) async {
    await pump(tester);
    await hold(tester, 'idle', 40);
    machine.session = 'brewing';
    await hold(tester, 'heating', 40);
    await hold(tester, 'click to start', 81.3);
    expect(progress(tester), 1.0);
  });

  testWidgets('ring glides to the new value, no jumps', (tester) async {
    machine.session = 'brewing';
    await pump(tester);
    await hold(tester, 'heating', 25);
    await tester.pumpAndSettle();
    await hold(tester, 'heating', 80);
    // Target is full, only part of it is painted at first …
    double painted() {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(TemperatureRing),
          matching: find.byType(CustomPaint),
        ),
      );
      return (paint.painter as dynamic).progress as double;
    }

    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), inExclusiveRange(0.05, 0.95));
    // … and everything after gliding.
    await tester.pump(const Duration(seconds: 1));
    expect(painted(), closeTo(1.0, 0.001));
  });
}

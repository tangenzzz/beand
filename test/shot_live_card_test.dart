import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/screens/live/shot_live_card.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Height that ShotCardsCarousel gives the cards.
const _cardHeight = ShotCardsCarousel.cardHeight;

class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  void push({
    required String phase,
    required bool extracting,
    double pressure = 0,
    double flow = 0,
    double weight = 0,
  }) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': phase == 'idle' ? 'idle' : 'brewing',
      'extracting': extracting,
      'sensors': {'p': pressure, 'f': flow, 'w': weight, 't': 92.0, 'g': 0.0},
    });
    notifyListeners();
  }
}

Widget _wrap(FakeSocket socket, LiveShotService live) => MultiProvider(
  providers: [
    ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
    // The same machine again under the shared interface: the pre-shot card
    // talks to it through that.
    ChangeNotifierProvider<EspressoMachine>.value(value: socket),
    ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
    ChangeNotifierProvider<LiveShotService>.value(value: live),
    ChangeNotifierProvider<ShotSetup>.value(value: ShotSetup.inMemory()),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: const Scaffold(
      body: Center(
        child: SizedBox(height: _cardHeight, width: 340, child: ShotLiveCard()),
      ),
    ),
  ),
);

void main() {
  testWidgets('shot card: axes and value row are shown even without data', (
    tester,
  ) async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    await tester.pumpWidget(_wrap(socket, live));
    await tester.pump();

    // No placeholder text anymore, but the real value row (the card
    // visibly waits for the tare point).
    for (final label in ['TIME', 'YIELD', 'FLOW', 'PRESSURE']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('No shot running yet'), findsNothing);
    // No TEMP column on the Meticulous: its four sensors have their own
    // temperature card (see ShotChart.showTemperature).
    expect(find.text('TEMP'), findsNothing);
  });

  testWidgets('shot card: the live curve grows into a fixed time window', (
    tester,
  ) async {
    final socket = FakeSocket()
      // As on the real machine: the profile target is known, the card
      // shows it in the value row. Without it the test below would be moot.
      ..targetTemperature = 93.0;
    final live = MeticulousLiveShotService(socket)..start();
    // Manually at the end: the brew is still running, its heartbeat timer
    // has to go before the test's timer check.

    await tester.pumpWidget(_wrap(socket, live));
    await tester.pump();

    double maxX() => tester.widget<LineChart>(find.byType(LineChart)).data.maxX;

    // Empty: 30-second window.
    expect(maxX(), 30);

    // After a few seconds the axis is still at 30 — so the curve builds
    // from the y-axis to the right instead of sliding in from the right.
    socket.push(phase: 'Water Filling', extracting: false, weight: 5);
    socket.push(phase: 'Initial Saturation', extracting: true, weight: 0);
    socket.push(phase: 'Percolation', extracting: true, weight: 12);
    await tester.pump();
    expect(live.liveReadings, isNotEmpty);
    expect(maxX(), 30);

    // No temperature in the Meticulous chart: neither a fourth curve nor
    // the red target line. The card passes the target temperature only for
    // the value row — the line wrongly depended on that at first.
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData, hasLength(3));
    expect(data.extraLinesData.horizontalLines, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);

    await tester.pumpWidget(const SizedBox());
    live.dispose();
  });

  testWidgets(
    'shot card: values, chart, stages and button fit without scrolling',
    (tester) async {
      final socket = FakeSocket();
      final live = MeticulousLiveShotService(socket)..start();
      // Manually at the end: the brew is still running, its heartbeat timer
      // has to go before the test's timer check.

      await tester.pumpWidget(_wrap(socket, live));

      // Feed a real shot history: pre-infusion, then extraction with
      // several stages (the stage bar needs room, so it belongs in the
      // height test).
      socket.push(phase: 'Water Filling', extracting: false);
      for (var i = 0; i < 5; i++) {
        socket.push(
          phase: 'Initial Saturation',
          extracting: true,
          pressure: 2.0 + i,
          flow: 3,
          weight: i.toDouble(),
        );
      }
      for (var i = 0; i < 5; i++) {
        socket.push(
          phase: 'Percolation',
          extracting: true,
          pressure: 9,
          flow: 2,
          weight: 10.0 + i * 4,
        );
      }
      await tester.pump();

      expect(live.liveReadings, isNotEmpty);
      expect(live.livePhases.length, greaterThan(1));

      // The card does scroll in principle (for the detail values above),
      // but while the shot is running none of that may be needed.
      final scrollable = tester.widget<Scrollable>(
        find.byType(Scrollable).first,
      );
      expect(
        scrollable.controller!.position.maxScrollExtent,
        0,
        reason:
            'Time/Yield/Flow/Pressure, chart, stages and button must be '
            'visible without scrolling',
      );

      await tester.pumpWidget(const SizedBox());
      live.dispose();
    },
  );

  testWidgets('shot card: a swipe over the chart does not freeze the live '
      'values', (tester) async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();

    await tester.pumpWidget(_wrap(socket, live));

    // Lead-in with a negative flow, as the machine reports it right after
    // the tare point.
    socket.push(phase: 'Water Filling', extracting: false, weight: 5);
    socket.push(
      phase: 'Water Filling',
      extracting: false,
      flow: -1.3,
      weight: 0,
    );
    await tester.pump();

    // A swipe that starts on the chart (e.g. meant for the carousel) lands
    // on its left edge — it used to pin the value row to that moment for
    // the rest of the brew.
    await tester.drag(find.byType(LineChart), const Offset(-200, 0));
    await tester.pump();
    // Scrubbing during the brew is wanted — but only for a moment.
    expect(find.text('-1.3 ml/s', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));

    socket.push(
      phase: 'Percolation',
      extracting: true,
      pressure: 9,
      flow: 2.4,
      weight: 20,
    );
    await tester.pump();

    expect(find.text('2.4 ml/s', findRichText: true), findsOneWidget);
    expect(find.text('-1.3 ml/s', findRichText: true), findsNothing);

    await tester.pumpWidget(const SizedBox());
    live.dispose();
  });
}

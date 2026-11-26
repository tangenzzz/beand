import 'package:beand/database/database.dart';
import 'package:beand/models/shot_phases.dart';
import 'package:beand/screens/history/shot_chart.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The chart ends with the last brew stage: the trailing retraction (piston
// moves back) is not drawn.
void main() {
  ShotReading r(int id, int ms, String stage) => ShotReading(
    id: id,
    shotId: 1,
    timeMs: ms,
    pressure: 6,
    flow: 2,
    weight: ms / 1000,
    stage: stage,
  );

  final readings = [
    for (var i = 0; i < 20; i++) r(i, i * 500, 'Extraction'),
    for (var i = 20; i < 26; i++) r(i, i * 500, retractionStage),
  ];

  test('withoutRetraction drops only the trailing retraction', () {
    final trimmed = withoutRetraction(readings);
    expect(trimmed.length, 20);
    expect(trimmed.last.timeMs, 9500);
    final noRetraction = readings.take(20).toList();
    expect(withoutRetraction(noRetraction), same(noRetraction));
    final onlyRetraction = readings.skip(20).toList();
    expect(withoutRetraction(onlyRetraction), same(onlyRetraction));
  });

  testWidgets('chart axis and stage bar end before the retraction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ShotChart(
              readings: readings,
              phases: computePhases(readings),
              cursorMs: 9500,
              onCursorChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.maxX, 9.5);
    final bar = tester.widget<StageBar>(find.byType(StageBar));
    expect(bar.phases.any((p) => p.isRetraction), isFalse);
    expect(find.text('Retraction'), findsNothing);
  });

  testWidgets('swiping reaches the end of a longer compared shot', (
    tester,
  ) async {
    final short = [for (var i = 0; i < 20; i++) r(i, i * 500, 'Extraction')];
    final long = [for (var i = 0; i < 60; i++) r(i, i * 500, 'Extraction')];
    var cursor = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ShotChart(
              readings: short,
              phases: computePhases(short),
              other: long,
              cursorMs: 0,
              onCursorChanged: (ms) => cursor = ms,
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(LineChart));
    await tester.dragFrom(
      Offset(box.left + 40, box.center.dy),
      Offset(box.width, 0),
    );
    expect(cursor, 29500);
  });
}

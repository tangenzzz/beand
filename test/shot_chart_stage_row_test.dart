import 'package:beand/database/database.dart';
import 'package:beand/models/shot_phases.dart';
import 'package:beand/screens/history/shot_chart.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The stage details arrow sits to the right of the stage name, but at a
// fixed position: it doesn't jump back and forth with short and long names
// when swiping.
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
    for (var i = 0; i < 20; i++) r(i, i * 500, 'Fill'),
    for (var i = 20; i < 40; i++) r(i, i * 500, 'Pressure Decline Long'),
  ];
  final phases = computePhases(readings);

  // The test font draws every character as a square, so texts are much
  // wider here than on the phone — hence the generous width.
  Future<Offset> arrowAt(
    WidgetTester tester,
    int cursorMs, {
    double width = 700,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ShotChart(
              readings: readings,
              phases: phases,
              cursorMs: cursorMs,
              onCursorChanged: (_) {},
              onStageTap: () {},
              stageExpanded: true,
            ),
          ),
        ),
      ),
    );
    final arrow = find.descendant(
      of: find.byKey(const ValueKey('stage-details-toggle')),
      matching: find.byIcon(Icons.expand_less),
    );
    return tester.getTopLeft(arrow);
  }

  testWidgets('arrow stays fixed after the longest name', (tester) async {
    final atShort = await arrowAt(tester, 2000);
    expect(find.text('Fill'), findsOneWidget);
    final atLong = await arrowAt(tester, 15000);
    expect(find.text('Pressure Decline Long').last, findsOneWidget);
    expect(atShort, atLong);

    // Directly after the long name, not at the right edge.
    final nameRight = tester
        .getTopRight(find.text('Pressure Decline Long').last)
        .dx;
    expect(atLong.dx - nameRight, inInclusiveRange(8, 14));
    expect(
      atLong.dx,
      lessThan(tester.getTopLeft(find.textContaining(' s / ')).dx),
    );
  });

  testWidgets('long name is never truncated but wraps', (tester) async {
    // So narrow that the long name doesn't fit on one line.
    await arrowAt(tester, 15000, width: 360);
    final name = tester.widget<Text>(find.text('Pressure Decline Long').last);
    expect(name.maxLines, isNull);
    expect(name.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
    // The row stays as tall as with the long name, even with the short one.
    final longRow = tester.getSize(
      find.byKey(const ValueKey('stage-details-toggle')),
    );
    await arrowAt(tester, 2000, width: 360);
    expect(
      tester.getSize(find.byKey(const ValueKey('stage-details-toggle'))),
      longRow,
    );
    await arrowAt(tester, 15000, width: 360);
    // It wraps instead of clipping: taller than one line.
    expect(
      tester.getSize(find.text('Pressure Decline Long').last).height,
      greaterThan(20),
    );
  });
}

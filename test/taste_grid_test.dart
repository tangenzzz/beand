import 'package:beand/models/taste_profile.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/taste_chips.dart';
import 'package:beand/widgets/underline_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Taste notes in the app: a fixed 2×4 grid, pleasant on top, off-putting
// below; plain text with level dots, no underline, no pill.
void main() {
  testWidgets('2×4 grid, tapping cycles 0 → 3 → 0', (tester) async {
    var values = <TasteAxis, int>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TasteChips(
              values: values,
              onAxisChanged: (axis, v) =>
                  setState(() => values = {...values, axis: v}),
            ),
          ),
        ),
      ),
    );

    double y(String label) => tester.getCenter(find.text(label)).dy;
    for (final axis in TasteAxis.values) {
      final top = y(TasteAxis.finish.label);
      expect(
        y(axis.label) == top,
        axis.isPositive,
        reason:
            '${axis.label} in the ${axis.isPositive ? 'top' : 'bottom'} row',
      );
    }
    expect(find.byType(UnderlineItem), findsNothing);

    for (var i = 1; i <= TasteAxis.maxValue; i++) {
      await tester.tap(find.text('Body'));
      await tester.pump();
      expect(values[TasteAxis.body], i);
    }
    await tester.tap(find.text('Body'));
    await tester.pump();
    expect(values[TasteAxis.body] ?? 0, 0);
  });
}

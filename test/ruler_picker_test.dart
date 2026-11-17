import 'package:beand/screens/live/ruler_picker.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late double value;

  Future<void> pump(WidgetTester tester) async {
    value = 18;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RulerPicker(
              value: 18,
              min: 5,
              max: 30,
              unit: 'g',
              onChanged: (v) => value = v,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dragging the big value slides the ruler like the ruler', (
    tester,
  ) async {
    await pump(tester);
    // 10 px per tick: 50 px to the left are five ticks up.
    await tester.drag(
      find.textContaining('18.0', findRichText: true),
      const Offset(-50, 0),
    );
    await tester.pumpAndSettle();
    expect(value, closeTo(18.5, 0.001));
  });

  testWidgets('a drag beside the value, in the empty row, works too', (
    tester,
  ) async {
    await pump(tester);
    final box = tester.getRect(find.byType(RulerPicker));
    await tester.dragFrom(
      Offset(box.left + 20, box.top + 30),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expect(value, closeTo(17.7, 0.001));
  });

  testWidgets('the keyboard icon still opens the input', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Type value'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}

import 'package:beand/models/taste_profile.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/taste_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The tests check the default appearance: dark with teal.
final _theme = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

Widget _host(Widget child) => MaterialApp(
  // The color tokens hang off the theme — without buildAppTheme() they are
  // missing.
  theme: buildAppTheme(),
  home: Scaffold(
    backgroundColor: _theme.bg,
    body: SingleChildScrollView(child: child),
  ),
);

void main() {
  testWidgets('axis chips count 1-2-3 and drop to 0 on the fourth tap', (
    tester,
  ) async {
    var values = <TasteAxis, int>{};
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => TasteChips(
            values: values,
            onAxisChanged: (axis, value) =>
                setState(() => values = {...values, axis: value}),
          ),
        ),
      ),
    );

    for (final expected in [1, 2, 3, 0]) {
      await tester.tap(find.text('Sweetness'));
      await tester.pump();
      expect(values[TasteAxis.sweetness], expected);
    }
  });

  testWidgets('without callback, display only', (tester) async {
    await tester.pumpWidget(
      _host(const TasteChips(values: {TasteAxis.bitter: 2})),
    );

    expect(find.text('Bitter'), findsOneWidget);
    // All eight axes are shown, including the unrated ones.
    for (final axis in TasteAxis.values) {
      expect(find.text(axis.label), findsOneWidget);
    }
  });
}

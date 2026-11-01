import 'package:beand/screens/beans/freshness.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [220.0, 260.0, 320.0]) {
    testWidgets('freshness legend fits a $width px bubble', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: const FreshnessLegend()),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

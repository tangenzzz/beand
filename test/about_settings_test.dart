import 'package:beand/screens/settings/about_settings_screen.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Settings → About: source code, credits and the open-source licenses.

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: "bean'd",
      packageName: 'app.beand',
      version: '0.9.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  Future<void> pumpAbout(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const AboutSettingsScreen()),
  );

  testWidgets('shows license note, source code, credits and licenses', (
    tester,
  ) async {
    await pumpAbout(tester);
    expect(find.textContaining('GPL-3.0'), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);
    expect(find.text('Credits'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('credits page lists every credit with its usage', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('Credits'));
    await tester.pumpAndSettle();
    for (final c in credits) {
      await tester.scrollUntilVisible(find.text(c.name), 200);
      expect(find.text(c.name), findsOneWidget);
      expect(find.textContaining(c.usage), findsOneWidget);
    }
  });

  testWidgets('opens the license page with the app version', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('0.9.0 (1)'), findsOneWidget);
  });

  test('every credit links to https', () {
    for (final c in credits) {
      expect(c.url, startsWith('https://'), reason: c.name);
    }
  });
}

import 'package:beand/screens/settings/settings_widgets.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ⓘ bubble: tapping the ⓘ opens and closes, tapping beside it closes;
// tapping inside the bubble keeps it open.

void main() {
  testWidgets('ⓘ opens and closes on tap, tapping beside it closes too', (
    tester,
  ) async {
    var rowTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              ListTile(
                onTap: () => rowTaps++,
                title: const SettingsTitle(
                  'Title',
                  info: 'Explained here.',
                  infoHeading: 'Heading',
                ),
              ),
              const SizedBox(height: 300),
              const Text('elsewhere'),
            ],
          ),
        ),
      ),
    );
    final info = find.byType(SettingsInfo);
    expect(find.textContaining('Explained here.'), findsNothing);

    await tester.tap(info);
    await tester.pump();
    expect(find.textContaining('Explained here.'), findsOneWidget);
    expect(find.textContaining('Heading'), findsOneWidget);
    // The ⓘ catches the tap: the row below doesn't trigger.
    expect(rowTaps, 0);

    // Tap inside the bubble: stays open.
    await tester.tap(find.textContaining('Explained here.'));
    await tester.pump();
    expect(find.textContaining('Explained here.'), findsOneWidget);

    // The ⓘ again: closed.
    await tester.tap(info);
    await tester.pump();
    expect(find.textContaining('Explained here.'), findsNothing);

    // Open, then tap beside it: closed.
    await tester.tap(info);
    await tester.pump();
    expect(find.textContaining('Explained here.'), findsOneWidget);
    await tester.tap(find.text('elsewhere'));
    await tester.pump();
    expect(find.textContaining('Explained here.'), findsNothing);
  });
}

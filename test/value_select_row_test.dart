import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/value_select_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The app's one selection pattern: value row + inline list.
void main() {
  final colors = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

  List<ValueOption<int>> options(int n) => [
    for (var i = 0; i < n; i++) ValueOption(value: i, title: 'Option $i'),
  ];

  Widget host(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: ListView(children: [child, const SizedBox(height: 2000)]),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Color textColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  testWidgets('placeholder dimmed, value in text color', (tester) async {
    int? value;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => ValueSelectRow<int>(
            label: 'Bean',
            placeholder: 'Select bean',
            value: value,
            options: options(3),
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(textColor(tester, 'Select bean'), colors.textTertiary);

    await tester.tap(find.text('Select bean'));
    await settle(tester);
    // Open: chevron turned up, options listed, nothing ticked yet.
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.5,
    );
    expect(find.text('Option 1'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    // Unselected options in the secondary tone.
    expect(textColor(tester, 'Option 1'), colors.textSecondary);

    await tester.tap(find.text('Option 1'));
    await settle(tester);
    expect(value, 1);
    // Closed again, the row shows the title.
    expect(find.text('Option 0'), findsNothing);
    expect(textColor(tester, 'Option 1'), colors.textPrimary);

    // Reopen: the chosen one is ticked in the accent color; tapping the
    // row again closes without a change.
    await tester.tap(find.text('Option 1'));
    await settle(tester);
    final check = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(check.color, colors.accent);
    await tester.tap(find.text('Bean'));
    await settle(tester);
    expect(find.text('Option 0'), findsNothing);
    expect(value, 1);
  });

  testWidgets('one list open at a time within a group', (tester) async {
    await tester.pumpWidget(
      host(
        ValueSelectGroup(
          child: Column(
            children: [
              ValueSelectRow<int>(
                label: 'A',
                placeholder: 'pick a',
                value: null,
                options: [const ValueOption(value: 1, title: 'a1')],
                onChanged: (_) {},
              ),
              ValueSelectRow<int>(
                label: 'B',
                placeholder: 'pick b',
                value: null,
                options: [const ValueOption(value: 1, title: 'b1')],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick a'));
    await settle(tester);
    expect(find.text('a1'), findsOneWidget);
    await tester.tap(find.text('pick b'));
    await settle(tester);
    expect(find.text('a1'), findsNothing);
    expect(find.text('b1'), findsOneWidget);
  });

  testWidgets('search above 8 entries, action at the end, subtitle', (
    tester,
  ) async {
    var added = false;
    await tester.pumpWidget(
      host(
        ValueSelectRow<int>(
          label: 'Bean',
          placeholder: 'Select bean',
          value: null,
          options: [
            for (var i = 0; i < 9; i++)
              ValueOption(value: i, title: 'Bean $i', subtitle: 'Roaster $i'),
          ],
          onChanged: (_) {},
          action: ValueSelectAction('New bean', () => added = true),
        ),
      ),
    );
    await tester.tap(find.text('Select bean'));
    await settle(tester);
    // Bottom bar: magnifier left, "+" right — icons only, no field yet.
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('New bean'), findsNothing, reason: 'icon only');
    expect(find.text('Roaster 0'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('Search')).dx,
      lessThan(tester.getCenter(find.byTooltip('New bean')).dx),
    );
    expect(
      tester.getTopLeft(find.byTooltip('Search')).dy,
      greaterThan(tester.getTopLeft(find.text('Roaster 0')).dy),
      reason: 'the bar sits below the list',
    );
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'bean 7');
    await tester.pump();
    expect(find.text('Bean 7'), findsOneWidget);
    expect(find.text('Bean 0'), findsNothing);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.text('Bean 0'), findsOneWidget, reason: 'closing clears it');

    final plus = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('New bean'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(plus.color, colors.accent);
    await tester.tap(find.byTooltip('New bean'));
    await settle(tester);
    expect(added, isTrue);
    expect(find.text('Bean 7'), findsNothing, reason: 'the action closes it');
  });

  testWidgets('up to 8 entries: no search field', (tester) async {
    await tester.pumpWidget(
      host(
        ValueSelectRow<int>(
          label: 'X',
          placeholder: 'pick',
          value: null,
          options: options(8),
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await settle(tester);
    expect(find.byTooltip('Search'), findsNothing);
  });

  testWidgets('a tap outside closes the list, scrolling does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              ValueSelectRow<int>(
                label: 'X',
                placeholder: 'pick',
                value: null,
                options: options(3),
                onChanged: (_) {},
              ),
              const SizedBox(height: 300, child: Text('elsewhere')),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await settle(tester);
    expect(find.text('Option 0'), findsOneWidget);
    await tester.tap(find.text('elsewhere'));
    await settle(tester);
    expect(find.text('Option 0'), findsNothing);

    await tester.tap(find.text('pick'));
    await settle(tester);
    expect(find.text('Option 0'), findsOneWidget);
    // Scrolling the page keeps the list open (it scrolls along).
    await tester.drag(find.text('elsewhere'), const Offset(0, -100));
    await settle(tester);
    expect(find.text('Option 0'), findsOneWidget);
  });

  testWidgets('semantics: label, value and expanded state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        ValueSelectRow<int>(
          label: 'Bean',
          value: 2,
          options: options(3),
          onChanged: (_) {},
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('Bean')),
      matchesSemantics(
        label: 'Bean',
        value: 'Option 2',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}

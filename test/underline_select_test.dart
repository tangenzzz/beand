import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/underline_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Direct choices without a dropdown: plain text, the chosen one underlined.
void main() {
  final colors = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

  Widget host(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  TextStyle styleOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!;

  testWidgets('single select: picks one, the previous one goes', (
    tester,
  ) async {
    String? value = 'a';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => UnderlineSelect<String>(
            options: const [
              UnderlineOption('a', 'Apple'),
              UnderlineOption('b', 'Berry'),
            ],
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(styleOf(tester, 'Apple').color, colors.textPrimary);
    expect(styleOf(tester, 'Apple').fontWeight, FontWeight.w500);
    expect(styleOf(tester, 'Berry').color, colors.textSecondary);

    await tester.tap(find.text('Berry'));
    await tester.pumpAndSettle();
    expect(value, 'b');
    expect(styleOf(tester, 'Apple').color, colors.textSecondary);
    // Tapping the chosen one again changes nothing (no allowDeselect).
    await tester.tap(find.text('Berry'));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });

  testWidgets('multi select toggles; at least 44 px tap height', (
    tester,
  ) async {
    final values = <int>{};
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => UnderlineSelect<int>.multi(
            options: const [
              UnderlineOption(1, 'One'),
              UnderlineOption(2, 'Two'),
            ],
            values: values,
            onToggle: (v) => setState(() => values.remove(v) || values.add(v)),
          ),
        ),
      ),
    );
    await tester.tap(find.text('One'));
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(values, {1, 2});
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(values, {2});
    expect(
      tester.getSize(find.byType(UnderlineItem).first).height,
      greaterThanOrEqualTo(UnderlineItem.minTapHeight),
    );
  });

  testWidgets('allowDeselect: tapping the chosen one clears it', (
    tester,
  ) async {
    String? value = 'a';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => UnderlineSelect<String>(
            options: const [UnderlineOption('a', 'Apple')],
            value: value,
            allowDeselect: true,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets('semantics: button with selected state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(UnderlineItem(label: 'Fruity', selected: true, onTap: () {})),
    );
    expect(
      tester.getSemantics(find.byType(UnderlineItem)),
      matchesSemantics(
        label: 'Fruity',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}

import 'package:beand/screens/history/history_logic.dart';
import 'package:beand/widgets/machine_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each machine has its own glyph and color', () {
    // How a shot is recognized in the history: Meticulous M, GaggiMate G,
    // Pour Over the V60 dripper.
    expect(ShotMachine.fromKey('meticulous').glyph, MachineGlyph.letterM);
    expect(ShotMachine.fromKey('gaggimate').glyph, MachineGlyph.letterG);
    expect(ShotMachine.fromKey('pourover').glyph, MachineGlyph.v60);

    final colors = {for (final m in ShotMachine.values) m.color};
    expect(
      colors.length,
      ShotMachine.values.length,
      reason: 'the same color on two machines would be indistinguishable',
    );
  });

  testWidgets('letters as text, the dripper drawn', (tester) async {
    Future<void> show(MachineGlyph glyph) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MachineBadge(glyph: glyph, color: Colors.teal),
          ),
        ),
      ),
    );

    await show(MachineGlyph.letterM);
    expect(find.text('M'), findsOneWidget);

    await show(MachineGlyph.letterG);
    expect(find.text('G'), findsOneWidget);

    await show(MachineGlyph.v60);
    // Not a letter but a drawn shape.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

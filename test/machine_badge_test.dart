import 'package:beand/screens/history/history_logic.dart';
import 'package:beand/widgets/machine_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each machine has its own glyph and color', () {
    // How a shot is recognized in the history: Meticulous M, GaggiMate GM,
    // Pour Over the V60 dripper.
    expect(ShotMachine.fromKey('meticulous').glyph, MachineGlyph.letterM);
    expect(ShotMachine.fromKey('gaggimate').glyph, MachineGlyph.gaggiMate);
    expect(ShotMachine.fromKey('pourover').glyph, MachineGlyph.v60);

    final colors = {for (final m in ShotMachine.values) m.color};
    expect(
      colors.length,
      ShotMachine.values.length,
      reason: 'the same color on two machines would be indistinguishable',
    );
  });

  testWidgets('M as text, GM from the wordmark, the dripper drawn', (
    tester,
  ) async {
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

    await show(MachineGlyph.gaggiMate);
    // G and M cut from the GaggiMate wordmark, not a font.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);

    await show(MachineGlyph.v60);
    // Not a letter but a drawn shape.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

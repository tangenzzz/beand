import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/command_buttons_row.dart';
import 'package:beand/screens/live/sweeping_icon.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The loading state of Purge/Raise depends solely on the `phase` reported
// by the machine — so it's enough to set the status without triggering an
// action. That's exactly the case of someone operating the machine via the
// dial.
// isPreheatActive depends on the machine's `heater_status` stream; for the
// button state the switch is enough.
class PreheatingSocket extends MeticulousSocketService {
  PreheatingSocket() : super(hostname: 'unreachable.local');

  @override
  bool get isPreheatActive => true;
}

void main() {
  late MeticulousSocketService service;

  Widget wrap() => ChangeNotifierProvider<MeticulousSocketService>.value(
    value: service,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: CommandButtonsRow()),
    ),
  );

  setUp(() {
    service = MeticulousSocketService(hostname: 'unreachable.local');
  });

  tearDown(() => service.dispose());

  SweepingIcon sweep(WidgetTester tester, IconData icon) => tester.widget(
    find.byWidgetPredicate((w) => w is SweepingIcon && w.icon == icon),
  );

  InkWell button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );

  testWidgets('idle: nothing glows and both arrows accept taps', (
    tester,
  ) async {
    service.latestStatus = MachineStatus.fromJson({'name': 'idle'});
    await tester.pumpWidget(wrap());

    expect(sweep(tester, Icons.arrow_downward).active, isFalse);
    expect(sweep(tester, Icons.arrow_upward).active, isFalse);
    expect(button(tester, 'Purge').onTap, isNotNull);
    expect(button(tester, 'Raise').onTap, isNotNull);
    // At rest no mask is drawn, so no ticker runs either.
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('phase "purge" makes the Purge arrow glow and locks it', (
    tester,
  ) async {
    service.latestStatus = MachineStatus.fromJson({'name': 'purge'});
    await tester.pumpWidget(wrap());

    expect(sweep(tester, Icons.arrow_downward).active, isTrue);
    expect(button(tester, 'Purge').onTap, isNull, reason: 'double trigger');
    // Only the affected button — Raise stays available.
    expect(sweep(tester, Icons.arrow_upward).active, isFalse);
    expect(button(tester, 'Raise').onTap, isNotNull);
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('phase "home" belongs to Raise, not Purge', (tester) async {
    service.latestStatus = MachineStatus.fromJson({'name': 'home'});
    await tester.pumpWidget(wrap());

    expect(sweep(tester, Icons.arrow_upward).active, isTrue);
    expect(button(tester, 'Raise').onTap, isNull);
    expect(sweep(tester, Icons.arrow_downward).active, isFalse);
    expect(button(tester, 'Purge').onTap, isNotNull);
  });

  // The arrows light up in the direction they point: Purge moves the piston
  // down, Raise up.
  testWidgets('glow direction follows the arrow', (tester) async {
    service.latestStatus = MachineStatus.fromJson({'name': 'idle'});
    await tester.pumpWidget(wrap());

    expect(sweep(tester, Icons.arrow_downward).direction, AxisDirection.down);
    expect(sweep(tester, Icons.arrow_upward).direction, AxisDirection.up);
  });

  testWidgets('preheat only makes the icon glow permanently', (tester) async {
    service = PreheatingSocket();
    service.latestStatus = MachineStatus.fromJson({'name': 'idle'});
    await tester.pumpWidget(wrap());

    final accent = AppColors.forVariant(
      AppThemeVariant.dark,
      AppAccent.teal,
    ).accent;
    // When active the button becomes a stop button — its icon glows.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.stop_circle_outlined)).color,
      accent,
    );
    // The label below stays neutral, ...
    expect(tester.widget<Text>(find.text('Stop')).style?.color, isNot(accent));
    // ... and so do the neighbors.
    expect(tester.widget<Text>(find.text('Purge')).style?.color, isNot(accent));
  });

  // The glow grows from the start of the arrow to its tip and never falls
  // back — checked at the leading edge of the gradient.
  test('glow grows up to the tip and stays within the drawing', () {
    double lead(double t) => SweepingIcon.gradientFor(
      t: t,
      direction: AxisDirection.down,
      baseColor: Colors.grey,
      glowColor: Colors.teal,
    ).stops![2];

    expect(
      lead(0),
      closeTo(SweepingIcon.defaultInset, 0.002),
      reason: 'start at the drawing, not at the box edge',
    );
    expect(
      lead(1),
      closeTo(1 - SweepingIcon.defaultInset, 0.002),
      reason: 'end at the tip, not at the box edge',
    );

    var previous = -1.0;
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      final stops = SweepingIcon.gradientFor(
        t: t,
        direction: AxisDirection.down,
        baseColor: Colors.grey,
        glowColor: Colors.teal,
      ).stops!;
      expect(stops[2], greaterThan(previous), reason: 'falls back at t=$t');
      previous = stops[2];
      // A gradient with descending stops throws when drawn.
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThanOrEqualTo(stops[i - 1]), reason: 't=$t');
      }
    }
  });

  test('glow direction rotates the gradient, not just the colors', () {
    LinearGradient g(AxisDirection d) => SweepingIcon.gradientFor(
      t: 0.5,
      direction: d,
      baseColor: Colors.grey,
      glowColor: Colors.teal,
    );

    expect(g(AxisDirection.down).begin, Alignment.topCenter);
    expect(g(AxisDirection.up).begin, Alignment.bottomCenter);
  });
}

import 'package:beand/screens/live/temperature_ring.dart';
import 'package:beand/screens/live/temperature_tile.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Widget wrap(Widget child) => ChangeNotifierProvider<MeticulousSocketService>(
    create: (_) => MeticulousSocketService(hostname: 'unreachable.local'),
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('sensors are stacked next to the ring', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const TemperatureTile()));
    await tester.pump();

    for (final label in ['UP', 'MID', 'DOWN', 'GROUP HEAD']) {
      expect(find.text(label), findsOneWidget, reason: '$label missing');
    }

    // Stacked, no longer in two columns left and right.
    final up = tester.getRect(find.text('UP'));
    final mid = tester.getRect(find.text('MID'));
    final down = tester.getRect(find.text('DOWN'));
    final head = tester.getRect(find.text('GROUP HEAD'));

    expect(up.top, lessThan(mid.top));
    expect(mid.top, lessThan(down.top));
    expect(down.top, lessThan(head.top));
    // All four start on the same vertical line.
    expect(mid.left, closeTo(up.left, 0.5));
    expect(down.left, closeTo(up.left, 0.5));
    expect(head.left, closeTo(up.left, 0.5));

    // And they sit to the right of the ring, not around it.
    final ring = tester.getRect(find.byType(TemperatureRing));
    expect(up.left, greaterThan(ring.right));
  });

  // The column must not overtop the ring — otherwise the card grows with
  // the sensors instead of the ring.
  testWidgets('sensor column stays within the ring height', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const TemperatureTile()));
    await tester.pump();

    final ring = tester.getRect(find.byType(TemperatureRing));
    expect(ring.height, TemperatureRing.defaultSize);

    final up = tester.getRect(find.text('UP'));
    final head = tester.getRect(find.text('GROUP HEAD'));

    expect(up.top, greaterThanOrEqualTo(ring.top - 0.5));
    expect(head.bottom, lessThanOrEqualTo(ring.bottom + 0.5));
  });

  // The outer ring takes the target tone instead of the accent color.
  // Proven by changing only the accent — if the ring then paints
  // identically, it no longer depends on it.
  testWidgets('stabilization ring no longer depends on the accent color', (
    tester,
  ) async {
    Future<CustomPainter> painterFor(AppAccent accent) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(accent: accent),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TemperatureRing(
                  heroValue: 92,
                  targetTemp: 93,
                  progress: 1,
                  outerProgress: 0.5,
                  color: context.colors.heroRingReady,
                  statusText: 'Stabilizing',
                  statusColor: context.colors.textSecondary,
                  showCheck: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(TemperatureRing),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter!;
      // Tear down in between: a second pumpWidget alone does not pass the
      // changed theme through to the ring (measured in the test).
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      return painter;
    }

    final teal = await painterFor(AppAccent.teal);
    final cascara = await painterFor(AppAccent.cascara);

    // The two accents really are different …
    expect(
      AppAccent.teal.dark,
      isNot(AppAccent.cascara.dark),
      reason: 'test precondition',
    );
    // … the ring still paints the same.
    expect(
      cascara.shouldRepaint(teal),
      isFalse,
      reason: 'changing the accent must no longer change the ring',
    );
  });
}

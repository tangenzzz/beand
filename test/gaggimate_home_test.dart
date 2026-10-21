import 'dart:async';
import 'dart:convert';

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_live_shot_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/screens/live/gaggimate/gaggimate_hero.dart';
import 'package:beand/screens/live/gaggimate/gaggimate_home.dart';
import 'package:beand/screens/live/sensor_stack.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/screens/live/shot_live_card.dart';
import 'package:beand/screens/live/temperature_ring.dart';
import 'package:beand/screens/live/tile_title.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_sync_service.dart';
import 'package:beand/services/profile_store.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The tests check the default appearance: dark with teal.
final _theme = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

class FakeTransport implements GaggiMateTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) =>
      sent.add(Map<String, dynamic>.from(jsonDecode(data) as Map));

  @override
  Future<void> close() async => _incoming.close();

  void receive(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));
}

void main() {
  late AppDatabase db;
  late FakeTransport transport;
  late GaggiMateService machine;
  late GaggiMateLiveShotService live;

  // Reset per test: the request IDs start over with each new service; a
  // shared set would leave later tests empty-handed.
  final answered = <String>{};

  setUp(() {
    answered.clear();
    db = AppDatabase(NativeDatabase.memory());
    transport = FakeTransport();
    machine = GaggiMateService(
      host: 'gaggimate.local',
      transportFactory: (_) => transport,
      autoReconnect: false,
    )..connect();
    live = GaggiMateLiveShotService(machine)..start();
  });

  tearDown(() {
    live.dispose();
    machine.dispose();
  });

  // Tear down the tree inside the test body and pump once: the pre-shot
  // card's bean query cleans up on unsubscribe via a zero-duration timer,
  // which would otherwise break the test end as a "pending timer".
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Let real (if tiny) time pass, otherwise drift's cleanup timer gets
    // stuck.
    await tester.pump(const Duration(milliseconds: 10));
  }

  // The service requests the profile list right after connecting. The
  // answer must come, otherwise its timeout runs as a pending timer until
  // the end of the test.
  // There can be SEVERAL pending: the service asks itself on connect, the
  // home screen's profile store asks again. If only the last one is
  // answered, `service.profiles` stays empty — and with it the brew
  // temperature, which comes exactly from there, stays unknown.

  void answerOneProfileList(Map<String, dynamic> request) {
    transport.receive({
      'tp': 'res:profiles:list',
      'rid': request['rid'],
      'profiles': [
        {
          'id': 'p1',
          'label': 'Londinium',
          'description': '',
          'temperature': 93,
          'selected': true,
          'phases': [
            {
              'name': 'Brew',
              'duration': 25,
              'targets': [
                {'type': 'volumetric', 'value': 36},
              ],
            },
          ],
        },
      ],
    });
  }

  void answerProfileList() {
    for (final request
        in transport.sent
            .where((m) => m['tp'] == 'req:profiles:list')
            .toList()) {
      if (answered.add('${request['rid']}')) answerOneProfileList(request);
    }
  }

  Widget wrap() => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
      ChangeNotifierProvider<ShotSetup>.value(
        value: ShotSetup.inMemory(machineKey: 'gaggimate'),
      ),
      // The home screen's profile row reads this machine's profiles
      // from the local store.
      Provider<ProfileStore>.value(
        value: GaggiMateProfileSyncService(database: db, machine: machine),
      ),
      ChangeNotifierProvider<GaggiMateService>.value(value: machine),
      ChangeNotifierProvider<EspressoMachine>.value(value: machine),
      ChangeNotifierProvider<LiveShotService>.value(value: live),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: SingleChildScrollView(child: GaggiMateHome())),
    ),
  );

  testWidgets(
    'GaggiMate home shows hero ring, commands and the same three cards',
    (tester) async {
      await tester.pumpWidget(wrap());
      answerProfileList();
      transport.receive({
        'tp': 'evt:status',
        'ct': 92.4,
        'tt': 93.0,
        'm': 1,
        'p': 'Londinium',
        'sys': {'s': 'ready', 'm': '', 'c': 0},
      });
      await tester.pump();

      // The same hero ring as on the Meticulous home.
      expect(find.byType(TemperatureRing), findsOneWidget);
      expect(find.text('92.4°'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      // The GaggiMate command row.
      expect(find.text('Brew'), findsOneWidget);
      expect(find.text('Steam'), findsOneWidget);
      expect(find.text('Flush'), findsOneWidget);

      // And the shared shot cards: the first page is PREShot.
      expect(find.byType(TileTitle), findsWidgets);
      expect(find.text('PRE'), findsOneWidget);
      expect(find.text('Profile'), findsWidgets);

      // The machine's profile cards below the carousel.
      expect(find.text('Londinium'), findsWidgets);

      // No "Auto Start": in brew mode the machine is always ready, so the
      // checkbox would mean an immediate start.
      expect(find.text('Auto Start'), findsNothing);
      expect(find.byKey(const ValueKey('autoStartBox')), findsNothing);

      await disposeTree(tester);
    },
  );

  testWidgets('active machine warning is shown below the hero', (tester) async {
    await tester.pumpWidget(wrap());
    answerProfileList();
    transport.receive({
      'tp': 'evt:status',
      'ct': 90.0,
      'tt': 93.0,
      'm': 1,
      'warn': [
        {'k': 'water', 'l': 2, 'a': true},
        {'k': 'flush', 'l': 1, 'a': false},
      ],
    });
    await tester.pump();

    expect(find.text('Water tank empty'), findsOneWidget);
    // Inactive warnings stay invisible.
    expect(find.text('Flush needed'), findsNothing);

    // No divider above the warnings anymore.
    expect(
      find.descendant(
        of: find.byType(GaggiMateHero),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );

    await disposeTree(tester);
  });

  testWidgets(
    'hero without card: ring on the left, three values on the right, one ring',
    (tester) async {
      await tester.pumpWidget(wrap());
      answerProfileList();
      transport.receive({
        'tp': 'evt:status',
        'ct': 93.1,
        'tt': 93.0,
        'm': 1,
        'cp': true, // Pro: reports pressure and flow
        'pr': 9.1,
        'fl': 2.1,
        'bc': true, // scale connected
        'cw': 18.4,
        'sys': {'s': 'ready', 'm': '', 'c': 0},
      });
      await tester.pump();

      // All three values, each in its own row — the same column as on the
      // Meticulous.
      expect(find.byType(SensorRow), findsNWidgets(3));
      expect(find.text('BAR'), findsOneWidget);
      expect(find.text('ML/S'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.text('9.1'), findsOneWidget);
      expect(find.text('2.1'), findsOneWidget);
      expect(find.text('18.4'), findsOneWidget);

      // The ring sits to the left of each of the three rows.
      final ring = tester.getRect(find.byType(TemperatureRing));
      for (final box in find.byType(SensorRow).evaluate()) {
        expect(
          tester.getRect(find.byWidget(box.widget)).left,
          greaterThan(ring.right),
        );
      }

      // Together the three fields stay at most as tall as the ring — the
      // height follows from the font size, so it would otherwise grow
      // unnoticed.
      final boxes = find.byType(SensorRow).evaluate().toList();
      final top = boxes
          .map((b) => tester.getRect(find.byWidget(b.widget)).top)
          .reduce((a, b) => a < b ? a : b);
      final bottom = boxes
          .map((b) => tester.getRect(find.byWidget(b.widget)).bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(bottom - top, lessThanOrEqualTo(ring.height));

      // Only ONE ring: no "Stabilized" outer ring.
      final ringWidget = tester.widget<TemperatureRing>(
        find.byType(TemperatureRing),
      );
      expect(ringWidget.outerProgress, isNull);

      // No card around the hero anymore: between hero and screen there is
      // nothing left that paints a card surface.
      expect(
        find.descendant(
          of: find.byType(GaggiMateHero),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == _theme.card,
          ),
        ),
        findsNothing,
      );

      await disposeTree(tester);
    },
  );

  testWidgets('without scale and pressure control the fields stay in place', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    answerProfileList();
    transport.receive({
      'tp': 'evt:status',
      'ct': 90.0,
      'tt': 93.0,
      'm': 1,
      'sys': {'s': 'ready', 'm': '', 'c': 0},
    });
    await tester.pump();

    // The layout stays the same, the values are just empty — otherwise the
    // area would jump as soon as a scale is added.
    expect(find.byType(SensorRow), findsNWidgets(3));
    expect(find.text('G'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SensorRow),
        matching: find.text('\u2014'),
      ),
      findsNWidgets(3),
    );

    await disposeTree(tester);
  });

  testWidgets('more than two warnings: rest behind "+n", expandable', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    answerProfileList();
    transport.receive({
      'tp': 'evt:status',
      'ct': 90.0,
      'tt': 93.0,
      'm': 1,
      'warn': [
        {'k': 'water', 'l': 2, 'a': true}, // blocking
        {'k': 'flush', 'l': 1, 'a': true},
        {'k': 'switch', 'l': 1, 'a': true},
        {'k': 'scaleBattery', 'l': 1, 'a': true},
      ],
    });
    await tester.pump();

    // Two rows, blocking first, the rest summarized.
    expect(find.text('Water tank empty'), findsOneWidget);
    expect(find.text('Flush needed'), findsOneWidget);
    expect(find.text('Brew switch is on'), findsNothing);
    expect(find.text('Scale battery low'), findsNothing);
    expect(find.text('+2'), findsOneWidget);

    // Tapping shows all, tapping again collapses.
    await tester.tap(find.text('+2'));
    await tester.pump();
    expect(find.text('Brew switch is on'), findsOneWidget);
    expect(find.text('Scale battery low'), findsOneWidget);
    expect(find.text('less'), findsOneWidget);

    await tester.tap(find.text('less'));
    await tester.pump();
    expect(find.text('+2'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('steam, water and flush can be stopped from the command row', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    answerProfileList();
    transport.receive({
      'tp': 'evt:status',
      'ct': 93.0,
      'tt': 93.0,
      'm': 2, // Steam
      'sys': {'s': 'ready', 'm': '', 'c': 0},
    });
    await tester.pump();
    expect(find.text('Steam'), findsOneWidget);

    // Steam running: the firmware only reports {"a": 1}.
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1},
    });
    await tester.pump();
    expect(find.text('Steam'), findsNothing);
    expect(find.text('Stop'), findsOneWidget);
    // And it does NOT jump to the live card (the carousel's three pages
    // always exist, but the "current" one is still PRE).
    expect(live.stage, isNot(ShotStage.running));
    expect(live.activeCard, isNot(ActiveCard.live));

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:process:deactivate');

    // Water: the same button in a different place.
    transport.receive({'tp': 'evt:status', 'process': null, 'm': 3});
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1},
    });
    await tester.pump();
    expect(find.text('Water'), findsNothing);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:process:deactivate');

    // Flush: it is aborted with req:process:deactivate.
    // In the firmware `req:flush:stop` only means "button released" and lets
    // a fixed-duration flush run to completion (measured on the simulator).
    transport.receive({'tp': 'evt:status', 'process': null, 'm': 1});
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1, 's': 'brew', 'l': 'Flush', 'e': 500, 'u': 1},
    });
    await tester.pump();
    expect(find.text('Flush'), findsNothing);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:process:deactivate');

    await disposeTree(tester);
  });

  testWidgets('water: first mode, then water runs, then stop', (tester) async {
    await tester.pumpWidget(wrap());
    answerProfileList();
    transport.receive({
      'tp': 'evt:status',
      'ct': 93.0,
      'tt': 93.0,
      'm': 1, // Brew
      'sys': {'s': 'ready', 'm': '', 'c': 0},
    });
    await tester.pump();

    // From another mode the button only sets the mode.
    await tester.tap(find.text('Water'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:change-mode');
    expect(transport.sent.last['mode'], 3);

    // In water mode the same button runs water — previously it only set the
    // mode and no water ever came.
    transport.receive({'tp': 'evt:status', 'm': 3});
    await tester.pump();
    await tester.tap(find.text('Water'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:process:activate');

    // And while it runs, it stops it.
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1},
    });
    await tester.pump();
    expect(find.text('Water'), findsNothing);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(transport.sent.last['tp'], 'req:process:deactivate');

    await disposeTree(tester);
  });

  // The GaggiMate's temperature (one boiler sensor) belongs in the live
  // curve: red line with its own scale plus a TEMP column in the value row.
  testWidgets('GaggiMate live card: temperature curve and TEMP column', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<ShotSetup>.value(
            value: ShotSetup.inMemory(machineKey: 'gaggimate'),
          ),
          ChangeNotifierProvider<GaggiMateService>.value(value: machine),
          ChangeNotifierProvider<EspressoMachine>.value(value: machine),
          ChangeNotifierProvider<LiveShotService>.value(value: live),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                // As the carousel on the machines' home gives it.
                height:
                    ShotCardsCarousel.cardHeight +
                    ShotCardsCarousel.machineExtra,
                width: 340,
                child: const ShotLiveCard(),
              ),
            ),
          ),
        ),
      ),
    );
    answerProfileList();

    transport.receive({
      'tp': 'evt:status',
      'ct': 92.4,
      'tt': 93.0,
      'm': 1,
      'pr': 8.6,
      'fl': 2.1,
      'cw': 22.8,
      'process': {'a': 1, 's': 'brew', 'l': 'Brew', 'e': 21000, 'u': 0},
    });
    await tester.pump();

    // Fifth column with the measured value; "Pressure" switches to the short
    // spelling to make room.
    expect(find.text('TEMP'), findsOneWidget);
    // Value and unit are together in one RichText ("92.4 °C").
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '92.4 °C',
      ),
      findsOneWidget,
    );
    expect(find.text('PRESS'), findsOneWidget);
    expect(find.text('PRESSURE'), findsNothing);

    // Four curves instead of three, and the target temperature as a dashed
    // line.
    final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(chart.lineBarsData, hasLength(4));
    expect(chart.extraLinesData.horizontalLines, hasLength(1));

    // The temperature is mapped onto the left axis within its own window
    // (target+5 at the top, target-20 at the bottom): 92.4 °C with target 93
    // lands just below the target line, not at the very top.
    final tempLine = chart.lineBarsData.first;
    final target = chart.extraLinesData.horizontalLines.first.y;
    expect(tempLine.spots.last.y, lessThan(target));
    expect(tempLine.spots.last.y, greaterThan(target - chart.maxY / 5));

    await disposeTree(tester);
  });

  // After the shot, swiping a finger through the curve was caught by the
  // carousel's PageView; only tapping still worked. Both must work: swiping
  // on the chart moves the cursor, the page stays put. Checked on the
  // GaggiMate, because it sends the time per data point itself — in the
  // Meticulous fake all data points are at time 0 (there it comes from the
  // real clock, and no time passes in the test), so no cursor could move.
  testWidgets(
    'live card: swiping over the curve moves the cursor, does not page',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            ChangeNotifierProvider<ShotSetup>.value(
              value: ShotSetup.inMemory(machineKey: 'gaggimate'),
            ),
            ChangeNotifierProvider<GaggiMateService>.value(value: machine),
            ChangeNotifierProvider<EspressoMachine>.value(value: machine),
            ChangeNotifierProvider<LiveShotService>.value(value: live),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  // Below the cards there is also the dots bar.
                  height:
                      ShotCardsCarousel.cardHeight +
                      ShotCardsCarousel.machineExtra +
                      80,
                  width: 340,
                  child: const ShotCardsCarousel(),
                ),
              ),
            ),
          ),
        ),
      );
      answerProfileList();

      // Running brew with data points over eleven seconds.
      for (var ms = 0; ms <= 11000; ms += 1000) {
        transport.receive({
          'tp': 'evt:status',
          'ct': 92.5,
          'tt': 93.0,
          'm': 1,
          'pr': 9.0,
          'fl': 2.0,
          'cw': ms / 500,
          'process': {'a': 1, 's': 'brew', 'l': 'Brew', 'e': ms, 'u': 0},
        });
        await tester.pump();
      }

      // The jump to the live page goes through `LiveShotService.pageJumps`,
      // whose controller was created in setUp — i.e. OUTSIDE the test's
      // FakeAsync zone. Its events therefore sit in the real microtask queue,
      // which `tester.pump()` does not drain: let real time pass once,
      // otherwise the carousel stays on page 0.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      // No pumpAndSettle: a button in the card pulses endlessly.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      double? page() =>
          tester.widget<PageView>(find.byType(PageView)).controller?.page;
      final chart = find.descendant(
        of: find.byType(ShotLiveCard),
        matching: find.byType(LineChart),
      );
      double cursor() => tester
          .widget<LineChart>(chart)
          .data
          .extraLinesData
          .verticalLines
          .first
          .x;

      expect(page(), 1, reason: 'the brew switches to the live page');
      // The profile list response triggers another status run with the same
      // process, so a data point may appear twice — only the last timestamp
      // counts here.
      expect(live.liveReadings.last.timeMs, 11000);
      expect(
        cursor(),
        11.0,
        reason: 'without a cursor it is at the last data point',
      );
      final atEnd = cursor();

      // Swipe left: the cursor snaps to an earlier data point.
      await tester.drag(chart, const Offset(-70, 0));
      await tester.pump(const Duration(milliseconds: 50));
      final left = cursor();
      expect(left, lessThan(atEnd));
      expect(page(), 1, reason: 'a swipe on the chart must not page');

      // And back to the right.
      await tester.drag(chart, const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(cursor(), greaterThan(left));
      expect(page(), 1);

      await disposeTree(tester);
    },
  );
}

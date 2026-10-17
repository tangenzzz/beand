import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/post_shot_card.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/screens/live/tile_title.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

import 'package:beand/widgets/app_button.dart';

// The tests check the default appearance: dark with teal.
final _theme = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  final actions = <String>[];

  @override
  Future<bool> triggerAction(String action) async {
    actions.add(action);
    return true;
  }

  @override
  Future<bool> loadProfile(String id) async {
    actions.add('load:$id');
    return true;
  }

  void phase(String name) {
    latestStatus = MachineStatus.fromJson({
      'name': name,
      'state': name == 'idle' ? 'idle' : 'brewing',
      'extracting': false,
      'sensors': {'p': 0.0, 'f': 0.0, 'w': 0.0, 't': 92.0, 'g': 0.0},
    });
    notifyListeners();
  }
}

// Play through the whole chain once, as it happens on the machine.
void runThroughShot(FakeSocket socket) {
  socket.phase('heating');
  socket.phase('click to start');
  socket.phase('Initial Saturation');
  socket.phase('click to purge');
  socket.phase('purge');
}

void main() {
  // Raise used to make the carousel jump to the Live card. Both manual moves
  // report their own `phase` ('home' or 'purge') but belong to no shot
  // cycle.
  test('Raise from idle does not switch cards', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final jumps = <int>[];
    live.pageJumps.listen(jumps.add);

    socket.phase('idle');
    socket.phase('home');
    expect(live.stage, ShotStage.idle, reason: 'no brew');
    expect(live.activeCard, ActiveCard.pre);
    expect(live.profileLocked, isFalse, reason: 'profile stays selectable');
    socket.phase('idle');

    await Future<void>.delayed(Duration.zero);
    expect(jumps, isEmpty);
  });

  test('Purge from idle does not switch cards', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final jumps = <int>[];
    live.pageJumps.listen(jumps.add);

    socket.phase('idle');
    socket.phase('purge');
    expect(live.stage, ShotStage.idle);
    expect(live.activeCard, ActiveCard.pre, reason: 'not the Post card');
    socket.phase('idle');

    await Future<void>.delayed(Duration.zero);
    expect(jumps, isEmpty);
  });

  // The counter-check: the purge that belongs to a brew still finishes the
  // Live card.
  test('Purge after a brew continues to the Post card', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final jumps = <int>[];
    live.pageJumps.listen(jumps.add);

    runThroughShot(socket);
    expect(live.stage, ShotStage.purging);
    expect(live.activeCard, ActiveCard.post);

    await Future<void>.delayed(Duration.zero);
    expect(jumps, [1, 2]);
  });

  test('active card: PRE -> LIVE -> POST, POST stays until saving', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final jumps = <int>[];
    live.pageJumps.listen(jumps.add);

    expect(live.activeCard, ActiveCard.pre);
    socket.phase('heating');
    expect(live.activeCard, ActiveCard.pre);
    socket.phase('click to start');
    expect(
      live.activeCard,
      ActiveCard.pre,
      reason: 'ready, but not started yet',
    );

    socket.phase('Initial Saturation');
    expect(live.activeCard, ActiveCard.live);
    socket.phase('click to purge');
    expect(live.activeCard, ActiveCard.live, reason: 'until after the purge');

    socket.phase('purge');
    expect(live.activeCard, ActiveCard.post);
    // The machine cleans up — POST still stays.
    socket.phase('finished');
    socket.phase('idle');
    expect(live.activeCard, ActiveCard.post);

    await Future<void>.delayed(Duration.zero);
    expect(jumps, [1, 2]);

    live.confirmPostShot();
    expect(live.activeCard, ActiveCard.pre);
    await Future<void>.delayed(Duration.zero);
    expect(jumps, [1, 2, 0], reason: 'saving jumps back to the Pre-Shot card');
  });

  // Bug 2026-10-17: the next shot was started on the machine before the
  // previous one was saved — then "Save" in the Post-Shot card did nothing.
  // It still has to work and bring the card of the running shot back up.
  test(
    'Save still works after the next shot was started on the machine',
    () async {
      final socket = FakeSocket();
      final live = MeticulousLiveShotService(socket)..start();
      addTearDown(live.dispose);
      final jumps = <int>[];
      live.pageJumps.listen(jumps.add);

      runThroughShot(socket);
      socket.phase('idle');
      expect(live.activeCard, ActiveCard.post);

      // New shot heats up: PRE is the active card again, Post not saved yet.
      socket.phase('heating');
      expect(live.activeCard, ActiveCard.pre);
      expect(live.postShotPending, isTrue);
      await Future<void>.delayed(Duration.zero);
      jumps.clear();

      live.confirmPostShot();
      expect(live.postShotPending, isFalse);
      expect(live.activeCard, ActiveCard.pre);
      await Future<void>.delayed(Duration.zero);
      expect(jumps, [0], reason: 'back to the card of the running shot');

      // Same while the new shot is already extracting: back to LIVE.
      runThroughShot(socket);
      socket.phase('idle');
      socket.phase('heating');
      socket.phase('click to start');
      socket.phase('Initial Saturation');
      expect(live.activeCard, ActiveCard.live);
      await Future<void>.delayed(Duration.zero);
      jumps.clear();
      live.confirmPostShot();
      expect(live.activeCard, ActiveCard.live);
      await Future<void>.delayed(Duration.zero);
      expect(jumps, [1]);
    },
  );

  test('active card: next profile without saving releases PRE again', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    runThroughShot(socket);
    socket.phase('idle');
    expect(live.activeCard, ActiveCard.post);

    socket.phase('heating');
    expect(live.activeCard, ActiveCard.pre);
  });

  test('active card: abort before the purge falls back to PRE', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.phase('heating');
    socket.phase('click to start');
    socket.phase('Initial Saturation');
    expect(live.activeCard, ActiveCard.live);
    socket.phase('idle');
    expect(live.activeCard, ActiveCard.pre, reason: 'no shot to rate');
  });

  test('Auto Start stays checked until unchecked by hand', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    expect(live.autoStartEnabled, false);
    live.setAutoStart(true);
    expect(live.autoStartEnabled, true);
    // A complete shot cycle leaves the checkmark untouched.
    runThroughShot(socket);
    socket.phase('idle');
    expect(live.autoStartEnabled, true);
    // Without stabilization (that would need the 10 s hold time) the app
    // starts nothing on its own.
    expect(socket.actions, isEmpty);

    live.setAutoStart(false);
    expect(live.autoStartEnabled, false);
  });

  Widget wrap(
    AppDatabase db,
    FakeSocket socket,
    LiveShotService live,
    Widget card,
  ) => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
      ChangeNotifierProvider<ShotSetup>.value(value: ShotSetup.inMemory()),
      ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
      // The same machine once more under the shared interface: the
      // Pre-Shot card addresses it through that.
      ChangeNotifierProvider<EspressoMachine>.value(value: socket),
      ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
      ChangeNotifierProvider<LiveShotService>.value(value: live),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            width: 340,
            child: card,
          ),
        ),
      ),
    ),
  );

  // Color the abbreviation is actually painted with (comes via TileTitle's
  // animated DefaultTextStyle).
  Color shortColor(WidgetTester tester, String short) =>
      tester.renderObject<RenderParagraph>(find.text(short)).text.style!.color!;

  testWidgets(
    'Pre Shot: title PREShot, Auto Start checkbox right, Start/Abort in button',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final socket = FakeSocket();
      final live = MeticulousLiveShotService(socket)..start();
      // By hand at the end: the brew is still running, its heartbeat timer
      // must be gone before the test's timer check.

      await tester.pumpWidget(wrap(db, socket, live, const PreShotCard()));
      await tester.pump();

      // Title: abbreviation and word separate, abbreviation smaller and
      // higher.
      expect(find.byType(TileTitle), findsOneWidget);
      expect(find.text('PRE'), findsOneWidget);
      expect(find.text('Shot'), findsOneWidget);
      final pre = tester.getTopLeft(find.text('PRE'));
      final word = tester.getTopLeft(find.text('Shot'));
      expect(
        pre.dx,
        lessThan(word.dx),
        reason: 'abbreviation sits left of the word',
      );
      expect(pre.dy, lessThan(word.dy), reason: 'and higher');
      // Active card at rest is PRE -> accent color.
      expect(shortColor(tester, 'PRE'), _theme.accent);

      // Auto Start: the checkbox toggles the setting in the service.
      expect(find.text('Auto Start'), findsOneWidget);
      expect(live.autoStartEnabled, false);
      // The box is on the right, the label on the left.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('autoStartBox'))).dx,
        greaterThan(tester.getBottomRight(find.text('Auto Start')).dx),
      );
      await tester.tap(find.text('Auto Start'));
      await tester.pump();
      expect(live.autoStartEnabled, true);
      // Checked means a checkmark, not a color change.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Auto Start'))
            .text
            .style!
            .color,
        _theme.textSecondary,
      );

      // Button: start profile, then start the shot manually; Abort sits as a
      // square in the button, there are no swipe gestures anymore.
      expect(find.text('Start Profile'), findsOneWidget);
      expect(find.byTooltip('Abort brew'), findsNothing);
      socket.phase('heating');
      await tester.pump();
      expect(find.textContaining('Heating'), findsOneWidget);
      expect(find.byTooltip('Abort brew'), findsOneWidget);
      // The word stays fixed while the dots come and go (they are always in
      // the layout, only temporarily transparent).
      final wordAt = tester.getTopLeft(find.textContaining('Heating'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 450));
        expect(tester.getTopLeft(find.textContaining('Heating')), wordAt);
      }

      socket.phase('click to start');
      await tester.pump();
      expect(find.text('Start Shot'), findsOneWidget);
      await tester.tap(find.text('Start Shot'));
      await tester.pump();
      expect(socket.actions, ['continue'], reason: 'manual start at the gate');

      socket.phase('Initial Saturation');
      await tester.pump();
      expect(find.text('Shot running'), findsOneWidget);
      // Now LIVE is the active card: PRE is no longer highlighted (the color
      // cross-fades, so let the animation finish).
      await tester.pump(const Duration(milliseconds: 300));
      expect(shortColor(tester, 'PRE'), _theme.textSecondary);

      await tester.tap(find.byTooltip('Abort brew'));
      await tester.pump();
      expect(socket.actions, ['continue', 'stop']);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);

      await tester.pumpWidget(const SizedBox());
      live.dispose();
    },
  );

  testWidgets('Post Shot: Save button switches back to PRE', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    await tester.pumpWidget(wrap(db, socket, live, const PostShotCard()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('POST'), findsOneWidget);
    // Without a shot there is nothing to save.
    expect(find.text('Save'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

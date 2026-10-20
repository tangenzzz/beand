import 'package:beand/database/database.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/grind_scale.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:drift/native.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Grinder scale (unit, step, range) and zero point with its history.

// The Pre-Shot card in the carousel's height must not scroll: when it
// did, the title ("PRE") slipped into the top edge (user report
// 2026-10-20, after the Chain row came in).
void main() {
  for (final markers in [false, true]) {
    testWidgets('Pre Shot card fits without scrolling, markers: $markers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => tester.runAsync(db.close));
      final socket = MeticulousSocketService(hostname: 'unreachable.local');
      final live = MeticulousLiveShotService(socket)..start();
      addTearDown(live.dispose);
      final grinders = GrinderStore.inMemory();
      final m = grinders.add('Monolith', const []);
      grinders.update(
        grinders
            .byId(m.id)!
            .copyWith(
              scale: GrindScale(
                step: 0.1,
                max: 9,
                markers: markers
                    ? const [
                        GrindMarker(name: 'Espresso', color: 0xFF4CAF50),
                        GrindMarker(
                          name: 'Soup',
                          color: 0xFFE53935,
                          offset: 6.8,
                        ),
                        GrindMarker(
                          name: 'Pour over',
                          color: 0xFFFFFFFF,
                          offset: 13.8,
                        ),
                      ]
                    : const [],
              ),
            ),
      );
      final gear = grinders.gear
        ..saveChain(BrewChain(id: '', name: 'Bar', gearIds: [m.id]));
      final setup = ShotSetup.inMemory(grindSize: 4.5)..gear = gear;
      var extra = 0.0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            ChangeNotifierProvider<GearStore>.value(value: gear),
            ChangeNotifierProvider<ShotSetup>.value(value: setup),
            ChangeNotifierProvider<MeticulousSocketService>.value(
              value: socket,
            ),
            ChangeNotifierProvider<EspressoMachine>.value(value: socket),
            ChangeNotifierProvider<GaggiMateService>.value(
              value: offlineGaggiMate(),
            ),
            ChangeNotifierProvider<LiveShotService>.value(value: live),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 380,
                    height:
                        ShotCardsCarousel.cardHeight +
                        ShotCardsCarousel.machineExtra +
                        extra,
                    child: PreShotCard(
                      // The carousel's part: grow by what the open list needs.
                      onExtraHeight: (h) {
                        if (context.mounted) setState(() => extra = h);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      double maxScroll() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      // Otherwise the card scrolls and "PRE" slips into its top edge.
      expect(maxScroll(), 0, reason: 'closed');
      await tester.tap(find.text('Grind'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(maxScroll(), 0, reason: 'grind open');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  }
}

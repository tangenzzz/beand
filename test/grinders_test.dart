import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/screens/settings/grinders_screen.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Settings → My Setup → Grinders: own grinders with several burr sets, one
// of them fitted; chosen per machine next to the grind size; stored on the
// shot as text.
void main() {
  group('GrinderStore', () {
    test('add, fitted burrs, switch, remove', () {
      final store = GrinderStore.inMemory();
      final niche = store.add(' Niche Zero ', ['Stock', ' SSP ', 'stock', '']);
      expect(niche.name, 'Niche Zero');
      // Trimmed, empty and case-duplicates dropped.
      expect(niche.burrs, ['Stock', 'SSP']);
      // Without a choice the first burr set counts as fitted.
      expect(niche.activeBurrs, 'Stock');

      store.setActiveBurr(niche.id, 'SSP');
      expect(store.byId(niche.id)!.activeBurrs, 'SSP');
      // Unknown burrs are ignored.
      store.setActiveBurr(niche.id, 'Mazzer');
      expect(store.byId(niche.id)!.activeBurrs, 'SSP');

      store.add('K-Ultra', ['Stock']);
      expect(store.burrSuggestions, ['Stock', 'SSP']);

      store.remove(niche.id);
      expect(store.grinders.map((g) => g.name), ['K-Ultra']);
    });

    test('JSON round trip; foreign entries are skipped', () {
      const g = Grinder(
        id: 'a',
        name: 'Niche Zero',
        burrs: ['Stock', 'SSP'],
        activeBurr: 'SSP',
      );
      final decoded = GrinderStore.decode(
        '[${'{"id":"a","name":"Niche Zero","burrs":["Stock","SSP"],"active":"SSP"}'},'
        '{"name":"no id"}, 42]',
      );
      expect(decoded, [g]);
      expect(Grinder.fromJson(g.toJson()), g);
      expect(GrinderStore.decode('not json'), isEmpty);
    });

    test('the list travels with the synced settings', () {
      expect(syncedSettingKeys(), contains(GrinderStore.prefKey));
    });
  });

  group('ShotSetup', () {
    test('snapshot carries grinder name and fitted burrs', () {
      final store = GrinderStore.inMemory();
      final setup = ShotSetup.inMemory()..grinders = store;
      expect(setup.snapshot().grinder, isNull);

      // Exactly one grinder counts as chosen.
      final niche = store.add('Niche Zero', ['Stock', 'SSP']);
      expect(setup.snapshot().grinder, 'Niche Zero');
      expect(setup.snapshot().burrs, 'Stock');

      final k = store.add('K-Ultra', const []);
      expect(setup.grinder, isNull, reason: 'two grinders, none chosen');
      setup.setGrinder(niche.id);
      store.setActiveBurr(niche.id, 'SSP');
      expect(setup.snapshot().grinder, 'Niche Zero');
      expect(setup.snapshot().burrs, 'SSP');

      setup.setGrinder(k.id);
      expect(setup.snapshot().burrs, isNull);
      // Deleted grinder: nothing on the shot instead of a stale name.
      store.remove(k.id);
      expect(setup.snapshot().grinder, 'Niche Zero');
    });
  });

  testWidgets('Grinders page: add with two burr sets, tick to switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GrinderStore.inMemory();
    await tester.pumpWidget(
      ChangeNotifierProvider<GrinderStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const GrindersScreen(),
        ),
      ),
    );
    expect(find.text('No grinders yet. Tap + to add yours.'), findsOneWidget);

    await tester.tap(find.byTooltip('Add grinder'));
    await tester.pumpAndSettle();
    expect(find.text('Add grinder'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('grinder-name')),
      'Niche Zero',
    );
    await tester.enterText(
      find.byKey(const ValueKey('grinder-burrs-0')),
      'Stock',
    );
    await tester.tap(find.text('Add burrs'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('grinder-burrs-1')),
      'SSP',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.grinders.single.burrs, ['Stock', 'SSP']);
    // One card: the grinder with both burr sets, the first one ticked.
    expect(find.text('Niche Zero'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('SSP'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('SSP'));
    await tester.pump();
    expect(store.grinders.single.activeBurrs, 'SSP');

    // Edit → delete at the bottom of the dialog.
    await tester.tap(find.text('Niche Zero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete grinder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.grinders, isEmpty);
  });

  testWidgets('Pre Shot: grinder pill next to the grind size picks one', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final socket = MeticulousSocketService(hostname: 'unreachable.local');
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final store = GrinderStore.inMemory();
    store.add('Niche Zero', ['SSP']);
    final k = store.add('K-Ultra', const []);
    final setup = ShotSetup.inMemory()..grinders = store;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<GrinderStore>.value(value: store),
          ChangeNotifierProvider<ShotSetup>.value(value: setup),
          ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
          ChangeNotifierProvider<EspressoMachine>.value(value: socket),
          ChangeNotifierProvider<GaggiMateService>.value(
            value: offlineGaggiMate(),
          ),
          ChangeNotifierProvider<LiveShotService>.value(value: live),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: ShotCardsCarousel.cardHeight + 300,
                width: 340,
                child: const PreShotCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Two grinders, none chosen yet.
    expect(find.text('Grinder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('grinder-pill')));
    await tester.pump();
    expect(find.text('K-Ultra'), findsOneWidget);
    // Fitted burrs as detail in the list.
    expect(find.textContaining('SSP', findRichText: true), findsOneWidget);
    await tester.tap(find.text('K-Ultra'));
    await tester.pump();
    expect(setup.grinder?.id, k.id);
    // List closed, the pill names the grinder.
    expect(find.text('K-Ultra'), findsOneWidget);
    expect(find.text('Niche Zero'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/models/water.dart';
import 'package:beand/screens/settings/my_setup_screen.dart';
import 'package:beand/screens/settings/settings_widgets.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/services/water_store.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/dot_choice_group.dart';
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

    test('mineral factors: g/L ↔ ppm as CaCO₃', () {
      // 1 ppm GH from Epsom salt = 2.4627 mg/L (246.47 / 100.09).
      expect(
        Mineral.epsomSalt.ppmFromGramsPerLitre(0.0024627),
        closeTo(1, 1e-6),
      );
      expect(
        Mineral.bakingSoda.gramsPerLitreFromPpm(40),
        closeTo(0.0671, 1e-4),
      );
      expect(Mineral.forGh, hasLength(3));
      expect(Mineral.forKh, hasLength(3));
    });

    test('grinders and waters travel with the synced settings', () {
      expect(syncedSettingKeys(), contains(GrinderStore.prefKey));
      expect(syncedSettingKeys(), contains(WaterStore.prefKey));
    });

    test('brand is optional and round-trips', () {
      final store = GrinderStore.inMemory();
      final g = store.add('Zero', const [], brand: ' Niche ');
      expect(g.brand, 'Niche');
      expect(Grinder.fromJson(g.toJson()), g);
      expect(store.add('K-Ultra', const [], brand: '  ').brand, isNull);
      expect(store.brandSuggestions, ['Niche']);
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

  Widget mySetup(GrinderStore grinders, WaterStore waters) => MultiProvider(
    providers: [
      ChangeNotifierProvider<GrinderStore>.value(value: grinders),
      ChangeNotifierProvider<WaterStore>.value(value: waters),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: const MySetupScreen()),
  );

  testWidgets('My Setup: add a grinder with two burr sets, tick to switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GrinderStore.inMemory();
    await tester.pumpWidget(mySetup(store, WaterStore.inMemory()));
    // Both sections in the one card, each with its own "+".
    expect(find.text('GRINDERS'), findsOneWidget);
    expect(find.text('WATER'), findsOneWidget);
    expect(
      find.text('Add your grinder to see it on every shot.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Add grinder'));
    await tester.pumpAndSettle();
    expect(find.text('Add grinder'), findsOneWidget);
    // Neutral label and line, but the blinking cursor in the accent color.
    final brandField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('grinder-brand')),
        matching: find.byType(TextField),
      ),
    );
    expect(
      brandField.cursorColor,
      buildAppTheme().extension<AppColors>()!.accent,
    );
    await tester.enterText(
      find.byKey(const ValueKey('grinder-brand')),
      'Niche',
    );
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
    expect(store.grinders.single.brand, 'Niche');
    // Only one divider: between Grinders and Water, not between entries.
    expect(find.byType(SettingsDivider), findsOneWidget);
    // One card: the grinder with both burr sets, the first one ticked.
    expect(
      find.textContaining('Niche Zero', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('SSP'), findsOneWidget);
    bool fitted(String burr) => tester
        .widget<DotChoiceItem>(
          find.ancestor(
            of: find.text(burr),
            matching: find.byType(DotChoiceItem),
          ),
        )
        .selected;
    expect(fitted('Stock'), isTrue);
    expect(fitted('SSP'), isFalse);

    await tester.tap(find.text('SSP'));
    await tester.pump();
    expect(store.grinders.single.activeBurrs, 'SSP');
    expect(fitted('SSP'), isTrue);

    // Edit → delete at the bottom of the dialog.
    await tester.tap(find.textContaining('Niche Zero', findRichText: true));
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

  testWidgets('My Setup: add a water recipe', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final waters = WaterStore.inMemory();
    await tester.pumpWidget(mySetup(GrinderStore.inMemory(), waters));
    expect(
      find.text('Add a water recipe to keep its minerals.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Add water'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('water-recipe')), 'Lotus');
    await tester.enterText(find.byKey(const ValueKey('water-gh')), '68');
    // Fixed minerals instead of free text; GH from two of them.
    await tester.tap(find.text('Epsom salt'));
    await tester.tap(find.text('Calcium chloride'));
    await tester.enterText(find.byKey(const ValueKey('water-kh')), '40,5');
    await tester.tap(find.text('Baking soda'));
    await tester.pump();
    // Amount per ticked mineral, entered in g/L …
    await tester.enterText(
      find.byKey(const ValueKey('water-amount-epsomSalt')),
      '0,12',
    );
    // … and shown converted after switching to ppm (0.12 g/L Epsom salt =
    // 48.7 ppm as CaCO₃).
    await tester.tap(find.text('ppm').first);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('water-amount-epsomSalt')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '48.7',
    );
    await tester.enterText(find.byKey(const ValueKey('water-ppm')), '150');
    await tester.tap(find.text('Pour Over'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final w = waters.waters.single;
    expect(w.recipe, 'Lotus');
    expect(w.gh, 68);
    expect(w.ghMinerals, {Mineral.epsomSalt, Mineral.calciumChloride});
    expect(w.kh, 40.5);
    expect(w.khMinerals, {Mineral.bakingSoda});
    expect(w.unit, MineralUnit.ppm);
    expect(w.amounts[Mineral.epsomSalt], closeTo(0.12, 0.001));
    expect(w.amounts.containsKey(Mineral.bakingSoda), isFalse);
    expect(w.ppm, 150);
    expect(w.use, WaterUse.pourOver);
    expect(Water.fromJson(w.toJson()), w);
    // No bars: per GH/KH the value and what it is made of, in grams of
    // each mineral; the use at the right of the title.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('68 ppm'), findsOneWidget);
    expect(find.text('40.5 ppm'), findsOneWidget);
    expect(find.text('Epsom salt 0.12 g · Calcium chloride'), findsOneWidget);
    expect(find.text('Baking soda'), findsOneWidget);
    expect(find.text('Pour Over'), findsOneWidget);
  });

  // Bug 2026-10-18: adding a grinder only worked with burrs that already
  // existed, and the app hung afterwards. Typing new burrs whose start
  // matches an earlier entry must work too.
  testWidgets('My Setup: new burrs next to suggestions, then save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GrinderStore.inMemory();
    store.add('Zero', ['SSP', 'Stock'], brand: 'Niche');
    await tester.pumpWidget(mySetup(store, WaterStore.inMemory()));

    await tester.tap(find.byTooltip('Add grinder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('grinder-brand')), 'Ni');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The suggestion chip fills the field.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Niche'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('grinder-brand')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Niche',
    );
    await tester.enterText(find.byKey(const ValueKey('grinder-name')), 'Duo');
    await tester.enterText(find.byKey(const ValueKey('grinder-burrs-0')), 'S');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('grinder-burrs-0')),
      'Shura',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(store.grinders.map((g) => g.name), ['Zero', 'Duo']);
    expect(store.grinders.last.burrs, ['Shura']);
  });
}

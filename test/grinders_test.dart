import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/models/water.dart';
import 'package:beand/screens/settings/desk_filter.dart';
import 'package:beand/screens/settings/my_coffee_desk_screen.dart';
import 'package:beand/screens/settings/settings_widgets.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/services/water_store.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/underline_select.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      // My Setup's old setting moves into the gear store, IDs kept.
      final gear = GearStore.inMemory()
        ..migrateLegacy(
          grinders:
              '[${'{"id":"a","name":"Niche Zero","burrs":["Stock","SSP"],"active":"SSP"}'},'
              '{"name":"no id"}, 42]',
          waters: 'not json',
        );
      expect(GrinderStore(gear).grinders, [g]);
      expect(Grinder.fromJson(g.toJson()), g);
      expect(grinderFromGear(gearFromGrinder(g)), g);
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

    test('first start moves My Setup into the gear store, IDs kept', () async {
      SharedPreferences.setMockInitialValues({
        GearStore.legacyGrinderKey:
            '[{"id":"g1","name":"Zero","burrs":["SSP"],"active":"SSP"}]',
        GearStore.legacyWaterKey: '[{"id":"w1","recipe":"Lotus","gh":68}]',
      });
      final gear = await GearStore.load();
      expect(GrinderStore(gear).byId('g1')?.activeBurrs, 'SSP');
      expect(WaterStore(gear).byId('w1')?.gh, 68);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(GearStore.legacyGrinderKey), isNull);
      expect(GearStore.decodeGear(prefs.getString(GearStore.gearPrefKey)), [
        ...gear.gear,
      ]);
      // A second start finds nothing to move and keeps the gear.
      expect((await GearStore.load()).gear, hasLength(2));
    });

    test('grinders and waters travel with the synced settings', () {
      expect(syncedSettingKeys(), contains(GearStore.gearPrefKey));
      expect(syncedSettingKeys(), contains(GearStore.chainsPrefKey));
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

  Widget mySetup(GearStore gear) => MultiProvider(
    providers: [
      ChangeNotifierProvider<GearStore>.value(value: gear),
      ChangeNotifierProvider<GrinderStore>(create: (_) => GrinderStore(gear)),
      ChangeNotifierProvider<WaterStore>(create: (_) => WaterStore(gear)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const MyCoffeeDeskScreen(),
    ),
  );

  testWidgets('My Setup: add a grinder with two burr sets, tick to switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GrinderStore.inMemory();
    await tester.pumpWidget(mySetup(store.gear));
    // Shelves in the one card; Grinders and Water have their own "+".
    expect(find.textContaining('GRINDERS', findRichText: true), findsOneWidget);
    expect(find.textContaining('WATER', findRichText: true), findsOneWidget);

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
    // The new grinder stands on the shelf; a tap folds out its detail,
    // where the fitted burr set is picked.
    await tester.tap(find.text('Niche Zero'));
    await tester.pumpAndSettle();
    expect(find.text('Niche Zero'), findsNWidgets(2), reason: 'label + title');
    bool fitted(String burr) => tester
        .widget<UnderlineItem>(
          find.ancestor(
            of: find.text(burr),
            matching: find.byType(UnderlineItem),
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
    await tester.tap(find.text('Edit'));
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
    await tester.pumpWidget(mySetup(waters.gear));

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
    // The detail lists GH, KH, what the water is made of and its use.
    await tester.tap(find.text('Lotus'));
    await tester.pumpAndSettle();
    expect(find.text('68 ppm'), findsOneWidget);
    expect(find.text('40.5 ppm'), findsOneWidget);
    expect(
      find.text('Epsom salt, Calcium chloride, Baking soda'),
      findsOneWidget,
    );
  });

  testWidgets('My Coffee Desk: chain tabs, search and filter', (tester) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory(
      gear: const [
        Gear(
          id: 'm',
          type: GearType.machine,
          brand: 'Meticulous',
          model: 'Meticulous',
          brewModes: {BrewMode.espresso},
        ),
        Gear(
          id: 'v60',
          type: GearType.brewer,
          brand: 'Hario',
          model: 'V60 02',
          brewModes: {BrewMode.pourOver},
        ),
      ],
    );
    await tester.pumpWidget(mySetup(gear));
    // "All" shows every category, empty ones too (just "New"), and no
    // hairlines between the shelves.
    expect(find.textContaining('KETTLES', findRichText: true), findsOneWidget);
    expect(find.byType(SettingsDivider), findsNothing);

    // "+" next to the tabs adds a chain, which opens as its own tab.
    await tester.tap(find.byTooltip('Add brew chain'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chain-name')),
      'Espresso bar',
    );
    await tester.tap(find.byKey(const ValueKey('chain-gear-m')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gear.chains.single.gearIds, ['m']);
    expect(gear.activeIds, {'m'});
    expect(find.text('Meticulous'), findsOneWidget);
    expect(find.text('V60 02'), findsNothing, reason: 'not in the chain');
    expect(find.textContaining('KETTLES', findRichText: true), findsNothing);

    // Adding on the chain's tab puts the new piece into the chain.
    await tester.tap(find.byTooltip('Add machine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gear-model')), 'Gaggia');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gear.chains.single.gearIds, hasLength(2));

    // Tapping the open tab again edits the chain.
    await tester.tap(find.text('Espresso bar'));
    await tester.pumpAndSettle();
    expect(find.text('Edit brew chain'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back on All: the filter sheet narrows to what is stored.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stored'));
    await tester.pump();
    expect(find.text('Show 1 piece'), findsOneWidget);
    await tester.tap(find.text('Show 1 piece'));
    await tester.pumpAndSettle();
    expect(find.text('V60 02'), findsOneWidget);
    expect(find.text('Meticulous'), findsNothing);

    // Search goes over brand and model.
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'meti');
    await tester.pumpAndSettle();
    expect(find.text('V60 02'), findsNothing, reason: 'stored, but no match');
    expect(find.text('Nothing here.'), findsOneWidget);

    // Deleting gear takes it out of its chains.
    gear.remove('m');
    expect(gear.chains.single.gearIds, hasLength(1));
  });

  test('desk search matches brand, model and type fields', () {
    const g = Gear(
      id: 'b',
      type: GearType.basket,
      brand: 'IMS',
      model: 'Precision 18',
      specs: {'size': '58 mm'},
    );
    expect(matchesDeskQuery(g, 'ims 58'), isTrue);
    expect(matchesDeskQuery(g, 'basket'), isTrue);
    expect(matchesDeskQuery(g, 'vst'), isFalse);
    const f = DeskFilter(modes: {BrewMode.pourOver});
    expect(f.matches(g, inUse: false), isTrue, reason: 'both modes');
    expect(
      const DeskFilter(status: {DeskStatus.inUse}).matches(g, inUse: false),
      isFalse,
    );
  });

  testWidgets('My Coffee Desk: add a basket with the gear form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory();
    await tester.pumpWidget(mySetup(gear));

    await tester.tap(find.byTooltip('Add basket'));
    await tester.pumpAndSettle();
    expect(find.text('Add basket'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('gear-brand')), 'IMS');
    await tester.enterText(
      find.byKey(const ValueKey('gear-model')),
      'Precision 18',
    );
    await tester.enterText(find.byKey(const ValueKey('gear-dose')), '18');
    await tester.enterText(find.byKey(const ValueKey('gear-size')), '58 mm');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final basket = gear.ofType(GearType.basket).single;
    expect(basket.brand, 'IMS');
    expect(basket.specs, {'dose': 18.0, 'size': '58 mm'});
    // A basket is for espresso unless the user says otherwise.
    expect(basket.brewModes, {BrewMode.espresso});
    expect(Gear.fromJson(basket.toJson()), basket);

    await tester.tap(find.text('Precision 18'));
    await tester.pumpAndSettle();
    expect(find.text('18 g'), findsOneWidget);
    expect(find.text('58 mm'), findsOneWidget);
  });

  test('grinder and water saved through their stores keep desk facts', () {
    final gear = GearStore.inMemory();
    final grinders = GrinderStore(gear);
    final waters = WaterStore(gear);
    final niche = grinders.add('Zero', ['Stock', 'SSP'], brand: 'Niche');
    // A photo set on the desk survives an edit in the grinder dialog.
    gear.save(gear.byId(niche.id)!.copyWith(photoPath: 'gear_photos/a.jpg'));
    grinders.update(niche.copyWith(name: 'Zero 2'));
    expect(gear.byId(niche.id)!.photoPath, 'gear_photos/a.jpg');
    expect(grinders.byId(niche.id)!.name, 'Zero 2');

    final lotus = waters.save(
      const Water(id: '', recipe: 'Lotus', gh: 68, use: WaterUse.espresso),
    );
    expect(gear.byId(lotus.id)!.brewModes, {BrewMode.espresso});
    // A cleared value doesn't linger in the specs.
    waters.save(Water(id: lotus.id, recipe: 'Lotus'));
    expect(waters.byId(lotus.id)!.gh, isNull);
    expect(waters.byId(lotus.id), Water(id: lotus.id, recipe: 'Lotus'));
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
    await tester.pumpWidget(mySetup(store.gear));

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

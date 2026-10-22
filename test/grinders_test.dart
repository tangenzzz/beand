import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/models/water.dart';
import 'package:beand/screens/settings/desk_filter.dart';
import 'package:beand/screens/settings/gear_photo_preview.dart';
import 'package:beand/screens/settings/my_coffee_desk_screen.dart';
import 'package:beand/screens/settings/my_setup_dialogs.dart';
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

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:image/image.dart' as img;
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
    test('snapshot: grinder, burrs and gear of the chain in desk order', () {
      final grinders = GrinderStore.inMemory();
      final gear = grinders.gear;
      final setup = ShotSetup.inMemory()..gear = gear;
      expect(setup.snapshot().grinder, isNull);
      expect(setup.snapshot().brewedWith, isNull);

      final niche = grinders.add('Zero', ['Stock', 'SSP'], brand: 'Niche');
      gear.save(
        const Gear(
          id: 'm',
          type: GearType.machine,
          brand: 'Meticulous',
          model: 'Meticulous',
        ),
      );
      gear.save(
        const Gear(id: 'b', type: GearType.basket, brand: 'IMS', model: '18'),
      );
      // Chain lists the basket first — the shot gets desk order: machine,
      // grinder, basket.
      final bar = gear.saveChain(
        BrewChain(id: '', name: 'Bar', gearIds: ['b', niche.id, 'm']),
      );
      // Exactly one chain counts as chosen.
      expect(setup.chain?.id, bar.id);
      expect(setup.snapshot().grinder, 'Zero');
      expect(setup.snapshot().burrs, 'Stock');
      expect(
        setup.snapshot().brewedWith,
        'Meticulous Meticulous\nNiche Zero (Stock)\nIMS 18',
      );

      final travel = gear.saveChain(
        const BrewChain(id: '', name: 'Travel', gearIds: ['b']),
      );
      expect(setup.chain, isNull, reason: 'two chains, none chosen');
      setup.setChain(bar.id);
      grinders.setActiveBurr(niche.id, 'SSP');
      expect(setup.snapshot().burrs, 'SSP');

      setup.setChain(travel.id);
      expect(setup.snapshot().grinder, isNull, reason: 'no grinder in it');
      expect(setup.snapshot().brewedWith, 'IMS 18');
      // Deleted chain: the one left counts again.
      gear.removeChain(travel.id);
      expect(setup.chain?.id, bar.id);
    });
  });

  test('each machine starts with the chain of its last shot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final gear = GearStore.inMemory(
      chains: const [
        BrewChain(id: 'bar', name: 'Bar', gearIds: []),
        BrewChain(id: 'gag', name: 'Gaggia', gearIds: []),
        BrewChain(id: 'po', name: 'V60', gearIds: []),
      ],
    );
    Future<void> shot(String machine, String? chain, int day) => db
        .into(db.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, day),
            machine: Value(machine),
            brewChainId: Value(chain),
          ),
        );
    await shot('meticulous', 'gag', 1);
    await shot('meticulous', 'bar', 2);
    // The newest one names none: the one before counts.
    await shot('meticulous', null, 3);
    await shot('gaggimate', 'gag', 2);
    await shot('pourover', 'po', 2);
    // A chain deleted since is left alone.
    await shot('pourover', 'gone', 3);

    final meticulous = ShotSetup.inMemory()..gear = gear;
    final gaggimate = ShotSetup.inMemory(machineKey: 'gaggimate')..gear = gear;
    final pourOver = ShotSetup.inMemory(machineKey: 'pourover')..gear = gear;
    await meticulous.restoreFromLastShot(db);
    await gaggimate.restoreFromLastShot(db);
    await pourOver.restoreChainFromLastShot(db);
    expect(meticulous.chain?.id, 'bar');
    expect(gaggimate.chain?.id, 'gag');
    expect(pourOver.chain?.id, 'po');
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
    // Shelves in the one card; each ends in a dashed "New".
    expect(find.textContaining('GRINDERS', findRichText: true), findsOneWidget);
    expect(find.textContaining('WATER', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-grinder')));
    await tester.pumpAndSettle();
    // A new piece without brand and name: the head shows only its kind.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dialog-heading')),
        matching: find.text('Grinder'),
      ),
      findsOneWidget,
    );
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
    await tester.tap(find.byKey(const ValueKey('avatar-Niche Zero')));
    await tester.pumpAndSettle();
    // No name under the shelf board any more, only the detail's title.
    expect(find.text('Niche Zero'), findsOneWidget);
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

    // No Edit button in the detail any more: a long press on the piece
    // opens its dialog, with "Photo" at the top and delete at the bottom.
    expect(find.text('Edit'), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('avatar-Niche Zero')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialog-photo')), findsOneWidget);
    await tester.tap(find.text('Delete grinder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.grinders, isEmpty);
  });

  testWidgets('Pre Shot: brew chain row below the grind picks one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final socket = MeticulousSocketService(hostname: 'unreachable.local');
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final gear = GearStore.inMemory(
      gear: const [
        Gear(id: 'g', type: GearType.grinder, model: 'Zero'),
        Gear(id: 'v', type: GearType.brewer, model: 'V60'),
      ],
      chains: const [
        BrewChain(id: 'bar', name: 'Espresso bar', gearIds: ['g']),
        BrewChain(id: 'po', name: 'Pour over', gearIds: ['g', 'v']),
      ],
    );
    final setup = ShotSetup.inMemory()..gear = gear;
    var extra = 0.0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<GearStore>.value(value: gear),
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
          // Grows by the open list's height like the carousel does.
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SizedBox(
                  height: ShotCardsCarousel.cardHeight + extra,
                  width: 340,
                  child: PreShotCard(
                    onExtraHeight: (h) => setState(() => extra = h),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No grinder choice at the grind row any more; the chain row below it.
    expect(find.byKey(const ValueKey('grinder-pill')), findsNothing);
    expect(find.text('Chain'), findsOneWidget);
    expect(find.text('Select brew chain'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chain')).dy,
      greaterThan(tester.getTopLeft(find.text('Grind')).dy),
    );
    await tester.tap(find.text('Select brew chain'));
    await tester.pump();
    // The list folds open in 200 ms.
    await tester.pump(const Duration(milliseconds: 300));
    // Each chain with its pieces as detail.
    expect(find.text('V60, Zero'), findsOneWidget, reason: 'desk order');
    await tester.tap(find.text('Pour over'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(setup.chain?.id, 'po');
    expect(setup.snapshot().brewedWith, 'V60\nZero');
    expect(extra, 0, reason: 'list closed, the card shrinks back');
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('Shot detail: brewed with, small, pieces in one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: BrewedWith(gear: 'Niche Zero (SSP)\nMeticulous\nIMS 18'),
        ),
      ),
    );
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('shot-brewed-with')),
    );
    expect(
      text.textSpan!.toPlainText(),
      'BREWED WITH  Niche Zero (SSP)  ·  Meticulous  ·  IMS 18',
    );
    expect(text.maxLines, 2);
  });

  testWidgets('My Setup: add a water recipe', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final waters = WaterStore.inMemory();
    await tester.pumpWidget(mySetup(waters.gear));

    await tester.tap(find.byKey(const ValueKey('new-water')));
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
    // What the water is for is no longer asked.
    expect(find.text('Pour Over'), findsNothing);
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
    expect(w.use, isNull);
    expect(Water.fromJson(w.toJson()), w);
    // The detail lists GH, KH, what the water is made of and its use.
    await tester.tap(find.byKey(const ValueKey('avatar-Lotus')));
    await tester.pumpAndSettle();
    expect(find.text('68 ppm'), findsOneWidget);
    expect(find.text('40.5 ppm'), findsOneWidget);
    expect(
      find.text('Epsom salt, Calcium chloride, Baking soda'),
      findsOneWidget,
    );
  });

  testWidgets('My Coffee Desk: Shelf and Brew chains tabs, one per kind', (
    tester,
  ) async {
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
        Gear(id: 'b1', type: GearType.basket, brand: 'IMS', model: 'IMS 18'),
        Gear(id: 'b2', type: GearType.basket, brand: 'VST', model: 'VST 20'),
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
    // Shelf: every category, empty ones too (just "New"); one hairline
    // below the tabs, none between the shelves; machines first.
    expect(find.text('Shelf'), findsOneWidget);
    expect(find.textContaining('KETTLES', findRichText: true), findsOneWidget);
    expect(find.byType(SettingsDivider), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('MACHINES', findRichText: true)).dy,
      lessThan(
        tester
            .getTopLeft(find.textContaining('GRINDERS', findRichText: true))
            .dy,
      ),
    );
    expect(find.byTooltip('Add brew chain'), findsNothing);

    // Brew chains tab: "+" adds one; one piece per category.
    await tester.tap(find.text('Brew chains'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Filter'), findsNothing, reason: 'gear only');
    await tester.tap(find.byTooltip('Add brew chain'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chain-name')),
      'Espresso bar',
    );
    await tester.tap(find.text('Meticulous').last);
    await tester.tap(find.text('IMS 18'));
    await tester.pump();
    // Another basket replaces the first one.
    await tester.tap(find.text('VST 20'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gear.chains.single.gearIds, ['m', 'b2']);
    expect(gear.activeIds, {'m', 'b2'});
    // The chain as a shelf of its own: its pieces stand on a board.
    final bar = find.text('ESPRESSO BAR');
    expect(bar, findsOneWidget);
    final row = find.byKey(ValueKey('chain-${gear.chains.single.id}'));
    expect(
      find.descendant(of: row, matching: find.byType(GearAvatar)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('avatar-VST 20')),
      ),
      findsOneWidget,
    );

    // The name sits on the plate below the board; tapping it opens the
    // chain, Copy at the bottom makes a second one and opens it to change
    // one category.
    expect(bar, findsOneWidget);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy brew chain'));
    await tester.tap(find.text('Copy brew chain'));
    await tester.pumpAndSettle();
    expect(find.byType(SetupDialog), findsOneWidget);
    await tester.tap(find.text('IMS 18'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gear.chains, hasLength(2));
    expect(gear.chains.last.name, 'Espresso bar copy');
    expect(gear.chains.last.gearIds, ['m', 'b1']);

    // Delete from the chain's sheet, after asking.
    await tester.tap(
      find.textContaining('ESPRESSO BAR COPY', findRichText: true),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete brew chain'));
    await tester.tap(find.text('Delete brew chain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(gear.chains, hasLength(1));

    // Back on the shelf the filter narrows to what is stored.
    await tester.tap(find.text('Shelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stored'));
    await tester.pump();
    await tester.tap(find.text('Show 2 pieces'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-V60 02')), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar-IMS 18')), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar-VST 20')), findsNothing);

    // Deleting gear takes it out of its chains.
    gear.remove('m');
    expect(gear.chains.single.gearIds, ['b2']);
  });

  testWidgets('My Coffee Desk: no name needed, long press edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory();
    await tester.pumpWidget(mySetup(gear));

    await tester.tap(find.byKey(const ValueKey('new-machine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final machine = gear.ofType(GearType.machine).single;
    expect(machine.model, '');
    expect(machine.label, 'Machine');
    // On the shelf under its kind's name.
    final avatar = find.byKey(ValueKey('avatar-${machine.displayName}'));
    expect(avatar, findsOneWidget);

    await tester.longPress(avatar);
    await tester.pumpAndSettle();
    // No "Edit …" in the head: without brand and model just its kind.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dialog-heading')),
        matching: find.text('Machine'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('My Coffee Desk: a cut-out stands on the shelf, no circle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final docs = Directory.systemTemp.createTempSync('desk_cutout');
    addTearDown(() => docs.deleteSync(recursive: true));
    Directory('${docs.path}/gear_photos').createSync();
    File('${docs.path}/gear_photos/a_cut.png').writeAsBytesSync(
      img.encodePng(img.Image(width: 8, height: 8, numChannels: 4)),
    );
    final gear = GearStore.inMemory(
      docsPath: docs.path,
      gear: const [
        Gear(
          id: 'm',
          type: GearType.machine,
          model: 'Meticulous',
          photoPath: 'gear_photos/a_cut.png',
          photoOriginalPath: 'gear_photos/a.jpg',
        ),
      ],
      chains: const [
        BrewChain(id: 'c', name: 'Bar', gearIds: ['m']),
      ],
    );
    await tester.pumpWidget(mySetup(gear));
    expect(find.byType(StandingImage), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    // In use, but no mark under the board (user request 2026-10-20).
    expect(find.byKey(const ValueKey('in-use-dot')), findsNothing);
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
    // In use follows from being in a chain; an old "put away" flag is
    // ignored.
    final old = BrewChain.fromJson({
      'id': 'c',
      'name': 'Travel',
      'gear': ['b'],
      'active': false,
    })!;
    expect(activeGearIds([old]), {'b'});
    expect(old.toJson().containsKey('active'), isFalse);
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

    await tester.tap(find.byKey(const ValueKey('new-basket')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dialog-heading')),
        matching: find.text('Basket'),
      ),
      findsOneWidget,
    );
    // What it serves follows the kind; the form doesn't ask.
    expect(find.text('Both'), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey('avatar-Precision 18')));
    await tester.pumpAndSettle();
    expect(find.text('18 g'), findsOneWidget);
    // Brand and model in the look of the card titles: brand small, in
    // capitals, before the model.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gear-title')),
        matching: find.text('IMS'),
      ),
      findsOneWidget,
    );
    expect(find.text('58 mm'), findsOneWidget);
  });

  testWidgets('My Coffee Desk: a photo while adding saves the piece first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory();
    await tester.pumpWidget(mySetup(gear));

    await tester.tap(find.byKey(const ValueKey('new-basket')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gear-model')), 'VST');
    // The photo is there before the piece exists (user 2026-10-22).
    await tester.tap(find.byKey(const ValueKey('dialog-photo')));
    await tester.pumpAndSettle();
    expect(gear.ofType(GearType.basket).single.model, 'VST');
    expect(find.text('Take photo'), findsOneWidget);
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();

    // Saving afterwards keeps one piece, with what came after the photo.
    await tester.enterText(find.byKey(const ValueKey('gear-brand')), 'VST');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final basket = gear.ofType(GearType.basket).single;
    expect(basket.brand, 'VST');
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

    await tester.tap(find.byKey(const ValueKey('new-grinder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('grinder-brand')), 'Ni');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The suggestion chip fills the field.
    await tester.tap(
      find.descendant(
        of: find.byType(SetupDialog),
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

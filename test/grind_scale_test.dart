import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/grind_scale.dart';
import 'package:beand/screens/live/grind_panel.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:drift/native.dart';
import 'package:beand/models/grinder.dart';
import 'package:beand/screens/settings/my_coffee_desk_screen.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/services/water_store.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Grinder scale (unit, step, range) and zero point with its history.
void main() {
  group('GrindScale', () {
    test('formats per unit, decimals from the step', () {
      const dial = GrindScale(step: 0.25, max: 50);
      expect(dial.digits, 2);
      expect(dial.format(12.5), '12.50');
      const half = GrindScale(step: 0.5, max: 50);
      expect(half.format(12.5), '12.5');
      const microns = GrindScale(unit: GrindUnit.microns, step: 10, max: 1500);
      expect(microns.format(450), '450 µm');
      expect(microns.format(450, withUnit: false), '450');
      const clicks = GrindScale(unit: GrindUnit.clicks, step: 1, max: 40);
      expect(clicks.format(24), '24 clicks');
      const rotations = GrindScale(
        unit: GrindUnit.rotations,
        step: 1,
        max: 120,
        clicksPerRotation: 30,
      );
      expect(rotations.format(74), '2.14');
    });

    test('range may start below zero; JSON round trip; nonsense dropped', () {
      const s = GrindScale(step: 0.5, min: -5, max: 50);
      expect(s.clamp(-9), -5);
      expect(s.clamp(60), 50);
      expect(GrindScale.fromJson(s.toJson()), s);
      expect(
        GrindScale.fromJson({'unit': 'dial', 'step': 1, 'min': 5, 'max': 5}),
        isNull,
      );
      expect(GrindScale.fromJson({'unit': 'parsecs'}), isNull);
    });
  });

  group('markers (Kafatek Monolith)', () {
    // Red 2.2 = green 9.0, red 9.0 = white 2.0 (read off the grinder).
    const green = GrindMarker(name: 'Espresso', color: 0xFF4CAF50);
    const red = GrindMarker(name: 'Soup', color: 0xFFE53935, offset: 6.8);
    const white = GrindMarker(
      name: 'Pour over',
      color: 0xFFF2F2F2,
      offset: 13.8,
    );
    const scale = GrindScale(step: 0.1, max: 9, markers: [green, red, white]);

    test('one ruler across all marks, switching at the end only', () {
      expect(scale.absoluteMin, 0);
      expect(scale.absoluteMax, closeTo(22.8, 1e-9));
      // Green up to 9.0, then on at red 2.2.
      expect(scale.read(9.0, green), (value: 9.0, marker: green));
      final r = scale.read(9.1, green);
      expect(r.marker, red);
      expect(r.value, closeTo(2.3, 1e-9));
      // Red 1.0 lies inside green's range too: stays where it is.
      expect(scale.read(7.8, red).marker, red);
      expect(scale.read(7.8, red).value, closeTo(1.0, 1e-9));
      expect(scale.read(7.8, green).marker, green);
      // Red past 9.0 → white 2.x; white below 0 → red.
      expect(scale.read(15.9, red).marker, white);
      expect(scale.read(13.7, white).marker, red);
      expect(GrindScale.fromJson(scale.toJson()), scale);
    });
  });

  group('zero point', () {
    test('history per burr set, set before burrs counts for them', () {
      var g = const Grinder(id: 'g', name: 'Zero');
      g = g.withZero(-0.3, DateTime(2026, 10, 1));
      expect(g.zeroPoint?.value, -0.3);
      expect(g.effective(12), closeTo(12.3, 1e-9));

      // Burrs named later: the zero point set before applies to them.
      g = g.copyWith(burrs: ['SSP']);
      expect(g.zeroPoint?.value, -0.3);
      g = g.withZero(0.5, DateTime(2026, 10, 19));
      expect(g.zeros['SSP']!.single.value, 0.5);
      expect(g.zeros['']!.single.value, -0.3, reason: 'history stays');
      // Unchanged: no new entry.
      expect(identical(g.withZero(0.5, DateTime(2026, 10, 20)), g), isTrue);

      // Through the gear store and back: nothing lost.
      final back = grinderFromGear(gearFromGrinder(g));
      expect(back.zeros['SSP']!.single.at, DateTime(2026, 10, 19));
      expect(back.zeroPoint?.value, 0.5);
    });

    test('the shot keeps the grind precisely and the zero of its day', () {
      final grinders = GrinderStore.inMemory();
      final niche = grinders.add('Zero', ['SSP']);
      grinders.update(
        grinders
            .byId(niche.id)!
            .copyWith(scale: const GrindScale(step: 0.25, max: 50)),
      );
      grinders.setZero(niche.id, -0.3);
      final gear = grinders.gear
        ..saveChain(BrewChain(id: '', name: 'Bar', gearIds: [niche.id]));
      final setup = ShotSetup.inMemory(grindSize: 12.25)..gear = gear;
      final snap = setup.snapshot();
      expect(snap.grindText, '12.25');
      expect(snap.grindZero, -0.3);
      expect(grindSizeText(12), '12.0');
    });
  });

  testWidgets('grinder dialog: hand, microns in tens, zero point with ±', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory();
    final grinders = GrinderStore(gear);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GearStore>.value(value: gear),
          ChangeNotifierProvider<GrinderStore>.value(value: grinders),
          ChangeNotifierProvider<WaterStore>(create: (_) => WaterStore(gear)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MyCoffeeDeskScreen(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('new-grinder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('grinder-name')), 'K6');
    await tester.tap(find.text('Hand'));
    await tester.pump();
    await tester.tap(find.text('Microns'));
    await tester.pump();
    await tester.tap(find.text('10 µm'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('grinder-max')), '1200');
    await tester.enterText(find.byKey(const ValueKey('grinder-zero')), '30');
    // The number pad has no minus: the ± button sets it.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('grinder-zero')),
        matching: find.byTooltip('Plus/minus'),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final g = grinders.grinders.single;
    expect(g.hand, isTrue);
    expect(
      g.scale,
      const GrindScale(unit: GrindUnit.microns, step: 10, min: 0, max: 1200),
    );
    expect(g.zeroPoint?.value, -30);
    // The hand grinder icon on the desk.
    expect(
      gear.byId(g.id)!.type.iconAsset(gear.byId(g.id)!.specs),
      contains('grinder_hand'),
    );
    // The detail names scale and zero point.
    await tester.tap(find.text('K6'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Microns · 0–1200 µm'), findsOneWidget);
    expect(find.textContaining('-30 ·'), findsOneWidget);
  });

  testWidgets('Pre Shot: grind in the unit of the chain grinder, from zero', (
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
    final grinders = GrinderStore.inMemory();
    final k6 = grinders.add('K6', const []);
    grinders.update(
      grinders
          .byId(k6.id)!
          .copyWith(
            scale: const GrindScale(
              unit: GrindUnit.microns,
              step: 10,
              max: 1200,
            ),
          ),
    );
    grinders.setZero(k6.id, -30);
    final gear = grinders.gear
      ..saveChain(BrewChain(id: '', name: 'Bar', gearIds: [k6.id]));
    final setup = ShotSetup.inMemory(grindSize: 450)..gear = gear;

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
          home: const Scaffold(
            body: SingleChildScrollView(child: PreShotCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('450 µm'), findsOneWidget);
    expect(find.text('+480 from zero'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('grind panel: tap a mark converts, sliding on switches', (
    tester,
  ) async {
    const scale = GrindScale(
      step: 0.1,
      max: 9,
      markers: [
        GrindMarker(name: 'Espresso', color: 0xFF4CAF50),
        GrindMarker(name: 'Soup', color: 0xFFE53935, offset: 6.8),
      ],
    );
    (double, String?)? last;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: GrindPanel(
            scale: scale,
            value: 8.0,
            marker: 'Espresso',
            onChanged: (v, m) => last = (v, m),
          ),
        ),
      ),
    );
    expect(find.text('8.0'), findsOneWidget);
    // Green 8.0 = red 1.2.
    await tester.tap(find.byKey(const ValueKey('marker-Soup')));
    await tester.pump();
    expect(last?.$2, 'Soup');
    expect(last!.$1, closeTo(1.2, 1e-9));
  });

  testWidgets('grinder dialog: markers with colour, name and offset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gear = GearStore.inMemory();
    final grinders = GrinderStore(gear);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GearStore>.value(value: gear),
          ChangeNotifierProvider<GrinderStore>.value(value: grinders),
          ChangeNotifierProvider<WaterStore>(create: (_) => WaterStore(gear)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MyCoffeeDeskScreen(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('new-grinder')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('grinder-name')),
      'Monolith',
    );
    await tester.tap(find.text('Dial'));
    await tester.pump();
    await tester.tap(find.text('Steps of 0.1'));
    await tester.enterText(find.byKey(const ValueKey('grinder-max')), '9');
    await tester.ensureVisible(find.text('Add marker'));
    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('marker-name-0')),
      'Espresso',
    );
    await tester.enterText(find.byKey(const ValueKey('marker-name-1')), 'Soup');
    await tester.enterText(
      find.byKey(const ValueKey('marker-offset-1')),
      '6.8',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final scale = grinders.grinders.single.scale!;
    expect(scale.max, 9);
    expect(scale.step, 0.1);
    expect(
      [for (final m in scale.markers) (m.name, m.offset)],
      [('Espresso', 0.0), ('Soup', 6.8)],
    );
    expect(scale.markers[0].color, isNot(scale.markers[1].color));
  });
}

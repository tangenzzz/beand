import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/meticulous_scale.dart';
import 'package:beand/scale/scale_selector.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/live/pourover/pourover_home.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Socket extends MeticulousSocketService {
  _Socket() : super(hostname: 'test.local');

  @override
  void connect() {}

  final actions = <String>[];

  @override
  Future<bool> triggerAction(String action) async {
    actions.add(action);
    return true;
  }

  void send(double w) {
    connectionState = MachineConnectionState.connected;
    latestStatus = MachineStatus.fromJson({
      'state': 'idle',
      'name': 'idle',
      'sensors': {'w': w},
    });
    notifyListeners();
  }
}

final _machineProfile = brewRecipeFromMeticulous({
  'brew_type': 'pour_over',
  'id': '2500765d-a7bd-4ec3-986c-1bb3f47dde8b',
  'name': 'One and Done',
  'author': 'Meticulous',
  'recipe': {
    'coffee_dose_g': 15,
    'total_water_g': 225,
    'water_temperature_c': 93,
  },
  'stages': [
    {
      'name': 'Bloom',
      'starts_at_s': 0,
      'pour': {'water_g': 45, 'duration_s': 6},
    },
    {
      'name': 'Pour to 225 g',
      'starts_at_s': 30,
      'pour': {'water_g': 180, 'duration_s': 20},
    },
  ],
});

void main() {
  testWidgets('Meticulous as the scale: setup steps under the ring, Setup '
      'button, own profiles; switching back to Bluetooth', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    final socket = _Socket()..send(-136.5);
    final selector = ScaleSelector(
      bluetooth: SimulatedScale(),
      meticulous: MeticulousScale(socket),
      initial: ScaleSource.meticulous,
    );
    late PourOverBrewService brew;
    late BrewRecipeStore store;
    await tester.runAsync(() async {
      store = BrewRecipeStore(
        cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
        loadBundled: () async => jsonEncode(
          BrewRecipeBundle(
            commit: 'x',
            fetchedAt: DateTime(2026),
            raw: const [],
          ).toJson(),
        ),
      );
      await store.load();
      store.setMachineRecipes([_machineProfile]);
      brew = PourOverBrewService(
        scale: selector,
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      )..start();
    });
    expect(store.useMachine, isTrue);
    expect(brew.recipe?.name, 'One and Done');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<GearStore>.value(value: GearStore.inMemory()),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<AiSettings>.value(
            value: AiSettings(keyStore: InMemoryAiKeyStore()),
          ),
          ChangeNotifierProvider<BrewScale>.value(value: selector),
          ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
          ChangeNotifierProvider<PourOverBrewService>.value(value: brew),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PourOverHome()),
          ),
        ),
      ),
    );
    await tester.pump();

    // Machine mode (default): the dial leads. Two buttons: the scale
    // button names the mode, and Last brew.
    expect(find.text('Machine'), findsOneWidget);
    expect(find.text('Last brew'), findsOneWidget);
    // Free Pour and Tare stay, but dark and without a function; Auto's
    // place is Last brew.
    expect(find.text('Free Pour'), findsOneWidget);
    expect(find.text('Tare'), findsOneWidget);
    expect(find.text('Auto off'), findsNothing);
    await tester.tap(find.text('Tare'));
    await tester.pump();
    expect(socket.actions, isEmpty);
    expect(find.textContaining('Brew on the machine'), findsWidgets);
    expect(find.text('On the machine'), findsNWidgets(4));
    expect(find.text('Server on'), findsNothing);

    // Scale only via the scale button: the app leads with its own steps.
    await tester.tap(find.text('Machine'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Meticulous · Scale only'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(brew.meticulousMode, MeticulousPourMode.scaleOnly);
    expect(find.text('Scale only'), findsOneWidget);
    expect(find.text('Tare'), findsOneWidget);
    // Auto off: no steps, enter everything by hand.
    expect(find.text('Auto off'), findsOneWidget);
    expect(find.text('Server on'), findsNothing);
    await tester.tap(find.text('Auto off'));
    await tester.pump();
    expect(find.text('Auto on'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Server on'), findsOneWidget);
    expect(find.text('One and Done'), findsWidgets);
    // "+" on the profile row in every mode.
    expect(find.byTooltip('Add profile'), findsOneWidget);

    // Scale button → choose Bluetooth.
    await tester.tap(find.text('Scale only'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bluetooth scale'), findsOneWidget);
    await tester.tap(find.text('Bluetooth scale'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selector.source, ScaleSource.bluetooth);
    // Same row for a Bluetooth scale: Auto stays (steps once it connects).
    expect(find.text('Auto on'), findsOneWidget);
    expect(find.text('Server on'), findsNothing);
    expect(store.useMachine, isFalse);

    await tester.pumpWidget(const SizedBox());
    // Let pending timers (drift stream queries) run out.
    await tester.pump(const Duration(seconds: 2));
  });
}

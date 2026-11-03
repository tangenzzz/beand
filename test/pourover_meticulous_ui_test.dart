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

  @override
  Future<bool> triggerAction(String action) async => true;

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

    expect(find.text('Meticulous'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('1/3 Put the server on the scale'), findsOneWidget);
    expect(find.text('One and Done'), findsWidgets);
    // Machine profiles: reload instead of "+".
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    // Scale button → choose Bluetooth.
    await tester.tap(find.text('Meticulous'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bluetooth scale'), findsOneWidget);
    await tester.tap(find.text('Bluetooth scale'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selector.source, ScaleSource.bluetooth);
    expect(find.text('Setup'), findsNothing);
    expect(find.textContaining('Put the server'), findsNothing);
    expect(store.useMachine, isFalse);

    await tester.pumpWidget(const SizedBox());
    // Let pending timers (drift stream queries) run out.
    await tester.pump(const Duration(seconds: 2));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/pourover_draft.dart';
import 'package:beand/screens/profile/pourover_profile_detail_screen.dart';
import 'package:beand/screens/profile/setpoint_curve_chart.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:beand/services/profile_share.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _id = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _profile() => {
  'id': _id,
  'name': 'My Pour',
  'brew_type': 'pour_over',
  'author': 'Me',
  'beand': {'chain_id': 'x'},
  'recipe': {
    'coffee_dose_g': 15,
    'total_water_g': 50,
    'water_temperature_c': 93,
  },
  'stages': [
    {
      'name': 'Bloom',
      'key': 'bloom',
      'starts_at_s': 0,
      'pour': {
        'water_g': 50,
        'duration_s': 10,
        'target_cumulative_water_g': 50,
        'flow_rate_g_s': 5,
        'height_cm': 40,
      },
    },
  ],
};

void main() {
  late Directory dir;
  late AppDatabase db;
  late BrewRecipeStore store;
  late List<String> deletes;
  late int deleteStatus;
  late AppSettings settings;

  Future<void> build(
    WidgetTester tester, {
    bool onMachine = false,
    ProfileFileSharer? share,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dir = Directory.systemTemp.createTempSync('beand_actions');
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => dir.path,
    );
    db = AppDatabase(NativeDatabase.memory());
    deletes = [];
    deleteStatus = 200;
    settings = AppSettings();
    await tester.runAsync(() async {
      store = BrewRecipeStore(
        cacheFile: File('${dir.path}/no-cache.json'),
        loadBundled: () async => jsonEncode(
          BrewRecipeBundle(
            commit: 'x',
            fetchedAt: DateTime(2026),
            raw: const [],
          ).toJson(),
        ),
      );
      await store.load();
      if (onMachine) {
        store.machineSource = MeticulousPourOverProfiles(
          host: () => 'machine',
          client: MockClient((request) async {
            if (request.method == 'DELETE') {
              deletes.add(request.url.path);
              return http.Response('{}', deleteStatus);
            }
            if (request.url.path.endsWith('/list')) {
              return http.Response(
                jsonEncode({
                  'profiles': [_profile()],
                }),
                200,
              );
            }
            return http.Response('', 404);
          }),
        );
        await store.refreshMachine();
      } else {
        store.importProfile(_profile());
      }
    });
    final recipe = onMachine
        ? store.machineRecipes.single
        : store.importedRecipes.single;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<BrewRecipeStore>.value(value: store),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: MaterialApp(
          theme: ThemeData(
            extensions: [
              AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal),
            ],
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PourOverProfileDetailScreen(
                      recipe: recipe,
                      shareFile: share,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.text('Delete profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a profile on the machine can be deleted, there first', (
    tester,
  ) async {
    await build(tester, onMachine: true);
    expect(find.byType(SetpointCurveChart), findsOneWidget);
    await confirmDelete(tester);
    expect(deletes, ['/api/v1/pour-over/profile/delete/$_id']);
    expect(store.machineRecipes, isEmpty);
    expect(find.text('open'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the curve folds away and stays as it was left', (tester) async {
    await build(tester);
    expect(find.byType(SetpointCurveChart), findsOneWidget);
    await tester.tap(find.text('TARGET CURVE'));
    await tester.pumpAndSettle();
    expect(find.byType(SetpointCurveChart), findsNothing);
    expect(settings.expandProfileCurve, isFalse);

    // Leave and come back.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('TARGET CURVE'), findsOneWidget);
    expect(find.byType(SetpointCurveChart), findsNothing);

    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppSettings.expandProfileCurvePrefKey), isFalse);
    });
    await finish(tester);
  });

  testWidgets('the machine refusing leaves the profile where it is', (
    tester,
  ) async {
    await build(tester, onMachine: true);
    deleteStatus = 500;
    await confirmDelete(tester);
    expect(store.machineRecipes, hasLength(1));
    expect(find.text('Delete profile'), findsOneWidget);
    expect(find.textContaining('Could not delete'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a profile only in the app is deleted without the machine', (
    tester,
  ) async {
    await build(tester);
    await confirmDelete(tester);
    expect(store.importedRecipes, isEmpty);
    await finish(tester);
  });

  testWidgets('share sends the profile as a .json file the machine takes', (
    tester,
  ) async {
    XFile? shared;
    await build(tester, share: (file, _) async => shared = file);
    await tester.tap(find.byTooltip('Share profile'));
    // Real file access: real time, with the test's clock pumped in between.
    for (var i = 0; i < 10 && shared == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(shared!.path, endsWith('My-Pour.json'));
    final json = await tester.runAsync(
      () async => jsonDecode(await File(shared!.path).readAsString()) as Map,
    );
    expect(json!['id'], _id);
    expect(json['brew_type'], 'pour_over');
    expect(json.containsKey('beand'), isFalse);
    await finish(tester);
  });

  test('height is at most 15 cm, also when a file says more', () {
    expect(maxHeightCm, 15);
    final draft = PourOverDraft.fromJson(_profile());
    expect(draft.pours.single.heightCm, 15);
  });
}

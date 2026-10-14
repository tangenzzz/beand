import 'dart:convert';
import 'dart:io';

import 'package:beand/models/brew_recipe.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _recipe({
  String id = 'test-recipe',
  Map<String, dynamic>? extra,
}) => {
  'id': id,
  'name': 'Test',
  'brewer': 'V60',
  'dose_g': 20,
  'water_ml': 300,
  'ratio': '1:15',
  'water_temp_c': 92,
  'grind_size': 'coarse',
  'phases': [
    {'label': 'Bloom', 'water_g': 60, 'wait_seconds': 45},
    {'label': 'Pulse', 'water_g': 80, 'pours': 3},
  ],
  'source': {'name': 'Someone'},
  ...?extra,
};

void main() {
  test('every bundled recipe passes the schema check', () {
    final bundle = BrewRecipeBundle.fromJson(
      jsonDecode(File(brewRecipesAsset).readAsStringSync())
          as Map<String, dynamic>,
    );
    final parsed = parseBrewRecipes(bundle.raw);
    expect(parsed.rejected, isEmpty);
    expect(parsed.recipes.length, greaterThanOrEqualTo(60));
    expect(
      parsed.recipes.map((r) => r.id),
      contains('tetsu-kasuya-4-6-method'),
    );
  });

  test('steps expand sub-pours and accumulate targets', () {
    final r = BrewRecipe.fromJson(_recipe());
    final steps = r.steps;
    expect(steps.map((s) => s.label), [
      'Bloom',
      'Pulse 1/3',
      'Pulse 2/3',
      'Pulse 3/3',
    ]);
    expect(steps.map((s) => s.targetTotalG), [60, 140, 220, 300]);
    expect(steps[1].startTotalG, 60);
    expect(r.stepsWaterG, 300);
    expect(r.ratioValue, 15);
  });

  test('invalid recipes are rejected, valid ones kept', () {
    final parsed = parseBrewRecipes([
      _recipe(id: 'ok'),
      _recipe(id: 'Bad_ID'),
      _recipe(id: 'unknown', extra: {'foo': 1}),
      _recipe(id: 'grind', extra: {'grind_size': 'powder'}),
      {..._recipe(id: 'no-temp')}..remove('water_temp_c'),
      _recipe(id: 'ok'),
    ]);
    expect(parsed.recipes.map((r) => r.id), ['ok']);
    expect(parsed.rejected, hasLength(5));
  });

  group('BrewRecipeStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('recipes'));
    tearDown(() => dir.deleteSync(recursive: true));

    String bundleJson(
      String commit,
      DateTime at,
      List<Map<String, dynamic>> raw,
    ) => jsonEncode(
      BrewRecipeBundle(commit: commit, fetchedAt: at, raw: raw).toJson(),
    );

    MockClient github(String sha, List<Map<String, dynamic>> files) =>
        MockClient((req) async {
          final u = req.url.toString();
          if (u.endsWith('/commits/main')) {
            return http.Response(jsonEncode({'sha': sha}), 200);
          }
          if (u.contains('/git/trees/')) {
            return http.Response(
              jsonEncode({
                'tree': [
                  for (var i = 0; i < files.length; i++)
                    {'type': 'blob', 'path': 'recipes/en/v60/r$i.yaml'},
                  {'type': 'blob', 'path': 'recipes/zh/v60/x.yaml'},
                ],
              }),
              200,
            );
          }
          final i = int.parse(
            RegExp(r'/r(\d+)\.yaml$').firstMatch(u)!.group(1)!,
          );
          // JSON is valid YAML.
          return http.Response(jsonEncode(files[i]), 200);
        });

    test('loads bundled, then a newer cache wins', () async {
      final cache = File('${dir.path}/c.json');
      final store = BrewRecipeStore(
        cacheFile: cache,
        loadBundled: () async =>
            bundleJson('aaa', DateTime(2026, 1, 1), [_recipe(id: 'one')]),
      );
      await store.load();
      expect(store.recipes.map((r) => r.id), ['one']);

      cache.writeAsStringSync(
        bundleJson('bbb', DateTime(2026, 2, 1), [_recipe(id: 'two')]),
      );
      await store.load();
      expect(store.recipes.map((r) => r.id), ['two']);
      expect(store.commit, 'bbb');
    });

    test('update writes cache; empty update keeps the old set', () async {
      final cache = File('${dir.path}/c.json');
      var files = [_recipe(id: 'new-one'), _recipe(id: 'BROKEN')];
      var sha = 'ccc';
      final store = BrewRecipeStore(
        cacheFile: cache,
        loadBundled: () async =>
            bundleJson('aaa', DateTime(2026, 1, 1), [_recipe(id: 'one')]),
        source: () => BrewRecipesSource(client: github(sha, files)),
      );
      await store.load();
      expect(await store.updateFromGitHub(), 1);
      expect(store.recipes.map((r) => r.id), ['new-one']);
      expect(cache.existsSync(), isTrue);

      // Same commit → nothing to do.
      expect(await store.updateFromGitHub(), isNull);

      sha = 'ddd';
      files = [_recipe(id: 'BROKEN')];
      await expectLater(store.updateFromGitHub(), throwsFormatException);
      expect(store.recipes.map((r) => r.id), ['new-one']);
    });
  });
}

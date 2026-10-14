// Updates the bundled recipes `assets/brew_recipes.json` from
// HotThoughts/brew-recipes (CC0 1.0).
//
//   dart run tool/fetch_brew_recipes.dart

import 'dart:convert';
import 'dart:io';

import 'package:beand/models/brew_recipe.dart';
import 'package:beand/services/brew_recipes_source.dart';

Future<void> main() async {
  final source = BrewRecipesSource();
  try {
    final bundle = await source.fetch();
    final parsed = parseBrewRecipes(bundle.raw);
    for (final r in parsed.rejected) {
      stderr.writeln('skipped $r');
    }
    // Bundle only valid recipes.
    final valid = {for (final r in parsed.recipes) r.id};
    final out = BrewRecipeBundle(
      commit: bundle.commit,
      fetchedAt: bundle.fetchedAt,
      raw: [
        for (final r in bundle.raw)
          if (valid.contains(r['id'])) r,
      ],
    );
    final file = File('assets/brew_recipes.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent(' ').convert(out.toJson())}\n',
    );
    stdout.writeln(
      '${out.raw.length} recipes @ ${bundle.commit.substring(0, 7)}'
      ' → ${file.path}',
    );
  } finally {
    source.close();
  }
}

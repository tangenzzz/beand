import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../models/brew_recipe.dart';

/// A snapshot of the recipe collection: the raw recipes (as they are in the
/// repo, only converted from YAML to JSON) plus the commit they come from.
/// The same format is bundled in `assets/brew_recipes.json` and cached after
/// an update from GitHub.
class BrewRecipeBundle {
  const BrewRecipeBundle({
    required this.commit,
    required this.fetchedAt,
    required this.raw,
  });

  final String commit;
  final DateTime fetchedAt;
  final List<Map<String, dynamic>> raw;

  factory BrewRecipeBundle.fromJson(Map<String, dynamic> j) => BrewRecipeBundle(
    commit: j['commit'] as String,
    fetchedAt: DateTime.parse(j['fetched_at'] as String),
    raw: [
      for (final r in j['recipes'] as List) Map<String, dynamic>.from(r as Map),
    ],
  );

  Map<String, dynamic> toJson() => {
    'source': 'https://github.com/$brewRecipesRepo',
    'license': 'CC0-1.0',
    'commit': commit,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    'recipes': raw,
  };
}

/// Loads the English recipes (`recipes/en/**.yaml`) from GitHub.
/// Two API calls (commit + file tree), the files themselves via
/// raw.githubusercontent.com — that doesn't count against the API limit.
class BrewRecipesSource {
  BrewRecipesSource({http.Client? client, this.branch = 'main'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String branch;

  static const _timeout = Duration(seconds: 20);

  Future<String> latestCommit() async {
    final res = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/$brewRecipesRepo/commits/$branch',
          ),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException(
        'GitHub commit lookup: HTTP ${res.statusCode}',
      );
    }
    return (jsonDecode(res.body) as Map)['sha'] as String;
  }

  /// Omit [commit] = latest state of [branch].
  Future<BrewRecipeBundle> fetch({String? commit}) async {
    final sha = commit ?? await latestCommit();
    final treeRes = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/$brewRecipesRepo/git/trees/$sha?recursive=1',
          ),
        )
        .timeout(_timeout);
    if (treeRes.statusCode != 200) {
      throw http.ClientException('GitHub tree: HTTP ${treeRes.statusCode}');
    }
    final tree = (jsonDecode(treeRes.body) as Map)['tree'] as List;
    final paths = [
      for (final e in tree)
        if (e['type'] == 'blob' &&
            (e['path'] as String).startsWith('recipes/en/') &&
            (e['path'] as String).endsWith('.yaml'))
          e['path'] as String,
    ]..sort();

    final raw = <Map<String, dynamic>>[];
    for (final path in paths) {
      final res = await _client
          .get(
            Uri.parse(
              'https://raw.githubusercontent.com/$brewRecipesRepo/$sha/$path',
            ),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) continue;
      try {
        final doc = loadYaml(utf8.decode(res.bodyBytes));
        if (doc is YamlMap) raw.add(yamlToJson(doc) as Map<String, dynamic>);
      } on YamlException {
        // Skip a broken file; the rest of the snapshot stays usable.
      }
    }
    return BrewRecipeBundle(commit: sha, fetchedAt: DateTime.now(), raw: raw);
  }

  void close() => _client.close();
}

/// YamlMap/YamlList → plain maps/lists (JSON-compatible).
Object? yamlToJson(Object? node) {
  if (node is YamlMap) {
    return <String, dynamic>{
      for (final e in node.entries) e.key.toString(): yamlToJson(e.value),
    };
  }
  if (node is YamlList) return [for (final v in node) yamlToJson(v)];
  return node;
}

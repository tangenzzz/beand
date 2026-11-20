import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Coastlines and country outlines for the coffee map (Natural Earth, public
// domain; see assets/geo/README.md). Points are (longitude, latitude).
class WorldGeo {
  WorldGeo._(this.coast, this.land, this.borders);

  /// Coastline pieces between 38° N and 38° S.
  final List<List<Offset>> coast;

  /// Land areas, clipped to the same band, for a faint fill.
  final List<List<Offset>> land;

  /// Outline rings per country ISO code.
  final Map<String, List<List<Offset>>> borders;

  static Future<WorldGeo>? _loading;

  /// Loaded once and kept; parsing runs off the UI thread.
  static Future<WorldGeo> load() => _loading ??= () async {
    final land = await rootBundle.loadString('assets/geo/land.json');
    final borders = await rootBundle.loadString('assets/geo/borders.json');
    return compute(_parse, (land, borders));
  }();

  static WorldGeo _parse((String, String) raw) {
    List<Offset> ring(List<dynamic> pts) => [
      for (final p in pts)
        Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    final land = jsonDecode(raw.$1) as Map<String, dynamic>;
    final borders = jsonDecode(raw.$2) as List<dynamic>;
    return WorldGeo._(
      [for (final l in land['lines'] as List) ring(l as List)],
      [for (final f in land['fills'] as List) ring(f as List)],
      {
        for (final b in borders)
          (b as Map<String, dynamic>)['iso'] as String: [
            for (final r in b['rings'] as List) ring(r as List),
          ],
      },
    );
  }
}

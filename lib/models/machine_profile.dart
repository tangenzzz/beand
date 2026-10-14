import 'dart:convert';

import 'package:flutter/material.dart';

import '../database/database.dart';

// Short profile form from `GET /api/v1/profile/list` (without ?full=true,
// i.e. without the stages — enough for the overview cards and much lighter
// than the full profile definition).
class MachineProfile {
  final String id;
  final String name;
  final double temperature;
  final double finalWeight;
  final Color accentColor;
  // Relative path like "/api/v1/profile/image/xxx.jpeg" — must be combined
  // with the machine's hostname (see ProfileCarousel).
  final String? imagePath;
  // Local copy of the image (preferred, works offline).
  final String? localImagePath;

  const MachineProfile({
    required this.id,
    required this.name,
    required this.temperature,
    required this.finalWeight,
    required this.accentColor,
    this.imagePath,
    this.localImagePath,
  });

  factory MachineProfile.fromJson(Map<String, dynamic> json) {
    final display = Map<String, dynamic>.from(json['display'] as Map? ?? {});
    final image = display['image'] as String?;
    return MachineProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      finalWeight: (json['final_weight'] as num?)?.toDouble() ?? 0,
      accentColor: _parseColor(
        display['accentColor'] as String?,
        (json['id'] ?? json['name'] ?? '').toString(),
      ),
      imagePath: (image != null && image.isNotEmpty) ? image : null,
    );
  }

  // From the local copy (StoredProfiles): works without the machine; the
  // image preferably comes from the local file. A user-chosen photo takes
  // precedence over the machine's.
  factory MachineProfile.fromStored(StoredProfile stored) {
    if (stored.machine == 'gaggimate') return _fromStoredGaggiMate(stored);
    final base = MachineProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(stored.json) as Map),
    );
    return MachineProfile(
      id: stored.id,
      name: base.name.isEmpty ? stored.name : base.name,
      temperature: base.temperature,
      finalWeight: base.finalWeight,
      accentColor: base.accentColor,
      imagePath: base.imagePath,
      localImagePath: stored.customImagePath ?? stored.imagePath,
    );
  }

  // GaggiMate profiles have their own schema: `label` instead of `name`, the
  // target weight lives in the phases' stop conditions, and they never carry
  // an image — only a user-chosen photo.
  static MachineProfile _fromStoredGaggiMate(StoredProfile stored) {
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(stored.json) as Map);
    } catch (_) {
      json = const {};
    }
    var weight = 0.0;
    for (final phase in (json['phases'] as List? ?? const [])) {
      if (phase is! Map) continue;
      for (final target in (phase['targets'] as List? ?? const [])) {
        // Only "volumetric" counts: the firmware discards any other type.
        if (target is Map && target['type'] == 'volumetric') {
          final value = (target['value'] as num?)?.toDouble();
          if (value != null && value > 0) weight = value;
        }
      }
    }
    return MachineProfile(
      id: stored.id,
      name: (json['label'] ?? stored.name).toString(),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      finalWeight: weight,
      accentColor: profilePlaceholderColor(stored.id),
      localImagePath: stored.customImagePath,
    );
  }

  // GaggiMate utility profiles (backflush, rinse) do not belong in the
  // profile picker.
  static bool isUtility(StoredProfile stored) {
    if (stored.machine != 'gaggimate') return false;
    try {
      final json = jsonDecode(stored.json);
      return json is Map && json['utility'] == true;
    } catch (_) {
      return false;
    }
  }

  // Without its own accent color the profile gets one from the placeholder
  // palette, fixed to [seed] — so profiles without an image do not all look
  // the same gray.
  static Color _parseColor(String? hex, String seed) {
    if (hex == null || hex.isEmpty) return profilePlaceholderColor(seed);
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return profilePlaceholderColor(seed);
    return Color(0xFF000000 | value);
  }
}

// Hues for profiles that bring neither an image nor their own accent color
// (all GaggiMate profiles, some Meticulous profiles). Muted enough for the
// dark background and clearly distinct from each other — otherwise the
// cards would all look the same.
const profilePlaceholderColors = [
  Color(0xFF3D7A6B), // Fir green
  Color(0xFF7A5A3D), // Roast brown
  Color(0xFF4A5B82), // Steel blue
  Color(0xFF7A3D4E), // Berry red
  Color(0xFF5B4A7A), // Plum
  Color(0xFF6B7A3D), // Olive
  Color(0xFF3D6B7A), // Petrol
  Color(0xFF7A6B3D), // Brass
];

// Always the same color for the same profile: it depends only on the key,
// not on the position in the list — otherwise a new profile would recolor
// all the others.
Color profilePlaceholderColor(String seed) {
  if (seed.isEmpty) return profilePlaceholderColors.first;
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return profilePlaceholderColors[hash % profilePlaceholderColors.length];
}

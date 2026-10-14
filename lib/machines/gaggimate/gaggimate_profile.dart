import '../../models/machine_profile.dart';

// GaggiMate profile (schema/profile.json in the firmware repo). Much leaner
// than a Meticulous profile: no image, no accent color, no top-level target
// weight — that lives in the phases' stop conditions.
class GaggiMateProfile {
  const GaggiMateProfile({
    required this.id,
    required this.label,
    required this.description,
    required this.temperature,
    required this.favorite,
    required this.selected,
    required this.utility,
    required this.phaseCount,
    required this.targetWeight,
    required this.totalDuration,
  });

  final String id;
  final String label;
  final String description;
  final double temperature;
  final bool favorite;
  final bool selected;
  // Utility profiles (backflush, rinse) — not part of the shot selection.
  final bool utility;
  final int phaseCount;
  // From the last volumetric target of the phases; 0 if the profile runs
  // purely on time.
  final double targetWeight;
  final Duration totalDuration;

  factory GaggiMateProfile.fromJson(Map<String, dynamic> json) {
    final phases = (json['phases'] as List?) ?? const [];
    double targetWeight = 0;
    double seconds = 0;
    for (final phase in phases) {
      if (phase is! Map) continue;
      seconds += (phase['duration'] as num?)?.toDouble() ?? 0;
      for (final target in (phase['targets'] as List?) ?? const []) {
        // Only "volumetric" counts: the firmware silently drops every other
        // target type (including "weight").
        if (target is Map && target['type'] == 'volumetric') {
          final value = (target['value'] as num?)?.toDouble();
          if (value != null && value > 0) targetWeight = value;
        }
      }
    }
    return GaggiMateProfile(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      favorite: json['favorite'] == true,
      selected: json['selected'] == true,
      utility: json['utility'] == true,
      phaseCount: phases.length,
      targetWeight: targetWeight,
      totalDuration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  // For the shared profile card. GaggiMate profiles bring neither an image
  // nor an accent color, so the color comes from the placeholder palette —
  // tied to the profile ID so every profile keeps its own.
  MachineProfile toMachineProfile() => MachineProfile(
    id: id,
    name: label,
    temperature: temperature,
    finalWeight: targetWeight,
    accentColor: profilePlaceholderColor(id),
  );
}

import 'dart:ui';

import '../database/database.dart';

// A phase (profile stage) of a shot, as the machine reports it per data
// point ("Initial Saturation", "Percolation", ...). At the end of every shot
// it reports "retracting" (piston moves back), which is kept here as
// "Retraction".
class ShotPhase {
  const ShotPhase({
    required this.name,
    required this.startMs,
    required this.endMs,
    required this.color,
    required this.isRetraction,
  });

  final String name;
  final int startMs;
  final int endMs;
  final Color color;
  final bool isRetraction;

  double get seconds => (endMs - startMs) / 1000;
}

const retractionStage = 'retracting';
const retractionColor = Color(0xFF6C7A99);

// Colors by stage order (not by name — profiles name their stages freely).
// The first four match the Meticulous colors for Initial Saturation /
// Puck Saturation / Percolation Ramp / Percolation.
const phasePalette = [
  Color(0xFFE0446A),
  Color(0xFFF2914C),
  Color(0xFFC9B23E),
  Color(0xFF2FC585),
  Color(0xFF4FB3BF),
  Color(0xFFA78DE0),
  Color(0xFFF06FB0),
];

String phaseLabel(String stage) =>
    stage == retractionStage ? 'Retraction' : stage;

// Consecutive data points with the same stage form one phase. A phase lasts
// until the start of the next one, the last until the last data point. Data
// points without a stage name (legacy data) are skipped.
List<ShotPhase> computePhases(List<ShotReading> readings) {
  final runs = <({String name, int start})>[];
  for (final r in readings) {
    final stage = r.stage;
    if (stage == null || stage.isEmpty) continue;
    if (runs.isEmpty || runs.last.name != stage) {
      runs.add((name: stage, start: r.timeMs));
    }
  }
  if (runs.isEmpty) return const [];
  final lastMs = readings.last.timeMs;
  final seen = <String>[];
  final phases = <ShotPhase>[];
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    final isRetraction = run.name == retractionStage;
    var color = retractionColor;
    if (!isRetraction) {
      if (!seen.contains(run.name)) seen.add(run.name);
      color = phasePalette[(seen.indexOf(run.name)) % phasePalette.length];
    }
    phases.add(
      ShotPhase(
        name: phaseLabel(run.name),
        startMs: run.start,
        endMs: i + 1 < runs.length ? runs[i + 1].start : lastMs,
        color: color,
        isRetraction: isRetraction,
      ),
    );
  }
  return phases;
}

// The phase that contains [timeMs] (for the cursor display in the chart).
ShotPhase? phaseAt(List<ShotPhase> phases, int timeMs) {
  for (final p in phases) {
    if (timeMs >= p.startMs && timeMs < p.endMs) return p;
  }
  return phases.isEmpty ? null : phases.last;
}

import 'dart:convert';
import 'dart:typed_data';

// The GaggiMate stores its shot history in binary form in flash and serves
// it over HTTP (not over the WebSocket):
//
//   GET /api/history/index.bin        — index of all shots
//   GET /api/history/<id>.slog        — time series of one shot
//
// Both formats are defined in `src/display/models/shot_log_format.h` in the
// firmware. Everything is little-endian, readings are scaled integers. The
// files are versioned and grow from version to version — so this code never
// uses fixed offsets from the start of the file, but `headerSize` from the
// file and the sample size matching the version. Older recordings stay
// readable that way.

const int _indexMagic = 0x58444953; // 'SIDX'
const int _shotMagic = 0x544F4853; // 'SHOT'

const int _indexHeaderSize = 32;

// Flags in ShotIndexEntry.flags
const int _flagCompleted = 0x01;
const int _flagDeleted = 0x02;

class GaggiMateShotLogException implements Exception {
  GaggiMateShotLogException(this.message);
  final String message;
  @override
  String toString() => 'GaggiMateShotLogException: $message';
}

// An entry from index.bin — enough to decide whether the shot has already
// been imported. The time series comes afterwards from the .slog.
class GaggiMateShotIndexEntry {
  const GaggiMateShotIndexEntry({
    required this.id,
    required this.timestamp,
    required this.durationMs,
    required this.finalWeight,
    required this.rating,
    required this.flags,
    required this.profileId,
    required this.profileName,
    required this.avgTemp,
    required this.maxPressure,
    required this.avgFlow,
  });

  final int id;
  final DateTime timestamp;
  final int durationMs;
  // Grams; null if the machine weighed nothing (no scale).
  final double? finalWeight;
  final int rating;
  final int flags;
  final String profileId;
  final String profileName;
  // Shot metrics; null for recordings that did not have them yet.
  final double? avgTemp;
  final double? maxPressure;
  final double? avgFlow;

  bool get completed => flags & _flagCompleted != 0;
  bool get deleted => flags & _flagDeleted != 0;

  // The file name is the id zero-padded to six digits —
  // /api/history/0.slog returns 404.
  String get fileName => '${id.toString().padLeft(6, '0')}.slog';
}

// One data point. All fields are already unscaled (°C, bar, ml/s, g).
class GaggiMateShotSample {
  const GaggiMateShotSample({
    required this.timeMs,
    required this.targetTemp,
    required this.currentTemp,
    required this.targetPressure,
    required this.pressure,
    required this.pumpFlow,
    required this.targetFlow,
    required this.puckFlow,
    required this.scaleFlow,
    required this.scaleWeight,
    required this.estimatedWeight,
    required this.puckResistance,
    required this.systemInfo,
    required this.waterPumped,
    required this.stage,
  });

  final int timeMs;
  final double targetTemp;
  final double currentTemp;
  final double targetPressure;
  final double pressure;
  final double pumpFlow;
  final double targetFlow;
  final double puckFlow;
  final double scaleFlow;
  final double scaleWeight;
  final double estimatedWeight;
  final double puckResistance;
  final int systemInfo;
  // Cumulative pumped water (ml); null before version 7.
  final double? waterPumped;
  // Name of the profile phase at this point; null if the recording contains
  // no phase transitions (before version 5).
  final String? stage;

  bool get scaleConnected => systemInfo & 0x0004 != 0;

  // Without a scale only the volumetric estimate is left. Writing exactly one
  // of the two sources into the weight curve keeps it monotonic — mixing
  // them would make it jump.
  double? get weight {
    if (scaleConnected && scaleWeight > 0) return scaleWeight;
    return estimatedWeight > 0 ? estimatedWeight : null;
  }
}

/// How a phase ended — the machine writes this into the recording header
/// itself (shot_log_format.h, PHASE_EXIT_REASON_*). So the app does not have
/// to guess from the curve which exit triggered.
class GaggiMatePhaseExit {
  const GaggiMatePhaseExit({
    required this.stage,
    this.reason,
    this.waterPumped,
    this.scaleConnected = false,
  });

  final String stage;

  /// weight | pressure | flow | pumped | time | safety | aborted; null =
  /// unknown (older firmware writes 0 here).
  final String? reason;

  /// Water pumped in this phase (ml) — the firmware resets the counter to 0
  /// at every phase boundary. Null before version 7.
  final double? waterPumped;

  /// Was a scale connected during the phase? Without a scale the weight is
  /// only estimated, and a weight target cannot trigger.
  final bool scaleConnected;

  Map<String, Object?> toJson() => {
    'stage': stage,
    'reason': reason,
    'pumped': waterPumped,
    'scale': scaleConnected,
  };
}

String? _exitReason(int code) => switch (code) {
  1 => 'weight',
  2 => 'pressure',
  3 => 'flow',
  4 => 'pumped',
  5 => 'time',
  6 => 'safety',
  7 => 'aborted',
  _ => null,
};

class GaggiMateShotLog {
  const GaggiMateShotLog({
    required this.version,
    required this.profileId,
    required this.profileName,
    required this.startedAt,
    required this.durationMs,
    required this.finalWeight,
    required this.samples,
    this.phaseExits = const [],
  });

  final int version;
  final String profileId;
  final String profileName;
  final DateTime startedAt;
  final int durationMs;
  final double? finalWeight;
  final List<GaggiMateShotSample> samples;

  /// How each phase ended, according to the machine (firmware with
  /// `transitionReason`, otherwise empty or [GaggiMatePhaseExit.reason] null).
  final List<GaggiMatePhaseExit> phaseExits;

  // Mean boiler temperature over the brew — the same measure the Meticulous
  // imports store as brewTemp (there the mean of the four sensors).
  double? get averageTemp {
    final values = [
      for (final s in samples)
        if (s.currentTemp > 0) s.currentTemp,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  // Target temperature of the profile.
  double? get targetTemp {
    for (final s in samples) {
      if (s.targetTemp > 0) return s.targetTemp;
    }
    return null;
  }
}

// ---- index.bin ------------------------------------------------------------

List<GaggiMateShotIndexEntry> parseGaggiMateIndex(Uint8List bytes) {
  if (bytes.length < _indexHeaderSize) {
    throw GaggiMateShotLogException('index too short (${bytes.length} B)');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _indexMagic) {
    throw GaggiMateShotLogException('bad index magic');
  }
  final entrySize = data.getUint16(6, Endian.little);
  final entryCount = data.getUint32(8, Endian.little);
  if (entrySize < 96) {
    throw GaggiMateShotLogException('implausible entry size $entrySize');
  }

  final entries = <GaggiMateShotIndexEntry>[];
  for (var i = 0; i < entryCount; i++) {
    final at = _indexHeaderSize + i * entrySize;
    // A truncated index is no reason to throw away the entries already read
    // — the rest is usable.
    if (at + entrySize > bytes.length) break;
    final volume = data.getUint16(at + 12, Endian.little);
    final avgTemp = data.getUint16(at + 96, Endian.little);
    final maxPressure = data.getUint16(at + 98, Endian.little);
    final avgFlow = data.getUint16(at + 100, Endian.little);
    entries.add(
      GaggiMateShotIndexEntry(
        id: data.getUint32(at, Endian.little),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          data.getUint32(at + 4, Endian.little) * 1000,
        ),
        durationMs: data.getUint32(at + 8, Endian.little),
        finalWeight: volume == 0 ? null : volume / 10,
        rating: data.getUint8(at + 14),
        flags: data.getUint8(at + 15),
        profileId: _string(bytes, at + 16, 32),
        profileName: _string(bytes, at + 48, 48),
        // 0 means "not recorded" (these fields were added later).
        avgTemp: avgTemp == 0 ? null : avgTemp / 10,
        maxPressure: maxPressure == 0 ? null : maxPressure / 10,
        avgFlow: avgFlow == 0 ? null : avgFlow / 100,
      ),
    );
  }
  return entries;
}

// ---- <id>.slog ------------------------------------------------------------

// Sample size and time field depend on the version:
//   v1–v5: 26 B, `t` is a uint16 sample index (× sampleInterval)
//   v6:    28 B, `t` is the real time in ms (uint32)
//   v7:    30 B, additionally `wp` (pumped water)
int _sampleSizeFor(int version) => switch (version) {
  >= 7 => 30,
  6 => 28,
  _ => 26,
};

GaggiMateShotLog parseGaggiMateShotLog(Uint8List bytes) {
  if (bytes.length < 64) {
    throw GaggiMateShotLogException('shot log too short (${bytes.length} B)');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _shotMagic) {
    throw GaggiMateShotLogException('bad shot log magic');
  }
  final version = data.getUint8(4);
  final headerSize = data.getUint16(6, Endian.little);
  final sampleInterval = data.getUint16(8, Endian.little);
  var sampleCount = data.getUint32(16, Endian.little);
  final durationMs = data.getUint32(20, Endian.little);
  final startEpoch = data.getUint32(24, Endian.little);
  final profileId = _string(bytes, 28, 32);
  final profileName = _string(bytes, 60, 48);
  if (headerSize < 108 || headerSize > bytes.length) {
    throw GaggiMateShotLogException('implausible header size $headerSize');
  }

  // finalWeight and the phase transitions came with the 512 B header (v5).
  final hasV5Header = headerSize >= 512;
  final rawFinalWeight = hasV5Header ? data.getUint16(108, Endian.little) : 0;
  final transitions = hasV5Header
      ? _phaseTransitions(bytes, data)
      : const <_Transition>[];

  final sampleSize = _sampleSizeFor(version);
  final available = (bytes.length - headerSize) ~/ sampleSize;
  // sampleCount is only filled in when the shot finishes — after an abort
  // (power loss) it is still 0 or too large. What is actually in the file
  // counts.
  if (sampleCount == 0 || sampleCount > available) sampleCount = available;

  final samples = <GaggiMateShotSample>[];
  for (var i = 0; i < sampleCount; i++) {
    final at = headerSize + i * sampleSize;
    final int timeMs;
    var f = at;
    if (version >= 6) {
      timeMs = data.getUint32(f, Endian.little);
      f += 4;
    } else {
      timeMs = data.getUint16(f, Endian.little) * sampleInterval;
      f += 2;
    }
    final sample = GaggiMateShotSample(
      timeMs: timeMs,
      targetTemp: data.getUint16(f, Endian.little) / 10,
      currentTemp: data.getUint16(f + 2, Endian.little) / 10,
      targetPressure: data.getUint16(f + 4, Endian.little) / 10,
      pressure: data.getUint16(f + 6, Endian.little) / 10,
      pumpFlow: data.getInt16(f + 8, Endian.little) / 100,
      targetFlow: data.getInt16(f + 10, Endian.little) / 100,
      puckFlow: data.getInt16(f + 12, Endian.little) / 100,
      scaleFlow: data.getInt16(f + 14, Endian.little) / 100,
      scaleWeight: data.getUint16(f + 16, Endian.little) / 10,
      estimatedWeight: data.getUint16(f + 18, Endian.little) / 10,
      puckResistance: data.getUint16(f + 20, Endian.little) / 100,
      systemInfo: data.getUint16(f + 22, Endian.little),
      waterPumped: version >= 7
          ? data.getUint16(f + 24, Endian.little) / 10
          : null,
      stage: _stageAt(transitions, i),
    );
    samples.add(sample);
  }

  // The reason phase i ended is stored with transition i+1; the last phase
  // ends with the shot (finalExitReason right after the count).
  final finalReason = hasV5Header
      ? data.getUint8(_transitionsBase + 12 * 29 + 1)
      : 0;
  final phaseExits = <GaggiMatePhaseExit>[
    for (var i = 0; i < transitions.length; i++)
      () {
        final t = transitions[i];
        final end = i + 1 < transitions.length
            ? transitions[i + 1].sampleIndex
            : samples.length;
        final inPhase = samples.sublist(
          t.sampleIndex.clamp(0, samples.length),
          end.clamp(0, samples.length),
        );
        final pumped = [for (final s in inPhase) ?s.waterPumped];
        return GaggiMatePhaseExit(
          stage: t.name,
          reason: _exitReason(
            i + 1 < transitions.length
                ? transitions[i + 1].reason
                : finalReason,
          ),
          waterPumped: pumped.isEmpty
              ? null
              : pumped.reduce((a, b) => a > b ? a : b),
          scaleConnected: inPhase.any((s) => s.scaleConnected),
        );
      }(),
  ];

  return GaggiMateShotLog(
    phaseExits: phaseExits,
    version: version,
    profileId: profileId,
    profileName: profileName,
    startedAt: DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000),
    durationMs: durationMs == 0 && samples.isNotEmpty
        ? samples.last.timeMs
        : durationMs,
    finalWeight: rawFinalWeight == 0 ? null : rawFinalWeight / 10,
    samples: samples,
  );
}

// Phase transitions are stored in the header as (sample index, name) — the
// name applies from that index until the next transition.
class _Transition {
  const _Transition(this.sampleIndex, this.name, this.reason);
  final int sampleIndex;
  final String name;

  /// Why the PREVIOUS phase ended (code, 0 = unknown).
  final int reason;
}

// Start of the phase transitions in the header, right after finalWeight.
const _transitionsBase = 110;

List<_Transition> _phaseTransitions(Uint8List bytes, ByteData data) {
  const stride = 29; // uint16 index, uint8 phase, uint8 reason, char[25]
  const maxCount = 12;
  final count = data
      .getUint8(_transitionsBase + maxCount * stride)
      .clamp(0, maxCount);
  final result = <_Transition>[];
  for (var i = 0; i < count; i++) {
    final at = _transitionsBase + i * stride;
    final name = _string(bytes, at + 4, 25);
    if (name.isEmpty) continue;
    result.add(
      _Transition(
        data.getUint16(at, Endian.little),
        name,
        data.getUint8(at + 3),
      ),
    );
  }
  return result;
}

String? _stageAt(List<_Transition> transitions, int sampleIndex) {
  String? name;
  for (final t in transitions) {
    if (t.sampleIndex > sampleIndex) break;
    name = t.name;
  }
  return name;
}

// Fixed char fields are null-terminated and zero-padded.
String _string(Uint8List bytes, int offset, int maxLength) {
  final end = (offset + maxLength).clamp(0, bytes.length);
  if (offset >= end) return '';
  var stop = offset;
  while (stop < end && bytes[stop] != 0) {
    stop++;
  }
  // The firmware writes plain ASCII; a broken byte should still not break
  // the import.
  return utf8.decode(bytes.sublist(offset, stop), allowMalformed: true).trim();
}

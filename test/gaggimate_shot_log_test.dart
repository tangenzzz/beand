import 'dart:io';

import 'package:beand/machines/gaggimate/gaggimate_shot_log.dart';
import 'package:flutter_test/flutter_test.dart';

// The fixtures are real files from the simulator, fetched via
// GET /api/history/index.bin and /api/history/000002.slog.
void main() {
  test('reads the simulator index.bin', () {
    final bytes = File('test/fixtures/gaggimate_history_index.bin')
        .readAsBytesSync();
    final entries = parseGaggiMateIndex(bytes);

    expect(entries, hasLength(3));
    final first = entries.first;
    expect(first.id, 0);
    expect(first.durationMs, 27500);
    expect(first.profileId, '5DORMxzTwa');
    expect(first.profileName, 'Copy of Default');
    expect(first.avgTemp, closeTo(92.7, 0.001));
    expect(first.maxPressure, closeTo(10.0, 0.001));
    expect(first.avgFlow, closeTo(2.46, 0.001));
    expect(first.completed, isTrue);
    expect(first.deleted, isFalse);
    // Without a scale the machine weighs nothing — 0 must not arrive as 0 g.
    expect(first.finalWeight, isNull);
    expect(first.fileName, '000000.slog');
    expect(entries.map((e) => e.id), [0, 1, 2]);
  });

  test('reads a simulator .slog', () {
    final bytes = File('test/fixtures/gaggimate_shot_000002.slog')
        .readAsBytesSync();
    final log = parseGaggiMateShotLog(bytes);

    expect(log.version, 7);
    expect(log.profileId, '5DORMxzTwa');
    expect(log.profileName, startsWith('Copy of Default'));
    expect(log.durationMs, 27140);
    expect(log.samples, hasLength(102));

    final first = log.samples.first;
    expect(first.timeMs, 253);
    expect(first.targetTemp, closeTo(93.0, 0.001));
    expect(first.currentTemp, closeTo(93.0, 0.001));
    expect(first.pressure, closeTo(4.7, 0.001));
    expect(first.pumpFlow, closeTo(1.17, 0.001));

    // Time runs monotonically and ends at the total duration.
    var previous = -1;
    for (final s in log.samples) {
      expect(s.timeMs, greaterThan(previous));
      previous = s.timeMs;
    }
    expect(log.samples.last.timeMs, lessThanOrEqualTo(log.durationMs));

    expect(log.targetTemp, closeTo(93.0, 0.001));
    expect(log.averageTemp, closeTo(92.7, 0.5));

    // The simulator has no BLE scale: no weight, only the volumetric
    // estimate.
    expect(first.scaleConnected, isFalse);

    // Phase names come from the transitions in the header.
    final stages = {
      for (final s in log.samples)
        if (s.stage != null) s.stage!,
    };
    expect(stages, isNotEmpty);
  });

  test('throws on foreign data instead of misreading it', () {
    expect(
      () => parseGaggiMateIndex(File('pubspec.yaml').readAsBytesSync()),
      throwsA(isA<GaggiMateShotLogException>()),
    );
    expect(
      () => parseGaggiMateShotLog(File('pubspec.yaml').readAsBytesSync()),
      throwsA(isA<GaggiMateShotLogException>()),
    );
  });
}

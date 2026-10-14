import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/machines/gaggimate/gaggimate_shot_log.dart';
import 'package:beand/models/history_import.dart';
import 'package:beand/models/profile_detail.dart';
import 'package:beand/models/shot_facts.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixed findings without AI. The cases come from a comparison with 20 real
// shots: Soup and lever profiles run through "as planned", ramps are
// measured against the target at the respective time, a limit that kicks
// in is not worth a notice.

var _id = 0;

/// Data points of a stage, every 250 ms, values as a function of the time
/// in the stage.
List<ShotReading> _stage(
  String name,
  double fromS,
  double toS, {
  required double Function(double t) p,
  required double Function(double t) f,
  required double Function(double t) w,
}) => [
  for (var t = fromS; t <= toS + 1e-9; t += 0.25)
    ShotReading(
      id: _id++,
      shotId: 1,
      timeMs: (t * 1000).round(),
      pressure: p(t - fromS),
      flow: f(t - fromS),
      weight: w(t),
      stage: name,
    ),
];

ProfileDetail _profile(List<Map<String, Object?>> stages, {num weight = 36}) =>
    ProfileDetail.fromJson({
      'id': 'x',
      'name': 'Test',
      'temperature': 93,
      'final_weight': weight,
      'stages': stages,
    });

Map<String, Object?> _st(
  String name,
  String type,
  List<List<num>> points, {
  List<Map<String, Object?>> exits = const [],
  List<Map<String, Object?>> limits = const [],
}) => {
  'name': name,
  'type': type,
  'dynamics': {'points': points, 'over': 'time', 'interpolation': 'linear'},
  'exit_triggers': exits,
  'limits': limits,
};

Map<String, Object?> _exit(String type, num value, {bool relative = true}) => {
  'type': type,
  'value': value,
  'relative': relative,
  'comparison': '>=',
};

void main() {
  test('Soup: low pressure, ends by weight — as planned', () {
    final readings = [
      ..._stage('Fill', 0, 6, p: (_) => 0.3, f: (_) => 1, w: (t) => t),
      ..._stage(
        'Percolation',
        6.25,
        15,
        p: (_) => 2.2,
        f: (_) => 5,
        w: (t) => 6 + (t - 6) * 3.5,
      ),
    ];
    final facts = computeShotFacts(
      readings: readings,
      finalWeight: 36.6,
      profile: _profile([
        _st(
          'Fill',
          'flow',
          [
            [0, 1],
          ],
          exits: [_exit('weight', 6, relative: false)],
          limits: [
            {'type': 'pressure', 'value': 0.5},
          ],
        ),
        _st(
          'Percolation',
          'flow',
          [
            [0, 5],
          ],
          limits: [
            {'type': 'pressure', 'value': 6},
          ],
        ),
      ]),
    );
    final f = facts.findings;
    expect(f, hasLength(1));
    expect(f.single.severity, FindingSeverity.ok);
    expect(f.single.text, 'Ran as planned · 36.6 g of 36 g');
    expect(facts.factSheet(), contains('Fill [flow]: ended: PLANNED'));
    expect(facts.factSheet(), contains('(weight ≥ 6 g)'));
  });

  test('short texts per stage: target and result', () {
    final readings = [
      ..._stage('Fill', 0, 6, p: (_) => 0.3, f: (_) => 1, w: (t) => t),
      ..._stage(
        'Percolation',
        6.25,
        15,
        p: (_) => 2.2,
        f: (_) => 5,
        w: (t) => 6 + (t - 6) * 3.5,
      ),
    ];
    final facts = computeShotFacts(
      readings: readings,
      finalWeight: 36.6,
      profile: _profile([
        _st(
          'Fill',
          'flow',
          [
            [0, 1],
            [5, 1.5],
          ],
          exits: [_exit('weight', 6, relative: false)],
          limits: [
            {'type': 'pressure', 'value': 0.5},
          ],
        ),
        _st(
          'Percolation',
          'flow',
          [
            [0, 5],
          ],
          limits: [
            {'type': 'pressure', 'value': 6},
          ],
        ),
      ]),
    );
    final fill = facts.stages.first, perc = facts.stages.last;
    expect(fill.goalText, 'Flow 1 → 1.5 ml/s · max 0.5 bar · until 6 g');
    expect(
      fill.resultText(facts),
      'Reached 6 g in 6 s · Ø 1 ml/s · max 0.3 bar',
    );
    expect(perc.goalText, 'Flow 5 ml/s · max 6 bar · until the target weight');
    expect(
      perc.resultText(facts),
      'Ended at 36.6 / 36 g · Ø 5 ml/s · max 2.2 bar',
    );
    expect(perc.severity, FindingSeverity.ok);
  });

  test('exit at the transition: the satisfying point already carries the '
      'next stage', () {
    // Pressure rises to 1.4, only the first point of "Main" has 1.5 bar.
    final readings = [
      ..._stage('Fill', 0, 3, p: (t) => t * 0.45, f: (_) => 2, w: (_) => 0),
      ..._stage(
        'Main',
        3.25,
        20,
        p: (_) => 1.5 + 7,
        f: (_) => 2,
        w: (t) => (t - 3) * 2,
      ),
    ];
    final facts = computeShotFacts(
      readings: readings,
      finalWeight: 34.5,
      profile: _profile([
        _st(
          'Fill',
          'flow',
          [
            [0, 2],
          ],
          exits: [_exit('pressure', 1.5)],
        ),
        _st('Main', 'pressure', [
          [0, 8.5],
        ]),
      ]),
    );
    expect(facts.stages.first.exit, ExitKind.planned);
    expect(facts.stages.first.firedTrigger, 'pressure ≥ 1.5 bar');
  });

  test('stall: stage ends by time although hardly anything came out', () {
    final facts = computeShotFacts(
      readings: _stage(
        'Main',
        0,
        20,
        p: (_) => 9,
        f: (_) => 0.05,
        w: (t) => t * 0.01,
      ),
      profile: _profile([
        _st(
          'Main',
          'pressure',
          [
            [0, 9],
          ],
          exits: [_exit('time', 20), _exit('weight', 36, relative: false)],
        ),
      ]),
    );
    expect(facts.findings.first.severity, FindingSeverity.problem);
    expect(facts.findings.first.text, startsWith('Stall in Main'));
  });

  test('channeling: pressure drops, flow rises, with a constant target', () {
    final facts = computeShotFacts(
      readings: _stage(
        'Main',
        0,
        10,
        p: (t) => 9 - t * 0.3,
        f: (t) => 1.5 + t * 0.3,
        w: (t) => t * 3,
      ),
      profile: _profile([
        _st('Main', 'pressure', [
          [0, 9],
        ]),
      ]),
    );
    expect(
      facts.findings.map((f) => f.text),
      contains(startsWith('Channeling in Main: pressure fell 3 bar')),
    );
  });

  test('lever: intended pressure decline is not channeling, ramp is '
      'measured at the time', () {
    // Target 9 → 3 bar over 55 s; the shot follows exactly and ends after 10 s.
    final facts = computeShotFacts(
      readings: _stage(
        'Decline',
        0,
        10,
        p: (t) => 9 - t * 6 / 55,
        f: (t) => 1.5 + t * 0.2,
        w: (t) => t * 3,
      ),
      finalWeight: 30,
      profile: _profile([
        _st('Decline', 'pressure', [
          [0, 9],
          [55, 3],
        ]),
      ], weight: 30),
    );
    final decline = facts.stages.single;
    expect(decline.channeling, isFalse);
    expect(
      decline.offTarget,
      isFalse,
      reason: 'previously: target 6 (mean of points) instead of ~8 at runtime',
    );
    expect(facts.findings.single.severity, FindingSeverity.ok);
  });

  test('ramp-up does not count against the target', () {
    // 2 → 9 bar in 2 s, then 9 bar until the end.
    final facts = computeShotFacts(
      readings: _stage(
        'Up',
        0,
        8,
        p: (t) => t < 2 ? 2 + t * 3.5 : 9,
        f: (_) => 2,
        w: (t) => t,
      ),
      profile: _profile([
        _st('Up', 'pressure', [
          [0, 9],
        ]),
      ]),
    );
    expect(facts.stages.single.offTarget, isFalse);
  });

  test('a limit that kicks in explains the deviation — no notice, but in '
      'the fact sheet', () {
    final facts = computeShotFacts(
      readings: _stage('Pi', 0, 8, p: (_) => 0.3, f: (_) => 5, w: (t) => t),
      profile: _profile([
        _st(
          'Pi',
          'pressure',
          [
            [0, 0],
            [5, 3],
          ],
          limits: [
            {'type': 'flow', 'value': 5},
          ],
        ),
      ]),
    );
    expect(facts.findings.where((f) => f.text.startsWith('Pi')), isEmpty);
    expect(facts.factSheet(), contains('held at the 5 ml/s cap'));
  });

  test('target weight missed and stages never reached: notices', () {
    final facts = computeShotFacts(
      readings: _stage('A', 0, 10, p: (_) => 9, f: (_) => 2, w: (t) => t * 2),
      finalWeight: 20,
      profile: _profile([
        _st('A', 'pressure', [
          [0, 9],
        ]),
        _st('B', 'pressure', [
          [0, 6],
        ]),
      ]),
    );
    final texts = facts.findings.map((f) => f.text).toList();
    expect(texts, contains('Stopped at 20 g, 44.4 % under the 36 g target'));
    expect(texts, contains('Never reached: B'));
  });

  test('without a profile: only what the curve tells', () {
    final facts = computeShotFacts(
      readings: _stage('Brew', 0, 10, p: (_) => 9, f: (_) => 2, w: (t) => t),
    );
    expect(facts.hasProfile, isFalse);
    expect(facts.findings.single.text, 'No problems seen in the curve');
    expect(facts.factSheet(), contains('No profile available'));
  });

  group('GaggiMate', () {
    // Like the firmware's default profile: pump 100 %, ends after 28 s or
    // at 36 g.
    final defaultProfile = jsonEncode({
      'id': 'd',
      'label': 'Default',
      'temperature': 93,
      'phases': [
        {
          'name': 'Brew',
          'phase': 'brew',
          'duration': 28,
          'pump': 100,
          'transition': {'type': 'instant', 'duration': 0},
          'targets': [
            {'type': 'volumetric', 'operator': 'gte', 'value': 36},
          ],
        },
      ],
    });

    test('profile is translated, "gte" becomes ">="', () {
      final detail = parseShotProfile(defaultProfile)!;
      expect(detail.finalWeight, 36);
      final weight = detail.stages.single.exitTriggers.last;
      expect(weight.type, 'weight');
      expect(weight.comparison, '>=');
    });

    test('weight target skipped: 36 g after 14 s, ends only after 28 s', () {
      final facts = computeShotFacts(
        readings: _stage(
          'Brew',
          0,
          28,
          p: (_) => 9.5,
          f: (_) => 2.5,
          w: (t) => t * 2.5,
        ),
        finalWeight: 70,
        profile: parseShotProfile(defaultProfile),
      );
      final brew = facts.stages.single;
      expect(brew.firedType, 'time');
      expect(brew.ignoredWeight!.$1, 36);
      expect(brew.ignoredWeight!.$2, closeTo(14, 0.5));
      expect(brew.severity, FindingSeverity.note);
      expect(
        facts.findings.map((f) => f.text),
        contains(startsWith('Brew: 36 g was reached at 14')),
      );
    });

    test('weight target kicks in: no notice', () {
      final facts = computeShotFacts(
        readings: _stage(
          'Brew',
          0,
          14.5,
          p: (_) => 9.5,
          f: (_) => 2.5,
          w: (t) => t * 2.5,
        ),
        finalWeight: 36.3,
        profile: parseShotProfile(defaultProfile),
      );
      expect(facts.stages.single.ignoredWeight, isNull);
      expect(facts.stages.single.firedType, 'weight');
    });

    test('recording: exit reason and scale per phase', () {
      final log = parseGaggiMateShotLog(
        File('test/fixtures/gaggimate_shot_000002.slog').readAsBytesSync(),
      );
      expect(log.phaseExits, hasLength(1));
      final brew = log.phaseExits.single;
      expect(brew.stage, 'Brew');
      expect(brew.reason, 'time');
      expect(brew.scaleConnected, isFalse);
    });

    test('reason from the machine beats the estimate; without a scale the '
        'notice says so', () {
      final facts = computeShotFacts(
        readings: _stage(
          'Brew',
          0,
          28,
          p: (_) => 9.5,
          f: (_) => 2.5,
          w: (t) => t * 2.5,
        ),
        finalWeight: 70,
        profile: parseShotProfile(defaultProfile),
        machineExits: parseStageExits(
          jsonEncode([
            {'stage': 'Brew', 'reason': 'time', 'pumped': 0, 'scale': false},
          ]),
        ),
      );
      final brew = facts.stages.single;
      expect(brew.firedType, 'time');
      expect(
        facts.findings.map((f) => f.text),
        contains(
          endsWith(
            'no scale was connected, the weight was only '
            'estimated',
          ),
        ),
      );
    });

    test('pumped, abort and safety shutoff', () {
      ShotFacts run(String reason) => computeShotFacts(
        readings: _stage('Fill', 0, 6, p: (_) => 1, f: (_) => 8, w: (_) => 0),
        profile: _profile([
          _st(
            'Fill',
            'flow',
            [
              [0, 8],
            ],
            exits: [
              _exit('time', 12),
              {
                'type': 'pumped',
                'value': 50,
                'relative': false,
                'comparison': '>=',
              },
            ],
          ),
        ]),
        machineExits: [
          MachineStageExit(stage: 'Fill', reason: reason, pumped: 50.4),
        ],
      );
      final pumped = run('pumped').stages.single;
      expect(pumped.exit, ExitKind.planned);
      expect(pumped.firedTrigger, 'pumped ≥ 50 ml water');
      expect(
        pumped.resultText(run('pumped')),
        startsWith('Pumped 50.4 ml in 6 s'),
      );
      final aborted = run('aborted');
      expect(
        aborted.stages.single.resultText(aborted),
        startsWith('Stopped by hand after 6 s'),
      );
      final safety = run('safety').stages.single;
      expect(safety.exit, ExitKind.backstop);
      expect(safety.severity, FindingSeverity.problem);
    });

    test('pause with pump 0 is not a stall', () {
      final facts = computeShotFacts(
        readings: _stage('Bloom', 0, 10, p: (_) => 1, f: (_) => 0, w: (_) => 2),
        profile: _profile([
          _st(
            'Bloom',
            'flow',
            [
              [0, 0],
            ],
            exits: [_exit('time', 10), _exit('pressure', 3, relative: false)],
          ),
        ]),
      );
      expect(facts.stages.single.stalled, isFalse);
    });
  });

  group('Profile at brew time', () {
    test('from the History entry, without image and authors', () {
      final json = compactShotProfile({
        'name': 'Soup',
        'display': {'image': '/x.png'},
        'previous_authors': [
          {'name': 'a'},
        ],
        'author_id': 'id',
        'db_key': 3,
        'stages': [
          {'name': 'A'},
        ],
        'variables': [],
      })!;
      final m = jsonDecode(json) as Map;
      expect(m.keys, unorderedEquals(['name', 'stages', 'variables']));
      expect(
        compactShotProfile({'name': 'kurz'}),
        isNull,
        reason: 'without stages save nothing',
      );
    });

    test('backfill only hits shots without a profile; the shot version beats '
        "today's", () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final a = await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 1),
          externalId: const Value('a'),
          profileName: const Value('Soup'),
        ),
        const [],
      );
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 2),
          externalId: const Value('b'),
          profileJson: const Value('{"keep":true}'),
        ),
        const [],
      );
      await db.backfillShotProfiles({'a': '{"v":"shot"}', 'b': '{"v":"x"}'});
      final shots = {
        for (final s in await db.select(db.shots).get()) s.externalId: s,
      };
      expect(shots['a']!.profileJson, '{"v":"shot"}');
      expect(shots['b']!.profileJson, '{"keep":true}');

      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'p',
          name: 'Soup',
          json: '{"v":"today"}',
          fetchedAt: DateTime(2026, 10, 7),
        ),
      );
      final shotA = shots['a']!;
      expect((await profileJsonForShot(db, shotA)).fromShot, isTrue);
      final noShotProfile = shotA.copyWith(profileJson: const Value(null));
      final today = await profileJsonForShot(db, noShotProfile);
      expect(today.json, '{"v":"today"}');
      expect(today.fromShot, isFalse);
      expect(a, isPositive);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:beand/models/profile_draft.dart';
import 'package:beand/models/profile_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The sample profile comes from the official schema repo
// (MeticulousHome/espresso-profile-schema). It is our touchstone for the
// round trip: as long as we cannot test against the real machine, it is
// the only hard proof that we get the format right.
Map<String, dynamic> _example() => jsonDecode(
  File('test/fixtures/meticulous_example_profile.json').readAsStringSync(),
) as Map<String, dynamic>;

ProfileDraft _draftWith(List<DraftStage> stages) => ProfileDraft(
  id: newUuid(),
  name: 'Test',
  author: 'tester',
  authorId: newUuid(),
  temperature: 92,
  finalWeight: 40,
  stages: stages,
);

void main() {
  group('Round trip', () {
    test('sample profile comes back out unchanged', () {
      final original = _example();
      final back = ProfileDraft.fromJson(original).toJson();

      // Key order may differ, the content may not.
      expect(_sorted(back), _sorted(original));
    });

    test('variable bindings stay bindings', () {
      final draft = ProfileDraft.fromJson(_example());

      // Stage 2 points to $pressure_1 with its only point.
      final infusion = draft.stages[1];
      expect(infusion.points.single.y.isVariable, isTrue);
      expect(infusion.points.single.y.variableKey, 'pressure_1');

      // Resolved, this gives the variable's value — but the reference is
      // still what gets stored, not the number.
      expect(infusion.points.single.y.resolve(draft.variables), 8);
      expect((infusion.toJson()['dynamics'] as Map)['points'], [
        [0, '\$pressure_1'],
      ]);
    });

    test('unknown fields survive editing', () {
      final original = _example()..['something_new'] = 'keep me';
      (original['stages'] as List).first['future_field'] = 42;

      final draft = ProfileDraft.fromJson(original);
      draft.name = 'Umbenannt';
      final back = draft.toJson();

      expect(back['something_new'], 'keep me');
      expect((back['stages'] as List).first['future_field'], 42);
      expect(back['name'], 'Umbenannt');
    });

    test('empty profile is complete enough for the machine', () {
      final json = ProfileDraft.empty().toJson();

      // The required fields according to schema.json.
      for (final key in [
        'name',
        'id',
        'author',
        'author_id',
        'temperature',
        'final_weight',
        'stages',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key missing');
      }
      // variables must be present even when empty, otherwise the
      // Meticulous app crashes when adding a variable.
      expect(json['variables'], isEmpty);
      // limits never null, always an array.
      expect((json['stages'] as List).first['limits'], isA<List>());
      // Every stage needs a unique key.
      expect((json['stages'] as List).first['key'], isNotEmpty);
    });
  });

  group('Rules — what trips up the machine', () {
    // Missing limits are safety warnings, not errors: Meticulous's official
    // sample profile itself ships a flow stage without a pressure limit.
    // Blocking would mean it could not be saved.
    test('flow stage without pressure limit reports a safety warning, not an error', () {
      final stage = ProfileDraft.defaultStage(1, 'flow')..limits.clear();
      final findings = checkStage(_draftWith([stage]), 0);

      expect(
        findings.where(
          (f) => f.isSafety && f.message.contains('pressure limit'),
        ),
        hasLength(1),
      );
      expect(findings.where((f) => f.blocksSaving), isEmpty);
    });

    test(
      'pressure stage from 6 bar without flow limit reports a safety warning',
      () {
        final stage = ProfileDraft.defaultStage(1, 'pressure')..limits.clear();
        final findings = checkStage(_draftWith([stage]), 0);

        expect(
          findings.where((f) => f.isSafety && f.message.contains('flow limit')),
          hasLength(1),
        );
        expect(findings.where((f) => f.blocksSaving), isEmpty);
      },
    );

    test('… below 6 bar nothing at all', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..limits.clear()
        ..points = [
          DraftPoint(const DraftValue.number(0), const DraftValue.number(3)),
          DraftPoint(const DraftValue.number(20), const DraftValue.number(3)),
        ];
      expect(
        checkStage(_draftWith([stage]), 0).where((f) => f.isSafety),
        isEmpty,
      );
    });

    test('interpolation "none" is caught, although the schema allows it', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..interpolation = 'none';
      expect(
        checkStage(
          _draftWith([stage]),
          0,
        ).where((f) => f.isError && f.message.contains('stalls')),
        hasLength(1),
      );
    });

    test('pressure above 15 bar is an error', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..points = [
          DraftPoint(const DraftValue.number(0), const DraftValue.number(16)),
        ];
      expect(
        checkStage(
          _draftWith([stage]),
          0,
        ).where((f) => f.isError && f.message.contains('15 bar')),
        hasLength(1),
      );
    });

    test(
      'non-last stage without exit condition: following stages never run',
      () {
        final first = ProfileDraft.defaultStage(1, 'pressure')
          ..exitTriggers.clear();
        final second = ProfileDraft.defaultStage(2, 'pressure');
        final findings = checkStage(_draftWith([first, second]), 0);

        expect(
          findings.where((f) => f.isSafety && f.message.contains('never run')),
          hasLength(1),
        );
      },
    );

    test('last stage without exit condition is only a hint', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..exitTriggers.clear();
      final findings = checkStage(_draftWith([stage]), 0);

      expect(findings.where((f) => f.isError), isEmpty);
      expect(findings.where((f) => !f.isError), isNotEmpty);
    });

    test('points running backwards are detected', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..points = [
          DraftPoint(const DraftValue.number(0), const DraftValue.number(6)),
          DraftPoint(const DraftValue.number(20), const DraftValue.number(6)),
          DraftPoint(const DraftValue.number(10), const DraftValue.number(6)),
        ];
      expect(
        checkStage(
          _draftWith([stage]),
          0,
        ).where((f) => f.isError && f.message.contains('backwards')),
        hasLength(1),
      );
    });
  });

  group('Rules — profile level', () {
    test('descending absolute weight triggers skip a stage', () {
      DraftStage withWeight(int n, double g) =>
          ProfileDraft.defaultStage(n, 'pressure')
            ..exitTriggers = [
              DraftTrigger(type: 'weight', value: DraftValue.number(g)),
            ];

      final draft = _draftWith([withWeight(1, 20), withWeight(2, 10)]);
      expect(
        checkProfile(draft)
            .where((f) => f.isError && f.message.contains('skipped')),
        hasLength(1),
      );
    });

    test('ascending weight triggers are fine', () {
      DraftStage withWeight(int n, double g) =>
          ProfileDraft.defaultStage(n, 'pressure')
            ..exitTriggers = [
              DraftTrigger(type: 'weight', value: DraftValue.number(g)),
            ];

      final draft = _draftWith([withWeight(1, 10), withWeight(2, 30)]);
      expect(
        checkProfile(draft).where((f) => f.message.contains('skipped')),
        isEmpty,
      );
    });

    test('reference to an undefined variable is an error', () {
      final stage = ProfileDraft.defaultStage(1, 'pressure')
        ..points = [
          DraftPoint(
            const DraftValue.number(0),
            const DraftValue.variable('ghost'),
          ),
        ];
      expect(
        checkProfile(_draftWith([stage]))
            .where((f) => f.isError && f.message.contains('ghost')),
        hasLength(1),
      );
    });

    test('duplicate stage keys are an error', () {
      final draft = _draftWith([
        ProfileDraft.defaultStage(1, 'pressure'),
        ProfileDraft.defaultStage(1, 'flow'),
      ]);
      expect(
        checkProfile(draft)
            .where((f) => f.isError && f.message.contains('unique')),
        isNotEmpty,
      );
    });

    test('missing name → error', () {
      final draft = _draftWith([ProfileDraft.defaultStage(1, 'pressure')])
        ..name = '';
      expect(
        checkProfile(draft)
            .where((f) => f.isError && f.message.contains('name')),
        hasLength(1),
      );
    });

    test('fresh profile from the editor has no errors once it has a name', () {
      final draft = ProfileDraft.empty()..name = 'Mein Profil';
      expect(checkProfile(draft).where((f) => f.isError), isEmpty);
    });

    // Cross-check against the REAL machine: this profile was built in the
    // editor, saved and then fetched back from the machine. It proves what
    // was previously only derived from third-party source code — above
    // all, that it accepts a photo as a base64 data URI and stores it under
    // its own path.
    test('profile the machine accepted from us stays clean', () {
      final raw = jsonDecode(
        File('test/fixtures/machine_roundtrip_apfel.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final draft = ProfileDraft.fromJson(raw);

      // The machine took over all required fields as we sent them.
      expect(draft.stages.map((s) => s.key), ['stage_1', 'stage_2']);
      expect(draft.authorId, isNotEmpty);
      expect(draft.variables, isEmpty);
      // The photo traveled as a data URI and now lives under the machine's
      // path.
      expect(draft.image, startsWith('/api/v1/profile/image/'));
      // Each stage limits the respective other quantity.
      expect(draft.stages[0].hasLimit('flow'), isTrue);
      expect(draft.stages[1].hasLimit('pressure'), isTrue);

      expect(checkProfile(draft), isEmpty, reason: 'no findings');
      expect(_sorted(draft.toJson()), _sorted(raw));
    });

    // The most important test in the set: what Meticulous itself ships as a
    // sample must be savable in our editor.
    test('the official sample profile does not block saving', () {
      final findings = checkProfile(ProfileDraft.fromJson(_example()));
      expect(
        findings.where((f) => f.blocksSaving),
        isEmpty,
        reason: findings.map((f) => f.message).join('\n'),
      );
    });
  });
}

// Make comparable: sort keys, normalize numbers to double
// (20 and 20.0 are the same in JSON).
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return [for (final v in value) _sorted(v)];
  if (value is num) return value.toDouble();
  return value;
}

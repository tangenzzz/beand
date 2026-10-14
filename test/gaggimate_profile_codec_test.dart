import 'dart:convert';
import 'dart:io';

import 'package:beand/machines/gaggimate/gaggimate_profile_codec.dart';
import 'package:beand/models/profile_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pro() => jsonDecode(
  File('test/fixtures/gaggimate_profile_pro.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _standard() {
  final raw = jsonDecode(
    File('test/fixtures/gaggimate_profiles_sim.json').readAsStringSync(),
  );
  return Map<String, dynamic>.from((raw as List).first as Map);
}

void main() {
  group('Reading GaggiMate profiles', () {
    test('Pro profile becomes stages with setpoint and limit', () {
      final draft = gaggiMateDraftFromJson(_pro());

      expect(draft.name, 'Adaptive v2');
      expect(draft.temperature, 93);
      expect(draft.stages, hasLength(6));

      // First phase: flow-controlled at 8 ml/s, for 5 s.
      final first = draft.stages.first;
      expect(first.name, 'Prefill');
      expect(first.type, 'flow');
      expect(first.points.last.y.resolve(draft.variables), 8);
      expect(
        first.exitTriggers.first.type,
        'time',
        reason: 'the phase duration is stored with the conditions',
      );
      expect(first.exitTriggers.first.value.resolve(draft.variables), 5);
      expect(first.exitTriggers.first.relative, isTrue);

      // "volumetric" is called "weight" on our side.
      final weights = [
        for (final s in draft.stages)
          for (final t in s.exitTriggers)
            if (t.type == 'weight') t.value.resolve(draft.variables),
      ];
      expect(weights, isNotEmpty);
      expect(draft.finalWeight, weights.last);
    });

    test('standard profile with bare pump power becomes "power"', () {
      final draft = gaggiMateDraftFromJson(_standard());

      expect(draft.name, 'Default');
      expect(draft.stages.single.type, 'power');
      expect(draft.stages.single.points.last.y.resolve(draft.variables), 100);
    });

    test('gte/lte become >= and <=', () {
      final draft = gaggiMateDraftFromJson(_pro());
      final comparisons = {
        for (final s in draft.stages)
          for (final t in s.exitTriggers) t.comparison,
      };
      expect(comparisons, everyElement(anyOf('>=', '<=')));
    });
  });

  group('Round-Trip', () {
    // The actual point of the codec: what the editor does not show
    // (valve state, phase group, transition type, favorite/selected) must
    // not get lost on save.
    test('Pro profile comes back out unchanged', () {
      final original = _pro();
      final back = gaggiMateJsonFromDraft(gaggiMateDraftFromJson(original));
      expect(_sorted(back), _sorted(original));
    });

    test('standard profile comes back out unchanged', () {
      final original = _standard();
      final back = gaggiMateJsonFromDraft(gaggiMateDraftFromJson(original));
      expect(_sorted(back), _sorted(original));
    });

    test('unknown firmware fields survive', () {
      final original = _pro()..['future_field'] = 'keep me';
      (original['phases'] as List).first['future_phase_field'] = 7;

      final back = gaggiMateJsonFromDraft(gaggiMateDraftFromJson(original));
      expect(back['future_field'], 'keep me');
      expect((back['phases'] as List).first['future_phase_field'], 7);
    });

    test('a change goes through, the rest stays', () {
      final original = _pro();
      final draft = gaggiMateDraftFromJson(original);
      draft.name = 'Umbenannt';
      draft.stages.first.name = 'Erste Phase';

      final back = gaggiMateJsonFromDraft(draft);
      expect(back['label'], 'Umbenannt');
      final phase = (back['phases'] as List).first as Map;
      expect(phase['name'], 'Erste Phase');
      // What the editor does not touch stays unchanged.
      expect(phase['valve'], 1);
      expect(phase['phase'], 'preinfusion');
    });

    test('our notes on the draft never go to a machine', () {
      final draft = gaggiMateDraftFromJson(_pro());
      // _source and _heldAs live in extra, but must not show up in the
      // JSON in case someone calls toJson() by accident.
      final meticulousShaped = draft.toJson();
      expect(meticulousShaped.keys.where((k) => k.startsWith('_')), isEmpty);
      for (final stage in meticulousShaped['stages'] as List) {
        expect(
          (stage as Map).keys.where((k) => k.toString().startsWith('_')),
          isEmpty,
        );
      }
    });
  });

  group('New profile', () {
    test('empty GaggiMate profile can be saved once it has a name', () {
      final draft = gaggiMateEmptyDraft()..name = 'Mein Profil';

      expect(
        checkProfile(draft).where((f) => f.blocksSaving),
        isEmpty,
        reason: checkProfile(draft).map((f) => f.message).join('\n'),
      );

      final json = gaggiMateJsonFromDraft(draft);
      expect(json['label'], 'Mein Profil');
      expect(json['phases'], hasLength(2));
      // The firmware needs duration, pump and transition per phase.
      for (final phase in json['phases'] as List) {
        final p = phase as Map;
        expect(p['duration'], isNotNull);
        expect(p['pump'], isNotNull);
        expect(p['transition'], isA<Map>());
        expect(p['targets'], isA<List>());
      }
    });
  });
}

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return [for (final v in value) _sorted(v)];
  if (value is num) return value.toDouble();
  return value;
}

import 'dart:convert';
import 'dart:io';

import 'package:beand/models/pourover_draft.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

// The rules the machine checks besides the schema (README of
// pour_over_profile_schema in meticulous-backend). Empty = it takes it.
List<String> machineRules(Map<String, dynamic> j) {
  final out = <String>[];
  final recipe = j['recipe'] as Map;
  final stages = (j['stages'] as List).cast<Map>();
  if (stages.isEmpty || stages.length > 5) out.add('1-5 pours');
  if (stages.first['starts_at_s'] != 0) out.add('first at 0');
  if (stages.map((s) => s['key']).toSet().length != stages.length) {
    out.add('keys unique');
  }
  var cumulative = 0.0;
  double? end;
  for (final s in stages) {
    final pour = s['pour'] as Map;
    final start = (s['starts_at_s'] as num).toDouble();
    if (end != null && start < end) out.add('overlap at $start');
    final water = (pour['water_g'] as num).toDouble();
    final duration = (pour['duration_s'] as num).toDouble();
    end = start + duration;
    cumulative += water;
    final flow = water / duration;
    final tolerance = flow * 0.02 > 0.1 ? flow * 0.02 : 0.1;
    if (((pour['flow_rate_g_s'] as num) - flow).abs() > tolerance) {
      out.add('flow of ${s['key']}');
    }
    if (((pour['target_cumulative_water_g'] as num) - cumulative).abs() > 0.1) {
      out.add('cumulative of ${s['key']}');
    }
  }
  if (((recipe['total_water_g'] as num) - cumulative).abs() > 0.1) {
    out.add('total water');
  }
  final target = recipe['target_total_time_s'] as num;
  if (target < end!) out.add('time before last pour ends');
  final max = recipe['target_total_time_max_s'] as num?;
  if (max != null && max < target) out.add('time span upside down');
  return out;
}

void main() {
  test('a new profile is one the machine takes', () {
    final d = PourOverDraft.empty()..name = 'Morning';
    final json = toMachineJson(d.toJson());
    expect(machineRules(json), isEmpty);
    expect(json['version'], 1);
    expect(json['brew_type'], 'pour_over');
    expect((json['recipe'] as Map)['total_water_g'], 240);
    expect(json.containsKey(PourOverDraft.appKey), isFalse);
    // Bloom 10 + wait 35 + pour 45 + drawdown 60.
    expect((json['recipe'] as Map)['target_total_time_s'], 150);
    expect((json['recipe'] as Map)['target_total_time_max_s'], 180);
  });

  test('any editing keeps the rules', () {
    final d = PourOverDraft.empty()..name = 'x';
    d.addPour();
    d.copyPour(0);
    d.pours[1].durationS = 7;
    d.pours[2].waterG = 33.3;
    d.setTotalWater(500);
    d.setTimeSpan(1, 2); // Earlier than the last pour's end: clamped.
    expect(machineRules(toMachineJson(d.toJson())), isEmpty);
    expect(d.totalWaterG, 500);
    expect(d.timeFromS, d.lastPourEndS);
    expect(d.drawdownS, 0);
    d.removePour(0);
    expect(machineRules(toMachineJson(d.toJson())), isEmpty);
  });

  test('at most five pours; the last one stays', () {
    final d = PourOverDraft.empty();
    for (var i = 0; i < 9; i++) {
      d.addPour();
    }
    expect(d.pours.length, maxPours);
    expect(d.canAddPour, isFalse);
    d.copyPour(0);
    expect(d.pours.length, maxPours);
    expect({for (final p in d.pours) p.key}.length, maxPours);
    while (d.pours.length > 1) {
      d.removePour(0);
    }
    d.removePour(0);
    expect(d.pours.length, 1);
    expect(d.pours.single.waitS, 0);
  });

  test('a new total is shared out; too little changes nothing', () {
    final d = PourOverDraft.empty(); // 45 + 195
    d.setTotalWater(480);
    expect([for (final p in d.pours) p.waterG], [90, 390]);
    d.setTotalWater(1);
    expect(d.totalWaterG, 480);
  });

  test('temperature per pour: exact goes out, let fall stays in the app', () {
    final d = PourOverDraft.empty()..name = 'x';
    d.pours[0]
      ..tempMode = PourTemp.exact
      ..tempC = 96;
    d.pours[1].tempMode = PourTemp.fall;
    final stored = d.toJson();
    final machine = toMachineJson(stored);
    final stages = (machine['stages'] as List).cast<Map>();
    expect(stages[0]['temperature_c'], 96);
    expect(stages[1].containsKey('temperature_c'), isFalse);

    final back = PourOverDraft.fromJson(stored);
    expect(back.pours[0].tempMode, PourTemp.exact);
    expect(back.pours[0].tempC, 96);
    expect(back.pours[1].tempMode, PourTemp.fall);

    // The recipe mentions it while brewing.
    final recipe = brewRecipeFromMeticulous(stored);
    expect(recipe.phases[0].note, contains('96 °C'));
    expect(recipe.phases[1].note, contains('Let the temperature fall'));
  });

  test(
    'the highlight color reaches the recipe, the chain stays in the app',
    () {
      final d = PourOverDraft.empty()
        ..name = 'x'
        ..accentColor = '#B5544B'
        ..chainId = 'c1'
        ..brewerName = 'V60'
        ..filterName = 'Paper';
      final stored = d.toJson();
      expect(brewRecipeFromMeticulous(stored).accentColor, '#B5544B');
      expect(brewRecipeFromMeticulous(stored).brewer, 'V60');
      final recipe = stored['recipe'] as Map;
      expect((recipe['filter'] as Map)['name'], 'Paper');
      expect(PourOverDraft.fromJson(stored).chainId, 'c1');
      expect(toMachineJson(stored).containsKey('beand'), isFalse);
    },
  );

  test('a profile from elsewhere reads back and loses nothing', () {
    final original = jsonDecode(
      File('test/fixtures/meticulous_pourover_example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final d = PourOverDraft.fromJson(original);
    expect(d.pours.map((p) => p.waitS), [35, 0]);
    expect(d.drawdownS, 95);
    expect(d.timeMaxS, 210);
    final again = toMachineJson(d.toJson());
    expect(machineRules(again), isEmpty);
    expect(again['author_id'], original['author_id']);
    final recipe = again['recipe'] as Map;
    // Not in the form, still there.
    expect((recipe['brewer'] as Map)['size'], '02');
    expect((recipe['filter'] as Map)['preparation'], 'Rinse before brewing');
    final bloom = ((again['stages'] as List).first as Map)['pour'] as Map;
    expect(bloom['flow_range_g_s'], [4, 6]);
    expect(bloom['pattern'], 'spiral_out');
    // Changed so it no longer fits: the flow range goes, not the profile.
    d.pours.first.durationS = 25;
    final changed = toMachineJson(d.toJson());
    final pour = ((changed['stages'] as List).first as Map)['pour'] as Map;
    expect(pour.containsKey('flow_range_g_s'), isFalse);
    expect(machineRules(changed), isEmpty);
  });

  test('the pour time reaches the recipe, also after storing it', () {
    final d = PourOverDraft.empty()..name = 'x';
    final recipe = brewRecipeFromMeticulous(d.toJson());
    expect([for (final p in recipe.phases) p.pourSeconds], [10, 45]);
    expect(recipe.phases[0].waitSeconds, 35);
  });

  test('what keeps it from being saved', () {
    final d = PourOverDraft.empty();
    expect(d.problems, ['Enter a name']);
    d
      ..name = 'x'
      ..drawdownS = 900;
    expect(d.problems, ['At most 10 minutes in total']);
  });
}

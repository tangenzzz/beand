import 'package:beand/models/brew_recipe.dart';
import 'package:beand/models/profile_detail.dart';
import 'package:beand/models/setpoint_curve.dart';
import 'package:beand/services/profile_share.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_detail.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileDetail _profile(
  List<Map<String, dynamic>> stages, {
  double weight = 36,
}) => ProfileDetail.fromJson({
  'id': 'a',
  'name': 'A',
  'temperature': 93,
  'final_weight': weight,
  'stages': stages,
});

Map<String, dynamic> _stage(
  String type,
  List<List<num>> points, {
  String over = 'time',
  String interpolation = 'linear',
  List<Map<String, dynamic>> exits = const [],
}) => {
  'name': type,
  'type': type,
  'dynamics': {'points': points, 'over': over, 'interpolation': interpolation},
  'exit_triggers': exits,
};

Map<String, dynamic> _time(num v, {bool relative = true}) => {
  'type': 'time',
  'value': v,
  'relative': relative,
};

void main() {
  test('stages follow each other, a time exit sets the length', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage(
          'flow',
          [
            [0, 2],
          ],
          exits: [_time(10)],
        ),
        _stage(
          'pressure',
          [
            [0, 6],
            [5, 9],
          ],
          exits: [_time(20)],
        ),
      ]),
    );
    expect(c.durationS, 30);
    expect(c.stages[1].startS, 10);
    expect(c.hasEstimate, isFalse);
    expect(c.segments.map((s) => s.type), ['flow', 'pressure']);
    final p = c.segments[1].points;
    expect([p.first.seconds, p.first.value], [10, 6]);
    // Reached after 5 s, held until the exit.
    expect([p[1].seconds, p[1].value], [15, 9]);
    expect([p.last.seconds, p.last.value], [30, 9]);
    expect(c.temperature, 93);
    expect(c.finalWeight, 36);
  });

  test('a time exit inside the curve cuts it at the right height', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage(
          'pressure',
          [
            [0, 0],
            [10, 10],
          ],
          exits: [_time(5)],
        ),
      ]),
    );
    expect(c.durationS, 5);
    expect(c.segments.single.points.last.value, 5);
  });

  test('a time exit counted from the shot start, not the stage', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage(
          'flow',
          [
            [0, 2],
          ],
          exits: [_time(10)],
        ),
        _stage(
          'flow',
          [
            [0, 4],
          ],
          exits: [_time(25, relative: false)],
        ),
      ]),
    );
    expect(c.durationS, 25);
    // Same quantity: a step at 10 s.
    final p = c.segments[1].points;
    expect([p[0].seconds, p[0].value], [10, 2]);
    expect([p[1].seconds, p[1].value], [10, 4]);
  });

  test('without any time the stage is an estimate', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage(
          'pressure',
          [
            [0, 9],
          ],
          exits: [
            {'type': 'weight', 'value': 36, 'relative': false},
          ],
        ),
      ]),
    );
    expect(c.durationS, unknownStageSeconds);
    expect(c.segments.single.estimated, isTrue);
    expect(c.segments.single.points.last.value, 9);
  });

  test(
    'a curve that then waits for a weight: known part solid, rest dashed',
    () {
      final c = SetpointCurve.fromProfile(
        _profile([
          _stage(
            'pressure',
            [
              [0, 2],
              [4, 9],
            ],
            exits: [
              {'type': 'weight', 'value': 36, 'relative': false},
            ],
          ),
        ]),
      );
      expect(c.durationS, unknownStageSeconds);
      expect(c.segments.map((s) => s.estimated), [false, true]);
      expect(c.segments[1].points.first.seconds, 4);
      expect(c.segments[1].points.first.value, 9);
    },
  );

  test('a curve over weight is stretched over the estimate', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage('flow', [
          [0, 1],
          [20, 3],
        ], over: 'weight'),
      ]),
    );
    final s = c.segments.single;
    expect(s.estimated, isTrue);
    expect(s.points.last.seconds, unknownStageSeconds);
    expect(s.points.last.value, 3);
  });

  test('no interpolation is drawn as steps', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage(
          'pressure',
          [
            [0, 2],
            [5, 8],
          ],
          interpolation: 'none',
          exits: [_time(5)],
        ),
      ]),
    );
    final p = c.segments.single.points;
    expect([for (final e in p) e.value], [2, 2, 8]);
    expect([for (final e in p) e.seconds], [0, 5, 5]);
  });

  test('a stage without points still takes its time, no line', () {
    final c = SetpointCurve.fromProfile(
      _profile([
        _stage('flow', const [], exits: [_time(7)]),
        _stage(
          'flow',
          [
            [0, 3],
          ],
          exits: [_time(3)],
        ),
      ]),
    );
    expect(c.durationS, 10);
    expect(c.segments.single.points.first.seconds, 7);
  });

  test('GaggiMate profiles come through the same way', () {
    final c = SetpointCurve.fromProfile(
      gaggiMateProfileDetail({
        'id': 'g',
        'label': 'G',
        'temperature': 92,
        'phases': [
          {
            'name': 'Pre',
            'duration': 8,
            'pump': {'target': 'pressure', 'pressure': 3, 'flow': 0},
          },
          {
            'name': 'Brew',
            'duration': 0,
            'pump': {'target': 'pressure', 'pressure': 9, 'flow': 0},
            'targets': [
              {'type': 'volumetric', 'operator': 'gte', 'value': 40},
            ],
          },
        ],
      }),
    );
    expect(c.stages.map((s) => s.name), ['Pre', 'Brew']);
    expect(c.durationS, 8 + unknownStageSeconds);
    expect(c.finalWeight, 40);
    expect(c.segments.last.estimated, isTrue);
  });

  test('a pour over shows running water and the flow of each pour', () {
    final c = SetpointCurve.fromRecipe(
      BrewRecipe(
        id: 'r',
        name: 'R',
        brewer: 'V60',
        doseG: 15,
        waterMl: 250,
        grindSize: 'medium',
        sourceName: 'x',
        phases: const [
          BrewPhase(
            label: 'Bloom',
            waterG: 50,
            waitSeconds: 30,
            pourSeconds: 10,
          ),
          BrewPhase(label: 'Main', waterG: 200, pourSeconds: 50),
        ],
        waterTempC: 94,
      ),
    );
    expect(c.durationS, 90);
    expect(c.stages[1].startS, 40);
    expect(c.flowUnit, 'g/s');
    final flow = c.segments.firstWhere((s) => s.type == 'flow').points;
    expect(flow[1].value, 5);
    expect(flow.any((p) => p.seconds == 40 && p.value == 4), isTrue);
    final water = c.segments.firstWhere((s) => s.type == 'weight').points;
    expect(water.last.value, 250);
    expect(water.last.seconds, 90);
    expect(c.temperature, 94);
  });

  test('profile file names stay safe', () {
    expect(profileFileName('Hoffmann V60'), 'Hoffmann-V60.json');
    expect(profileFileName('Café / 1:15?'), 'Café-1-15.json');
    expect(profileFileName(' *** '), 'profile.json');
  });
}

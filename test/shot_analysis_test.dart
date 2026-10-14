import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/ai/shot_analysis.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shot analysis. Checks what the model gets to see (thinned out, without
// clutter, with history of the same bean), that the answer is read
// leniently but not gullibly, and that the result is stored with the shot
// and displayed.

const _answer = {
  'summary': 'Ran fast at 22 s and tasted sour — under-extracted.',
  'extraction': 'under',
  'steps': [
    {'change': 'Grind finer', 'why': 'Flow peaked at 3.1 ml/s.'},
    {'change': 'Stop at 40 g', 'why': 'More yield lifts sweetness.'},
  ],
  'caveat': null,
};

ShotReading _r(int id, int ms, String stage, {double p = 6, double f = 2}) =>
    ShotReading(
      id: id,
      shotId: 1,
      timeMs: ms,
      pressure: p,
      flow: f,
      weight: ms / 1000,
      stage: stage,
    );

Shot _shot({
  int id = 1,
  DateTime? at,
  String? grind = '8.0',
  int? rating,
  String? notes,
}) => Shot(
  syncId: 'test',
  updatedAt: 0,
  syncState: SyncState.pending,
  id: id,
  timestamp: at ?? DateTime(2026, 10, 7, 9),
  doseGrams: 18,
  finalWeight: 36,
  durationMs: 22000,
  grindSize: grind,
  rating: rating,
  notes: notes,
  profileName: 'Classic',
  createdAt: DateTime(2026, 10, 7),
  machine: 'meticulous',
);

void main() {
  group('Input', () {
    test('Curve: at most N points per phase, edges stay, no retraction', () {
      final readings = [
        for (var i = 0; i < 100; i++) _r(i, i * 100, 'Preinfusion'),
        for (var i = 0; i < 5; i++) _r(100 + i, 10000 + i * 100, 'Extraction'),
        for (var i = 0; i < 30; i++) _r(200 + i, 11000 + i * 100, 'retracting'),
      ];
      final thin = thinReadings(readings, perPhase: 20);
      final pre = thin.where((r) => r.stage == 'Preinfusion').toList();
      expect(pre, hasLength(20));
      expect(pre.first.timeMs, 0);
      expect(pre.last.timeMs, 9900);
      expect(thin.where((r) => r.stage == 'Extraction'), hasLength(5));
      expect(thin.where((r) => r.stage == 'retracting'), isEmpty);
    });

    test('Task: figures, stages, profile without clutter, history', () {
      final task = shotAnalysisTask(
        ShotAnalysisInput(
          shot: _shot(rating: 2, notes: 'sour'),
          readings: [
            _r(1, 0, 'Preinfusion', p: 2),
            _r(2, 5000, 'Extraction', p: 9),
            _r(3, 9000, 'Extraction', p: 8),
          ],
          profileJson: jsonEncode({
            'id': 'abc',
            'name': 'Classic',
            'display': {'image': 'data:image/png;base64,AAAA'},
            'stages': [
              {'name': 'Extraction'},
            ],
          }),
          history: [
            _shot(id: 0, at: DateTime(2026, 10, 6), grind: '8.5', rating: 1),
          ],
        ),
      );
      expect(task, contains('Ratio: 1:2.0'));
      expect(task, contains('Grind setting: 8.0'));
      expect(task, contains('Stars: 2/5'));
      expect(task, contains('User notes: "sour"'));
      expect(task, contains('Taste: not rated'));
      expect(
        task,
        contains(
          'Extraction (5.0–9.0 s) — measured pressure avg 8.5 / max 9 bar',
        ),
      );
      expect(task, contains('Stage 1 "Extraction"'));
      expect(
        task,
        isNot(contains('base64')),
        reason: 'images only cost tokens',
      );
      expect(task, contains('Earlier shots of the same bean'));
      expect(task, contains('Date: 2026-10-06'));
      expect(task, contains('Grind setting: 8.5'));
    });

    test('Soup profile: variables resolved, target next to actual, low '
        'pressure is intended', () {
      final all = jsonDecode(
        File('test/fixtures/profiles_sample.json').readAsStringSync(),
      );
      final list = all is List ? all : (all as Map)['profiles'] as List;
      final soup = list.firstWhere((p) => '${p['name']}'.contains('Soup'));
      final task = shotAnalysisTask(
        ShotAnalysisInput(
          shot: _shot(),
          readings: [
            _r(1, 0, 'Puck Saturation', p: 0.4, f: 1),
            _r(2, 6000, 'Percolation', p: 2.1, f: 4.8),
            _r(3, 15000, 'Percolation', p: 2.4, f: 5),
          ],
          profileJson: jsonEncode(soup),
        ),
      );
      // ignore: avoid_print
      if (Platform.environment['SHOW_TASK'] != null) print(task);
      expect(task, isNot(contains(r'$flow')));
      expect(
        task,
        contains(
          'Stage 4 "Percolation": flow-controlled, target 5 ml/s; '
          'pressure capped at 6 bar; runs until the final weight',
        ),
      );
      expect(task, contains('ends when weight >= 6 g'));
      expect(
        task,
        contains('highest pressure the profile ever allows is 6 bar'),
      );
      expect(
        task,
        contains('(intended: flow-controlled, target 5 ml/s; pressure capped'),
      );
    });

    test('unknown profile is stated', () {
      final task = shotAnalysisTask(ShotAnalysisInput(shot: _shot()));
      expect(task, contains('Do not assume a classic 9-bar profile'));
    });

    test('missing curve is stated, not hidden', () {
      final task = shotAnalysisTask(ShotAnalysisInput(shot: _shot()));
      expect(task, contains('Not available for this shot.'));
    });

    test('system text: grind direction is unknown', () {
      expect(shotAnalysisSystemPrompt, contains('do NOT know'));
    });

    test('schema: every field required, closed', () {
      final schema = shotAnalysisSchema();
      expect(schema['required'], ['summary', 'extraction', 'steps', 'caveat']);
      expect(schema['additionalProperties'], false);
    });
  });

  group('Answer', () {
    test('at most three steps, steps without change are dropped', () {
      final a = ShotAnalysis.fromJson({
        'summary': ' ok ',
        'extraction': 'BALANCED',
        'steps': [
          {'change': '', 'why': 'leer'},
          {'change': 'a', 'why': '1'},
          {'change': 'b', 'why': '2'},
          {'change': 'c', 'why': '3'},
          {'change': 'd', 'why': '4'},
        ],
        'caveat': 'null',
      });
      expect(a.summary, 'ok');
      expect(a.extraction, ExtractionVerdict.balanced);
      expect([for (final s in a.steps) s.change], ['a', 'b', 'c']);
      expect(a.caveat, isNull);
    });

    test('save and read back; broken data gives null', () {
      final a = ShotAnalysis.fromJson(_answer);
      final back = ShotAnalysis.decode(a.encode())!;
      expect(back.summary, a.summary);
      expect(back.steps.last.why, 'More yield lifts sweetness.');
      expect(back.extraction, ExtractionVerdict.under);
      expect(ShotAnalysis.decode('{kaputt'), isNull);
      expect(ShotAnalysis.decode('[]'), isNull);
      expect(ShotAnalysis.decode(null), isNull);
    });
  });

  group('Shot detail', () {
    late AppDatabase db;
    late int requests;
    late String lastTask;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      requests = 0;
      lastTask = '';
    });

    http.Client provider() => MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      lastTask = jsonEncode(body['messages']);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'model': 'claude-opus-5',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': jsonEncode(_answer)},
            ],
          }),
        ),
        200,
      );
    });

    Future<AiSettings> settings({bool enabled = true}) async {
      final s = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: enabled);
      await s.setProvider(AiProvider.claude);
      await s.setKey(AiProvider.claude, 'sk-ant');
      return s;
    }

    Widget app(AiSettings ai, Widget home, {AppSettings? appSettings}) =>
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(
              value: appSettings ?? AppSettings(),
            ),
            ChangeNotifierProvider<AiSettings>.value(value: ai),
            Provider<AiService>.value(
              value: AiService(ai, httpClient: provider()),
            ),
          ],
          child: MaterialApp(theme: buildAppTheme(), home: home),
        );

    // Drift delivers stream results in real time.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(db.close);
    }

    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<int> insert(WidgetTester tester) async {
      late int id;
      await tester.runAsync(() async {
        final bean = await db.insertBean(
          BeansCompanion.insert(name: 'Guji Natural'),
        );
        await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 6),
            beanId: Value(bean.id),
            grindSize: const Value('9.0'),
            rating: const Value(1),
          ),
          const [],
        );
        id = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 7),
            beanId: Value(bean.id),
            doseGrams: const Value(18),
            finalWeight: const Value(36),
            grindSize: const Value('8.0'),
          ),
          const [],
        );
      });
      return id;
    }

    testWidgets('AI off: no section', (tester) async {
      bigScreen(tester);
      final id = await insert(tester);
      final ai = await settings(enabled: false);
      await tester.pumpWidget(app(ai, ShotDetailScreen(shotId: id)));
      await settle(tester);
      expect(find.text('AI ANALYSIS'), findsNothing);
      expect(find.text('Analyse this shot'), findsNothing);
      await teardown(tester);
    });

    testWidgets('Analyze: saved, displayed, history included', (tester) async {
      bigScreen(tester);
      final id = await insert(tester);
      final ai = await settings();
      await tester.pumpWidget(app(ai, ShotDetailScreen(shotId: id)));
      await settle(tester);

      expect(find.text('AI ANALYSIS'), findsOneWidget);
      await tester.tap(find.text('Analyse this shot'));
      await settle(tester);

      expect(requests, 1);
      expect(lastTask, contains('Guji Natural'));
      expect(lastTask, contains('Grind setting: 9.0'), reason: 'history');
      expect(find.text('Grind finer'), findsOneWidget);
      expect(find.text('Flow peaked at 3.1 ml/s.'), findsOneWidget);
      expect(find.textContaining('claude-opus-5'), findsOneWidget);

      late Shot stored;
      await tester.runAsync(
        () async => stored = (await db.watchShotEntry(id).first)!.shot,
      );
      expect(stored.aiAnalysisModel, 'claude-opus-5');
      expect(ShotAnalysis.decode(stored.aiAnalysis)!.steps, hasLength(2));
      expect(stored.aiAnalysedAt, isNotNull);
      await teardown(tester);
    });

    testWidgets('saved analysis costs nothing when opened', (tester) async {
      bigScreen(tester);
      final id = await insert(tester);
      await tester.runAsync(
        () => db.setShotAnalysis(
          id,
          json: ShotAnalysis.fromJson(_answer).encode(),
          model: 'gemini-2.5-flash',
        ),
      );
      final ai = await settings();
      await tester.pumpWidget(
        app(ai, ShotDetailScreen(shotId: id, analyse: true)),
      );
      await settle(tester);
      expect(requests, 0);
      expect(find.text('Stop at 40 g'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reanalyse')));
      await settle(tester);
      expect(requests, 1);
      expect(find.textContaining('claude-opus-5'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('AI ANALYSIS collapses; reopens from the Post-Shot card', (
      tester,
    ) async {
      bigScreen(tester);
      final id = await insert(tester);
      await tester.runAsync(
        () => db.setShotAnalysis(
          id,
          json: ShotAnalysis.fromJson(_answer).encode(),
          model: 'gemini-2.5-flash',
        ),
      );
      final ai = await settings();
      final appSettings = AppSettings();
      await tester.pumpWidget(
        app(ai, ShotDetailScreen(shotId: id), appSettings: appSettings),
      );
      await settle(tester);
      expect(find.text('Stop at 40 g'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle-AI ANALYSIS')));
      await settle(tester);
      expect(find.text('Stop at 40 g'), findsNothing);
      expect(find.byKey(const ValueKey('reanalyse')), findsNothing);
      expect(appSettings.expandAiAnalysis, isFalse);

      // "Show analysis" in the Post-Shot card opens the detail with
      // analyse: true — then it is expanded again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          ai,
          ShotDetailScreen(shotId: id, analyse: true),
          appSettings: appSettings,
        ),
      );
      await settle(tester);
      expect(find.text('Stop at 40 g'), findsOneWidget);
      expect(appSettings.expandAiAnalysis, isTrue);

      // AI off: neither heading nor arrow.
      await ai.setFeatureOn(AiFeature.shotAnalysis, false);
      await settle(tester);
      expect(find.text('AI ANALYSIS'), findsNothing);
      await teardown(tester);
    });

    testWidgets('stage details: expand and collapse via the stage name', (
      tester,
    ) async {
      bigScreen(tester);
      late int id;
      await tester.runAsync(() async {
        id = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 7),
            finalWeight: const Value(36),
            profileJson: Value(
              jsonEncode({
                'name': 'Flat',
                'temperature': 93,
                'final_weight': 36,
                'stages': [
                  {
                    'name': 'Main',
                    'type': 'flow',
                    'dynamics': {
                      'points': [
                        [0, 2],
                      ],
                      'over': 'time',
                    },
                    'exit_triggers': [],
                    'limits': [],
                  },
                ],
              }),
            ),
          ),
          [
            for (var t = 0; t <= 18000; t += 500)
              (shotId) => ShotReadingsCompanion.insert(
                shotId: shotId,
                timeMs: t,
                pressure: const Value(6),
                flow: const Value(2),
                weight: Value(t / 500),
                stage: const Value('Main'),
              ),
          ],
        );
      });
      final ai = await settings(enabled: false);
      final appSettings = AppSettings();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: appSettings),
            ChangeNotifierProvider<AiSettings>.value(value: ai),
            Provider<AiService>.value(value: AiService(ai)),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: ShotDetailScreen(shotId: id),
          ),
        ),
      );
      await settle(tester);

      const goal = 'Flow 2 ml/s · until the target weight';
      expect(find.text(goal), findsOneWidget);
      // Stage and summary are separated only by a short dash.
      final separator = tester.getSize(
        find.byKey(const ValueKey('stage-summary-separator')),
      );
      final row = tester.getSize(
        find.byKey(const ValueKey('stage-details-toggle')),
      );
      expect(separator.width, lessThan(row.width * 0.25));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stage-details-toggle')),
          matching: find.byIcon(Icons.expand_less),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('stage-details-toggle')));
      await settle(tester);
      expect(find.text(goal), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsWidgets);
      expect(appSettings.showStageDetails, isFalse);
      // One arrow for both: the summary is collapsed too.
      expect(find.textContaining('Ran as planned'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('stage-details-toggle')));
      await settle(tester);
      expect(find.text(goal), findsOneWidget);
      expect(find.textContaining('Ran as planned'), findsOneWidget);

      // Disabled in the settings: neither findings nor arrow.
      await appSettings.setShowShotFacts(false);
      await settle(tester);
      expect(find.textContaining('Ran as planned'), findsNothing);
      // … and the stage row no longer has an arrow.
      expect(find.byKey(const ValueKey('stage-details-toggle')), findsNothing);
      await teardown(tester);
    });

    testWidgets('from the Post-Shot card: starts by itself', (tester) async {
      bigScreen(tester);
      final id = await insert(tester);
      final ai = await settings();
      await tester.pumpWidget(
        app(ai, ShotDetailScreen(shotId: id, analyse: true)),
      );
      await settle(tester);
      expect(requests, 1);
      expect(find.text('Grind finer'), findsOneWidget);
      await teardown(tester);
    });
  });
}

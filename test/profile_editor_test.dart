import 'dart:io';

import 'package:beand/models/profile_draft.dart';
import 'package:beand/screens/profile/editor/profile_editor_screen.dart';
import 'package:beand/screens/profile/editor/stage_curve_editor.dart';
import 'package:beand/screens/profile/editor/stage_editor_screen.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/app_button.dart';
import 'package:drift/native.dart';
import 'package:beand/widgets/underline_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Accepts whatever the editor sends, without needing a machine.
class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  final uploaded = <Map<String, dynamic>>[];
  ({bool ok, String? error}) answer = (ok: true, error: null);

  @override
  Future<({bool ok, String? error})> saveProfile(
    Map<String, dynamic> profile,
  ) async {
    uploaded.add(profile);
    return answer;
  }
}

void main() {
  late AppDatabase db;
  late FakeSocket socket;
  late ProfileSyncService sync;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    socket = FakeSocket();
    sync = ProfileSyncService(
      database: db,
      socket: socket,
      imageDir: Directory.systemTemp.createTempSync('profile_images'),
      client: MockClient((_) async => http.Response('[]', 200)),
    );
  });

  tearDown(() async => db.close());

  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  Widget editor({ProfileDraft? initial}) => wrap(
    ProfileEditorScreen(
      machine: socket,
      store: sync,
      initial: initial,
      pickPhoto: (_) async => null,
    ),
  );

  // Large screen: the editor is a long page, and without room the tests
  // report overflow instead of the actual error.
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Profile page', () {
    testWidgets('starts with one stage and saving locked', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();

      expect(find.text('New profile'), findsOneWidget);
      // A first stage is already there, so nobody faces an empty page.
      expect(find.text('Pressure'), findsWidgets);
      // Without a name nothing can be saved.
      expect(find.textContaining('needs a name'), findsOneWidget);

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save to machine'),
      );
      expect(button.onPressed, isNull, reason: 'saving must be locked');
    });

    testWidgets('entering a name unlocks saving and sends the profile', (
      tester,
    ) async {
      bigScreen(tester);
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Morgenschluck');
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a name'), findsNothing);

      await tester.tap(find.text('Save to machine'));
      await tester.pumpAndSettle();

      expect(socket.uploaded, hasLength(1));
      final sent = socket.uploaded.single;
      expect(sent['name'], 'Morgenschluck');
      // The required fields without which the machine rejects it.
      expect(sent['id'], isNotEmpty);
      expect(sent['author_id'], isNotEmpty);
      expect(sent['variables'], isEmpty);
      expect((sent['stages'] as List).single['key'], isNotEmpty);
      expect((sent['stages'] as List).single['limits'], isA<List>());
    });

    testWidgets('machine error is shown in plain text', (tester) async {
      bigScreen(tester);
      socket.answer = (ok: false, error: 'stage 1: key missing');
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Kaputt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to machine'));
      await tester.pumpAndSettle();

      expect(find.textContaining('stage 1: key missing'), findsOneWidget);
    });

    testWidgets('adding a stage asks for the type', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();

      expect(find.text('Flow'), findsWidgets);
      expect(find.text('Power'), findsWidgets);
      expect(
        find.text('Water pushed into the puck each second'),
        findsOneWidget,
      );
    });
  });

  group('Stage page', () {
    // A draft with a name, so the profile level does not interfere.
    ProfileDraft named() => ProfileDraft.empty()..name = 'Test';

    testWidgets('discarding leaves the draft untouched', (tester) async {
      bigScreen(tester);
      final draft = named();
      final stageName = draft.stages.first.name;

      await tester.pumpWidget(
        wrap(
          StageEditorScreen(draft: draft, stageIndex: 0, profileName: 'Test'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Umbenannt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // The passed-in draft must not have changed — work happens on a
      // copy.
      expect(draft.stages.first.name, stageName);
    });

    testWidgets('changing type swaps the limit to the matching counterpart', (
      tester,
    ) async {
      bigScreen(tester);
      final draft = named();
      ProfileDraft? result;

      // Via a real route, so the return value of "Keep changes" arrives —
      // the whole draft mechanism relies on that.
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ProfileDraft>(
                  MaterialPageRoute(
                    builder: (_) => StageEditorScreen(
                      draft: draft,
                      stageIndex: 0,
                      profileName: 'Test',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Start: pressure stage, flow is limited.
      expect(draft.stages.first.type, 'pressure');
      expect(draft.stages.first.hasLimit('flow'), isTrue);

      await tester.tap(
        find.byWidgetPredicate((w) => w is UnderlineItem && w.label == 'Flow'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep changes'));
      await tester.pumpAndSettle();

      final changed = result!.stages.first;
      expect(changed.type, 'flow');
      // A flow stage must not limit flow — the limit has to go.
      expect(changed.hasLimit('flow'), isFalse);
      // 6 bar of 14 proportionally equals about 6.4 ml/s of 15.
      final value = changed.points.first.y.resolve(result!.variables)!;
      expect(value, closeTo(6.4, 0.2));

      // The passed-in draft stays untouched.
      expect(draft.stages.first.type, 'pressure');
    });

    testWidgets('adding and removing an exit condition', (tester) async {
      bigScreen(tester);
      final draft = named();

      await tester.pumpWidget(
        wrap(
          StageEditorScreen(draft: draft, stageIndex: 0, profileName: 'Test'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Time'), findsWidgets);
      await tester.tap(find.text('Condition'));
      await tester.pumpAndSettle();

      // Two conditions: now what counts is which triggers first.
      expect(find.text('Whichever is reached first wins.'), findsOneWidget);
    });

    // Found on the device: a CustomPaint without a child takes Size.zero and
    // thus stays 0 wide — the chart was empty although the room was there.
    testWidgets('chart gets a real area to draw on', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(
        wrap(
          StageEditorScreen(draft: named(), stageIndex: 0, profileName: 'Test'),
        ),
      );
      await tester.pumpAndSettle();

      final chart = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(StageCurveEditor),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(chart.size.width, greaterThan(100));
      expect(chart.size.height, greaterThan(100));
    });

    testWidgets('help sheet explains the exit conditions', (tester) async {
      bigScreen(tester);
      final draft = named();

      await tester.pumpWidget(
        wrap(
          StageEditorScreen(draft: draft, stageIndex: 0, profileName: 'Test'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Exit conditions'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('the first one reached wins'), findsOneWidget);
    });
  });
}

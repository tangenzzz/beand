import 'dart:convert';

import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_form_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Item 1 in the form: the "Fill from packaging or link" row, what it fills
// in and how to get rid of it again.
//
// The core is not the filling in, but the promise behind it: applied
// values are marked, nothing is saved silently, and "Undo" really restores
// everything — even a field that already contained something.

const _page =
    '<html><body><nav>Shop Abo Kontakt</nav>'
    '<h1>Kirinyaga AA</h1>'
    '<p>Kenya · Washed · SL28 · 250 g · 17,50 €</p>'
    '<p>Von der Kiangoi-Kooperative, geröstet für Espresso, '
    'Noten von Johannisbeere und Grapefruit.</p>'
    '<footer>Versand Impressum</footer></body></html>';

http.Client fakeProvider(Map<String, Object?> answer) =>
    MockClient((request) async {
      if (request.url.host == 'roesterei.de') {
        return http.Response.bytes(utf8.encode(_page), 200);
      }
      // As bytes: http.Response(String) encodes in Latin-1 when unspecified,
      // and "Rösterei" would then arrive as broken UTF-8 — a real provider
      // sends UTF-8 bytes.
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'model': 'claude-opus-5',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': jsonEncode(answer)},
            ],
          }),
        ),
        200,
      );
    });

Future<AiSettings> enabledSettings() async {
  final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
  await settings.setProvider(AiProvider.claude);
  await settings.setKey(AiProvider.claude, 'sk-ant');
  return settings;
}

Widget app(AppDatabase db, AiSettings ai, {http.Client? client, Bean? bean}) =>
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
        ChangeNotifierProvider<AiSettings>.value(value: ai),
        Provider<AiService>.value(value: AiService(ai, httpClient: client)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: BeanFormScreen(bean: bean),
      ),
    );

Color? labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label).first).style?.color;

Future<void> fillFromLink(WidgetTester tester) async {
  await tester.tap(find.text('Fill from packaging or link'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('From a shop link'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, 'roesterei.de/kenia');
  await tester.tap(find.text('Read'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppDatabase memoryDb(WidgetTester tester) {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    return db;
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('without AI set up the row does not exist at all', (
    tester,
  ) async {
    bigScreen(tester);
    // A button that first explains that it doesn't work is not a button.
    await tester.pumpWidget(
      app(memoryDb(tester), AiSettings(keyStore: InMemoryAiKeyStore())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fill from packaging or link'), findsNothing);
  });

  testWidgets('the main switch removes the row as well', (tester) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(app(memoryDb(tester), ai));
    await tester.pumpAndSettle();
    expect(find.text('Fill from packaging or link'), findsOneWidget);

    // Off means off throughout the app — the key stays in place anyway.
    await ai.setEnabled(false);
    await tester.pumpAndSettle();
    expect(find.text('Fill from packaging or link'), findsNothing);
    expect(ai.hasKey(AiProvider.claude), isTrue);
  });

  testWidgets('a disabled feature switch hides it again', (tester) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(app(memoryDb(tester), ai));
    await tester.pumpAndSettle();
    expect(find.text('Fill from packaging or link'), findsOneWidget);

    await ai.setFeatureOn(AiFeature.beanForm, false);
    await tester.pumpAndSettle();
    expect(find.text('Fill from packaging or link'), findsNothing);
  });

  testWidgets('fields read from a link are marked in the form', (tester) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    final before = labelColorProbe();
    await tester.pumpWidget(
      app(
        memoryDb(tester),
        ai,
        client: fakeProvider({
          'name': 'Kirinyaga AA',
          'roaster': 'Rösterei X',
          'country': 'Kenya',
          'processing': 'Washed',
          'variety': 'SL28',
          'weightGrams': 250,
          'cost': 17.5,
          'currency': 'EUR',
          'roastedFor': 'espresso',
          'taste': ['Johannisbeere', 'Grapefruit'],
        }),
      ),
    );
    await tester.pumpAndSettle();
    final plain = labelColor(tester, 'Country');

    await fillFromLink(tester);

    expect(find.text('Kirinyaga AA'), findsOneWidget);
    expect(find.text('Kenya'), findsOneWidget);
    expect(find.text('Johannisbeere, Grapefruit'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('17.5'), findsOneWidget);
    // The count says how much there is to check.
    expect(find.textContaining('9 fields read'), findsOneWidget);
    // Marked means: the label carries the accent color.
    expect(labelColor(tester, 'Country'), isNot(plain));
    expect(labelColor(tester, 'Producer'), plain);
    expect(before, isNull);
  });

  testWidgets('Undo also restores an overwritten field', (tester) async {
    bigScreen(tester);
    final db = memoryDb(tester);
    final ai = await enabledSettings();
    // A bean that already has something in it — exactly the case where an
    // irreversible change to the form hurts.
    final bean = await db
        .into(db.beans)
        .insertReturning(
          BeansCompanion.insert(
            name: 'Meine Bohne',
            country: const Value('Brazil'),
          ),
        );

    await tester.pumpWidget(
      app(
        db,
        ai,
        bean: bean,
        client: fakeProvider({'name': 'Kirinyaga AA', 'country': 'Kenya'}),
      ),
    );
    await tester.pumpAndSettle();
    final plain = labelColor(tester, 'Country');

    await fillFromLink(tester);
    expect(find.text('Kenya'), findsOneWidget);
    expect(find.text('Brazil'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Brazil'), findsOneWidget);
    expect(find.text('Meine Bohne'), findsOneWidget);
    expect(labelColor(tester, 'Country'), plain);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('typing yourself removes the marking', (tester) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(
      app(memoryDb(tester), ai, client: fakeProvider({'country': 'Kenya'})),
    );
    await tester.pumpAndSettle();
    final plain = labelColor(tester, 'Country');

    await fillFromLink(tester);
    expect(labelColor(tester, 'Country'), isNot(plain));

    await tester.enterText(
      find.ancestor(of: find.text('Kenya'), matching: find.byType(TextField)),
      'Kenia',
    );
    await tester.pumpAndSettle();
    // Touched means confirmed — without having to confirm anything.
    expect(labelColor(tester, 'Country'), plain);
  });

  testWidgets('the paste button takes the link from the clipboard', (
    tester,
  ) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(
      app(memoryDb(tester), ai, client: fakeProvider({'name': 'Kirinyaga AA'})),
    );
    await tester.pumpAndSettle();

    // On the phone the link practically always comes from here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'https://roesterei.de/kenia'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text('Fill from packaging or link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From a shop link'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Paste'));
    await tester.pumpAndSettle();
    expect(find.text('https://roesterei.de/kenia'), findsOneWidget);

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('Kirinyaga AA'), findsOneWidget);
  });

  testWidgets('if the model finds nothing, the form stays untouched', (
    tester,
  ) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(
      app(memoryDb(tester), ai, client: fakeProvider({'name': null})),
    );
    await tester.pumpAndSettle();

    await fillFromLink(tester);

    expect(find.textContaining('Nothing readable found'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  // Not an AI test, but noticed here and harmful exactly here: the weight
  // field showed round numbers truncated by the last digit — a 250 g bag
  // became "25".
  testWidgets('round numbers appear in full in the form', (tester) async {
    bigScreen(tester);
    final db = memoryDb(tester);
    final bean = await db
        .into(db.beans)
        .insertReturning(
          BeansCompanion.insert(
            name: 'Rund',
            weightGrams: const Value(250),
            cost: const Value(17.5),
          ),
        );
    await tester.pumpWidget(
      app(db, AiSettings(keyStore: InMemoryAiKeyStore()), bean: bean),
    );
    await tester.pumpAndSettle();

    expect(find.text('250'), findsOneWidget);
    expect(find.text('25'), findsNothing);
    expect(find.text('17.5'), findsOneWidget);
  });

  testWidgets('a price in a foreign currency is not filled in', (tester) async {
    bigScreen(tester);
    final ai = await enabledSettings();
    await tester.pumpWidget(
      app(
        memoryDb(tester),
        ai,
        client: fakeProvider({
          'name': 'Kirinyaga AA',
          'cost': 22,
          'currency': 'USD',
        }),
      ),
    );
    await tester.pumpAndSettle();

    await fillFromLink(tester);

    expect(find.text('22'), findsNothing);
    expect(find.textContaining('not in euro'), findsOneWidget);
  });
}

// Placeholder so the test above stays readable: before building there is
// no color to measure yet.
Color? labelColorProbe() => null;

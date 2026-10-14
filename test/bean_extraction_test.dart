import 'dart:convert';
import 'dart:typed_data';

import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_prompt.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/ai/bean_extraction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Item 1: read a bean from packaging or a link.
//
// The focus is on unpacking the response, not on sending: a model mostly
// sticks to the schema, and "mostly" is no basis when in the end a number
// goes into a weight field or a best-before date slips through as the
// roast date.

void main() {
  group('unpacking BeanDraft', () {
    test('the normal case', () {
      final draft = BeanDraft.fromJson({
        'name': 'Kirinyaga AA',
        'roaster': 'Rösterei X',
        'roastDate': '2026-09-28',
        'isBlend': false,
        'roastedFor': 'espresso',
        'country': 'Kenya',
        'processing': 'Washed',
        'variety': 'SL28',
        'producer': 'Kiangoi',
        'weightGrams': 250,
        'cost': 17.5,
        'currency': 'EUR',
        'taste': ['blackcurrant', 'grapefruit'],
      });

      expect(draft.name, 'Kirinyaga AA');
      expect(draft.roastDate, DateTime(2026, 9, 28));
      expect(draft.isBlend, isFalse);
      expect(draft.weightGrams, 250);
      expect(draft.costInEuro, 17.5);
      expect(draft.taste, ['blackcurrant', 'grapefruit']);
      expect(draft.isEmpty, isFalse);
    });

    test('empty answer stays empty and does not become text', () {
      final draft = BeanDraft.fromJson({
        'name': null,
        'country': '',
        'processing': '  ',
        // Some models write the word instead of the empty value.
        'variety': 'N/A',
        'producer': 'unknown',
        'taste': [],
      });
      expect(draft.isEmpty, isTrue);
      expect(draft.variety, isNull);
      expect(draft.producer, isNull);
    });

    test('numbers with a unit are read, not discarded', () {
      final draft = BeanDraft.fromJson({
        'weightGrams': '250 g',
        'cost': '17,50',
      });
      expect(draft.weightGrams, 250);
      expect(draft.cost, 17.5);
    });

    test('a roast date in the future is really the best-before date', () {
      final future = DateTime.now().add(const Duration(days: 200));
      final draft = BeanDraft.fromJson({
        'roastDate': future.toIso8601String().substring(0, 10),
      });
      // Better empty than a freshness ring pointing into the future.
      expect(draft.roastDate, isNull);
    });

    test('nonsensical dates are rejected', () {
      expect(BeanDraft.fromJson({'roastDate': 'September'}).roastDate, isNull);
      expect(BeanDraft.fromJson({'roastDate': '1998-01-01'}).roastDate, isNull);
    });

    test('roastedFor only from the three allowed values', () {
      expect(
        BeanDraft.fromJson({'roastedFor': 'Espresso'}).roastedFor,
        'espresso',
      );
      expect(BeanDraft.fromJson({'roastedFor': 'Moka'}).roastedFor, isNull);
    });

    test('price in a foreign currency does NOT go into the euro field', () {
      final draft = BeanDraft.fromJson({'cost': 22, 'currency': 'USD'});
      expect(draft.cost, 22);
      expect(draft.costInEuro, isNull);
      expect(draft.hasForeignPrice, isTrue);
    });

    test('without a currency the price counts as euros', () {
      final draft = BeanDraft.fromJson({'cost': 22});
      expect(draft.costInEuro, 22);
      expect(draft.hasForeignPrice, isFalse);
    });

    test('taste also as a comma-separated line', () {
      final draft = BeanDraft.fromJson({'taste': 'kirsche, kakao , '});
      expect(draft.taste, ['kirsche', 'kakao']);
    });

    test('isBlend also as a word', () {
      expect(BeanDraft.fromJson({'isBlend': 'blend'}).isBlend, isTrue);
      expect(BeanDraft.fromJson({'isBlend': 'single origin'}).isBlend, isFalse);
      expect(BeanDraft.fromJson({'isBlend': 'vielleicht'}).isBlend, isNull);
    });
  });

  group('Schema', () {
    test(
      'every field may be null — otherwise the model makes something up',
      () {
        final schema = beanDraftSchema();
        final properties = schema['properties'] as Map<String, Object?>;
        for (final entry in properties.entries) {
          if (entry.key == 'taste') continue; // list, may be empty
          expect(
            (entry.value as Map)['type'],
            contains('null'),
            reason: '${entry.key} must be allowed to stay empty',
          );
        }
        // Still, every field is in `required` — that is the form all three
        // providers go along with.
        expect(schema['required'], containsAll(properties.keys));
      },
    );

    test('the roast date carries the best-before warning in the schema', () {
      final roastDate =
          (beanDraftSchema()['properties'] as Map)['roastDate'] as Map;
      expect(roastDate['description'], contains('best-before'));
    });
  });

  group('reading a page', () {
    test('HTML becomes words, scripts and styles are dropped', () {
      final text = htmlToText('''
        <html><head><style>.a{color:red}</style>
        <script>var x = "Kenya";</script></head>
        <body><h1>Kirinyaga&nbsp;AA</h1><p>250&nbsp;g &ndash; 17,50&euro;</p>
        <div>Washed</div></body></html>
      ''');
      expect(text, contains('Kirinyaga AA'));
      expect(text, contains('17,50€'));
      expect(text, contains('Washed'));
      // The country name was ONLY in the script — it doesn't belong in the
      // text.
      expect(text, isNot(contains('var x')));
      expect(text, isNot(contains('color:red')));
    });

    test('block ends separate, otherwise everything sticks together', () {
      expect(htmlToText('<li>250 g</li><li>Natural</li>'), '250 g\nNatural');
    });

    test('the page is fetched with a recognizable browser', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes(
          utf8.encode(
            '<html><body><h1>Kirinyaga AA</h1>'
            '<p>Kenya, Washed, 250 g, geröstet am 28.09.2026, '
            'Noten von Johannisbeere und Grapefruit</p></body></html>',
          ),
          200,
        );
      });

      final text = await fetchReadableText(
        Uri.parse('https://roesterei.de/kenia'),
        client: client,
      );
      expect(text, contains('Kirinyaga AA'));
      // Without a recognizable browser many shops answer with a block page.
      expect(seen.headers['user-agent'], contains('Mozilla'));
    });

    test('a page without text is reported honestly, not sent', () async {
      final client = MockClient(
        (_) async => http.Response(
          '<html><body><div id="app"></div></body></html>',
          200,
        ),
      );
      await expectLater(
        fetchReadableText(Uri.parse('https://shop.de/x'), client: client),
        throwsA(
          isA<AiFailure>().having(
            (e) => e.message,
            'message',
            // The sentence must say what the user can do instead.
            contains('photo of the package'),
          ),
        ),
      );
    });

    test('404 is a network error, not an empty result', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      await expectLater(
        fetchReadableText(Uri.parse('https://shop.de/weg'), client: client),
        throwsA(
          isA<AiFailure>().having((e) => e.kind, 'kind', AiFailureKind.network),
        ),
      );
    });
  });

  group('extractBean', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AiSettings> configured() async {
      final settings = AiSettings(keyStore: InMemoryAiKeyStore());
      await settings.setProvider(AiProvider.claude);
      await settings.setKey(AiProvider.claude, 'sk-ant');
      return settings;
    }

    http.Response claudeOk(Map<String, Object?> data) => http.Response(
      jsonEncode({
        'model': 'claude-opus-5',
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(data)},
        ],
      }),
      200,
    );

    test('photo: image is sent, schema is enforced', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return claudeOk({'name': 'Kirinyaga AA', 'country': 'Kenya'});
      });

      final result = await AiService(await configured(), httpClient: client)
          .extractBean(
            image: AiImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/jpeg',
            ),
          );

      expect(result.draft.name, 'Kirinyaga AA');
      expect(result.schemaEnforced, isTrue);
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      expect((content.first as Map)['type'], 'image');
    });

    test('link: fetch the page first, then send the TEXT', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'roesterei.de') {
          // As bytes, not as a string: a server delivers bytes, and
          // http.Response(String) silently encodes in Latin-1 — it would
          // already have failed at the "€".
          return http.Response.bytes(
            utf8.encode(
              '<html><body><nav>Shop Kaffee Abo Kontakt</nav>'
              '<h1>Kirinyaga AA</h1>'
              '<p>Kenya · Washed · 250 g · 17,50 €</p>'
              '<p>SL28 und SL34 von der Kiangoi-Kooperative, geröstet für '
              'Espresso. Noten von Johannisbeere und Grapefruit.</p>'
              '<footer>Versand Impressum AGB</footer></body></html>',
            ),
            200,
          );
        }
        return claudeOk({'name': 'Kirinyaga AA', 'weightGrams': 250});
      });

      final result = await AiService(
        await configured(),
        httpClient: client,
      ).extractBean(url: Uri.parse('https://roesterei.de/kenia'));

      expect(result.draft.weightGrams, 250);
      expect(requests.length, 2);
      expect(requests.first.url.host, 'roesterei.de');
      // The model gets the page text — it can't fetch an address itself,
      // and a bare link would be an invitation to make things up.
      final body = jsonDecode(requests[1].body) as Map<String, Object?>;
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      final task = (content.last as Map)['text'] as String;
      expect(task, contains('Kirinyaga AA'));
      expect(task, contains('roesterei.de'));
      expect(body['messages'].toString(), isNot(contains('image')));
    });

    test('a dead page never reaches the model', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('nope', 404);
      });

      await expectLater(
        AiService(
          await configured(),
          httpClient: client,
        ).extractBean(url: Uri.parse('https://shop.de/weg')),
        throwsA(isA<AiFailure>()),
      );
      // Only the page fetch — no paid call to the provider.
      expect(requests.length, 1);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:beand/services/ai/ai_client.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_prompt.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/ai/gemini_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Tests of the AI foundation: schema, provider translation, error mapping,
// settings. All without network — the clients get a MockClient, and the
// assertions check what is REALLY in the request body. That's exactly where
// the three providers differ, and exactly where it would otherwise only
// show up for the user.

AiPrompt testPrompt({List<AiImage> images = const []}) => AiPrompt(
  system: 'You read coffee packaging.',
  task: 'Read the bean.',
  images: images,
  schema: aiObjectSchema({
    'name': aiField('string'),
    'country': aiNullable('string', description: 'Origin, null if unreadable'),
  }),
);

// Records every request and answers per script: one answer per call so the
// fallback levels can be tested.
class RecordingClient {
  RecordingClient(this.responses);

  final List<http.Response> responses;
  final requests = <http.Request>[];
  var _next = 0;

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final response = responses[_next.clamp(0, responses.length - 1)];
    _next++;
    return response;
  });

  Map<String, Object?> bodyOf(int index) =>
      jsonDecode(requests[index].body) as Map<String, Object?>;
}

http.Response claudeOk(String json) => http.Response(
  jsonEncode({
    'model': 'claude-opus-5',
    'stop_reason': 'end_turn',
    'content': [
      {'type': 'text', 'text': json},
    ],
    'usage': {'input_tokens': 42, 'output_tokens': 7},
  }),
  200,
);

void main() {
  group('Schema', () {
    test('every field is required and the object is closed', () {
      final schema = aiObjectSchema({
        'name': aiField('string'),
        'country': aiNullable('string'),
      });
      expect(schema['required'], ['name', 'country']);
      expect(schema['additionalProperties'], false);
    });

    test('what may be missing says so via the type null', () {
      expect(aiNullable('string')['type'], ['string', 'null']);
      expect(aiField('boolean')['type'], 'boolean');
      // Without a description there's no empty field in the schema either.
      expect(aiField('string').containsKey('description'), isFalse);
    });
  });

  group('Gemini-Schema', () {
    test(
      'types uppercase, nullability converted, additionalProperties gone',
      () {
        final converted = geminiSchema(
          aiObjectSchema({
            'name': aiField('string'),
            'country': aiNullable('string', description: 'Origin'),
          }),
        );

        expect(converted['type'], 'OBJECT');
        expect(converted.containsKey('additionalProperties'), isFalse);
        expect(converted['required'], ['name', 'country']);
        expect(converted['propertyOrdering'], ['name', 'country']);

        final properties = converted['properties'] as Map;
        expect((properties['name'] as Map)['type'], 'STRING');
        final country = properties['country'] as Map;
        expect(country['type'], 'STRING');
        expect(country['nullable'], isTrue);
        expect(country['description'], 'Origin');
      },
    );

    test('anyOf with null means the same as the type list', () {
      final converted = geminiSchema({
        'anyOf': [
          {'type': 'integer'},
          {'type': 'null'},
        ],
      });
      expect(converted['type'], 'INTEGER');
      expect(converted['nullable'], isTrue);
    });

    test('nested lists come along', () {
      final converted = geminiSchema(
        aiObjectSchema({
          'steps': aiArray(aiObjectSchema({'note': aiField('string')})),
        }),
      );
      final steps = (converted['properties'] as Map)['steps'] as Map;
      expect(steps['type'], 'ARRAY');
      expect((steps['items'] as Map)['type'], 'OBJECT');
      expect(
        (steps['items'] as Map).containsKey('additionalProperties'),
        isFalse,
      );
    });
  });

  group('extracting JSON', () {
    test('pure JSON', () {
      expect(HttpAiClient.extractJson('{"a":1}'), {'a': 1});
    });

    test('in fences and with a leading sentence', () {
      expect(
        HttpAiClient.extractJson(
          'Sure!\n```json\n{"a":1}\n```\nHope that helps',
        ),
        {'a': 1},
      );
    });

    test('no JSON is reported as badResponse, with an excerpt', () {
      expect(
        () => HttpAiClient.extractJson('I cannot read that label.'),
        throwsA(
          isA<AiFailure>()
              .having((e) => e.kind, 'kind', AiFailureKind.badResponse)
              .having((e) => e.message, 'message', contains('cannot read')),
        ),
      );
    });
  });

  group('Claude', () {
    AiConnection connection() => const AiConnection(
      provider: AiProvider.claude,
      apiKey: 'sk-ant-test',
      model: 'claude-opus-5',
      baseUrl: 'https://api.anthropic.com/v1',
    );

    test(
      'request carries header, model, enforced schema — image before text',
      () async {
        final recorder = RecordingClient([
          claudeOk('{"name":"Yirga","country":null}'),
        ]);
        final client = AiClient.forConnection(
          connection(),
          httpClient: recorder.client,
        );

        final result = await client.completeJson(
          testPrompt(
            images: [
              AiImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                mediaType: 'image/jpeg',
              ),
            ],
          ),
        );

        final request = recorder.requests.single;
        expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(request.headers['x-api-key'], 'sk-ant-test');
        expect(request.headers['anthropic-version'], '2023-06-01');

        final body = recorder.bodyOf(0);
        expect(body['model'], 'claude-opus-5');
        expect(
          ((body['output_config'] as Map)['format'] as Map)['type'],
          'json_schema',
        );
        final content =
            ((body['messages'] as List).first as Map)['content'] as List;
        expect((content.first as Map)['type'], 'image');
        expect((content.last as Map)['type'], 'text');
        // The schema is also in the request as plain text.
        expect((content.last as Map)['text'], contains('JSON Schema'));

        expect(result.data, {'name': 'Yirga', 'country': null});
        expect(result.model, 'claude-opus-5');
        expect(result.inputTokens, 42);
        expect(result.outputTokens, 7);
      },
    );

    test('Sonnet 5.5 is the default and asks for fallback on refusal; '
        'Haiku does not', () async {
      expect(AiProvider.claude.defaultModel, 'claude-sonnet-5-5');

      Future<RecordingClient> send(String model) async {
        final recorder = RecordingClient([
          claudeOk('{"name":"Yirga","country":null}'),
        ]);
        await AiClient.forConnection(
          AiConnection(
            provider: AiProvider.claude,
            apiKey: 'sk-ant-test',
            model: model,
            baseUrl: 'https://api.anthropic.com/v1',
          ),
          httpClient: recorder.client,
        ).completeJson(testPrompt());
        return recorder;
      }

      final sonnet = await send('claude-sonnet-5-5');
      expect(
        sonnet.requests.single.headers['anthropic-beta'],
        'server-side-fallback-2026-07-01',
      );
      expect(sonnet.bodyOf(0)['fallbacks'], 'default');

      final haiku = await send('claude-haiku-4-5');
      expect(
        haiku.requests.single.headers.containsKey('anthropic-beta'),
        isFalse,
      );
      expect(haiku.bodyOf(0).containsKey('fallbacks'), isFalse);
    });

    test(
      'if the provider rejects output_config, the retry comes without it',
      () async {
        final recorder = RecordingClient([
          http.Response(
            jsonEncode({
              'error': {
                'message': 'output_config is not supported for this model',
              },
            }),
            400,
          ),
          claudeOk('{"name":"Yirga","country":"Ethiopia"}'),
        ]);
        final client = AiClient.forConnection(
          connection(),
          httpClient: recorder.client,
        );

        final result = await client.completeJson(testPrompt());

        expect(recorder.requests.length, 2);
        expect(recorder.bodyOf(0).containsKey('output_config'), isTrue);
        expect(recorder.bodyOf(1).containsKey('output_config'), isFalse);
        expect(result.data['country'], 'Ethiopia');
      },
    );

    test('a wrong key is not retried', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'error': {'message': 'invalid x-api-key'},
          }),
          401,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );

      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>()
              .having((e) => e.kind, 'kind', AiFailureKind.auth)
              // The provider's message belongs in the message to the user.
              .having(
                (e) => e.message,
                'message',
                contains('invalid x-api-key'),
              ),
        ),
      );
      expect(recorder.requests.length, 1);
    });

    test('truncated answer reports the length, not "no JSON"', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'stop_reason': 'max_tokens',
            'content': [
              {'type': 'text', 'text': '{"name":"Yir'},
            ],
          }),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>().having(
            (e) => e.message,
            'message',
            contains('length limit'),
          ),
        ),
      );
    });

    test('refusal is not a format error', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({'stop_reason': 'refusal', 'content': []}),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>().having((e) => e.kind, 'kind', AiFailureKind.refused),
        ),
      );
    });

    test('model list comes from the provider', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'data': [
              {'id': 'claude-opus-5', 'display_name': 'Claude Opus 5'},
              {'id': 'claude-haiku-4-5', 'display_name': 'Claude Haiku 4.5'},
            ],
          }),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );

      final models = await client.listModels();
      expect(models.map((m) => m.id), ['claude-opus-5', 'claude-haiku-4-5']);
      expect(models.first.label, 'Claude Opus 5');
    });
  });

  group('Gemini', () {
    AiConnection connection() => const AiConnection(
      provider: AiProvider.gemini,
      apiKey: 'AIza-test',
      model: 'gemini-2.5-flash',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    );

    test('key in header, schema converted, model in the URL', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"name":"Yirga","country":"Ethiopia"}'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
            'modelVersion': 'gemini-2.5-flash-001',
            'usageMetadata': {'promptTokenCount': 9, 'candidatesTokenCount': 3},
          }),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );

      final result = await client.completeJson(testPrompt());

      final request = recorder.requests.single;
      expect(
        request.url.path,
        endsWith('/models/gemini-2.5-flash:generateContent'),
      );
      // Not as ?key= in the URL — that ends up in every log.
      expect(request.headers['x-goog-api-key'], 'AIza-test');
      expect(request.url.query, isEmpty);

      final config = recorder.bodyOf(0)['generationConfig'] as Map;
      expect(config['responseMimeType'], 'application/json');
      expect((config['responseSchema'] as Map)['type'], 'OBJECT');
      expect(result.model, 'gemini-2.5-flash-001');
      expect(result.inputTokens, 9);
    });

    test('a provider filter is a refusal', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'promptFeedback': {'blockReason': 'SAFETY'},
          }),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>().having((e) => e.kind, 'kind', AiFailureKind.refused),
        ),
      );
    });

    test('exhausted free tier is retryable and states the reason', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'error': {'message': 'Quota exceeded for quota metric'},
          }),
          429,
        ),
      ]);
      final client = AiClient.forConnection(
        connection(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>()
              .having((e) => e.kind, 'kind', AiFailureKind.rateLimit)
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.message, 'message', contains('Quota exceeded')),
        ),
      );
    });

    test(
      'models without generateContent are dropped from the selection',
      () async {
        final recorder = RecordingClient([
          http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash',
                  'displayName': 'Gemini 2.5 Flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/text-embedding-004',
                  'displayName': 'Embedding',
                  'supportedGenerationMethods': ['embedContent'],
                },
              ],
            }),
            200,
          ),
        ]);
        final client = AiClient.forConnection(
          connection(),
          httpClient: recorder.client,
        );

        final models = await client.listModels();
        // "models/" belongs in the list, not in the call.
        expect(models.map((m) => m.id), ['gemini-2.5-flash']);
      },
    );
  });

  group('OpenAI and Custom', () {
    AiConnection openai() => const AiConnection(
      provider: AiProvider.openai,
      apiKey: 'sk-test',
      model: 'gpt-5',
      baseUrl: 'https://api.openai.com/v1',
    );

    http.Response chatOk(String json) => http.Response(
      jsonEncode({
        'model': 'gpt-5',
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': json},
          },
        ],
        'usage': {'prompt_tokens': 11, 'completion_tokens': 4},
      }),
      200,
    );

    test('image as data URL, schema strict', () async {
      final recorder = RecordingClient([
        chatOk('{"name":"Yirga","country":null}'),
      ]);
      final client = AiClient.forConnection(
        openai(),
        httpClient: recorder.client,
      );

      await client.completeJson(
        testPrompt(
          images: [
            AiImage(bytes: Uint8List.fromList([9]), mediaType: 'image/png'),
          ],
        ),
      );

      final request = recorder.requests.single;
      expect(
        request.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer sk-test');

      final body = recorder.bodyOf(0);
      final format = body['response_format'] as Map;
      expect(format['type'], 'json_schema');
      expect((format['json_schema'] as Map)['strict'], isTrue);
      final content = ((body['messages'] as List)[1] as Map)['content'] as List;
      expect(
        ((content.first as Map)['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
    });

    test('three levels down until one cooperates', () async {
      final recorder = RecordingClient([
        http.Response(
          '{"error":{"message":"response_format unsupported"}}',
          400,
        ),
        http.Response('{"error":{"message":"json_object unsupported"}}', 400),
        chatOk('Here you go: {"name":"Yirga","country":null}'),
      ]);
      final client = AiClient.forConnection(
        const AiConnection(
          provider: AiProvider.compatible,
          apiKey: '',
          model: 'llama3',
          baseUrl: 'http://127.0.0.1:11434/v1',
        ),
        httpClient: recorder.client,
      );

      final result = await client.completeJson(testPrompt());

      expect(recorder.requests.length, 3);
      expect(
        (recorder.bodyOf(0)['response_format'] as Map)['type'],
        'json_schema',
      );
      expect(
        (recorder.bodyOf(1)['response_format'] as Map)['type'],
        'json_object',
      );
      expect(recorder.bodyOf(2).containsKey('response_format'), isFalse);
      // The last level also speaks the old token limit.
      expect(recorder.bodyOf(2).containsKey('max_tokens'), isTrue);
      // Without a key no Authorization header — a local server likes to
      // answer an empty Bearer with 401.
      expect(
        recorder.requests.first.headers.containsKey('authorization'),
        isFalse,
      );
      expect(result.data['name'], 'Yirga');
    });

    test('refusal comes in its own field with a strict schema', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'refusal': 'I will not do that.'},
              },
            ],
          }),
          200,
        ),
      ]);
      final client = AiClient.forConnection(
        openai(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>()
              .having((e) => e.kind, 'kind', AiFailureKind.refused)
              .having((e) => e.message, 'message', 'I will not do that.'),
        ),
      );
    });

    test('server error is retryable', () async {
      final recorder = RecordingClient([http.Response('bad gateway', 502)]);
      final client = AiClient.forConnection(
        openai(),
        httpClient: recorder.client,
      );
      await expectLater(
        client.completeJson(testPrompt()),
        throwsA(
          isA<AiFailure>()
              .having((e) => e.kind, 'kind', AiFailureKind.server)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });
  });

  group('Settings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('freshly installed, AI is off and stays off', () async {
      // A new installation should not want to send anything to an AI
      // provider on its own.
      final settings = await AiSettings.load(keyStore: InMemoryAiKeyStore());
      expect(settings.enabled, isFalse);
      for (final feature in AiFeature.values) {
        expect(settings.isEnabled(feature), isFalse);
      }
    });

    test('an update does not turn off an already set up AI', () async {
      // Whoever already entered a key obviously wanted it — they shouldn't
      // face a disabled feature after the update.
      final store = InMemoryAiKeyStore();
      await store.write(AiProvider.gemini, 'AIza');
      final settings = await AiSettings.load(keyStore: store);
      expect(settings.enabled, isTrue);

      // And the decision is written afterwards: a key deleted later doesn't
      // flip the switch back behind the user's back.
      await settings.removeKey(AiProvider.gemini);
      final again = await AiSettings.load(keyStore: InMemoryAiKeyStore());
      expect(again.enabled, isTrue);
    });

    test('without a key nothing is set up and nothing is enabled', () {
      final settings = AiSettings(
        keyStore: InMemoryAiKeyStore(),
        enabled: true,
      );
      expect(settings.provider, AiProvider.gemini);
      expect(settings.isConfigured, isFalse);
      for (final feature in AiFeature.values) {
        // The switch is on, but the feature still doesn't run.
        expect(settings.isFeatureOn(feature), isTrue);
        expect(settings.isEnabled(feature), isFalse);
      }
    });

    test('entering a key sets it up, deleting undoes it', () async {
      final settings = AiSettings(
        keyStore: InMemoryAiKeyStore(),
        enabled: true,
      );
      await settings.setKey(AiProvider.gemini, '  AIza-test  ');
      expect(settings.hasKey(AiProvider.gemini), isTrue);
      expect(settings.isConfigured, isTrue);
      expect(settings.isEnabled(AiFeature.beanForm), isTrue);
      // Surrounding whitespace from pasting doesn't belong in the key —
      // it turns every call into a 401.
      expect((await settings.connection()).apiKey, 'AIza-test');

      await settings.removeKey(AiProvider.gemini);
      expect(settings.isConfigured, isFalse);
    });

    test('each provider keeps its own key and model', () async {
      final settings = AiSettings(
        keyStore: InMemoryAiKeyStore(),
        enabled: true,
      );
      await settings.setKey(AiProvider.gemini, 'AIza');
      await settings.setProvider(AiProvider.claude);
      await settings.setKey(AiProvider.claude, 'sk-ant');
      await settings.setModel('claude-haiku-4-5');

      expect(settings.model, 'claude-haiku-4-5');
      expect((await settings.connection()).apiKey, 'sk-ant');

      await settings.setProvider(AiProvider.gemini);
      // Switched back, the Gemini model is there again, not Claude's.
      expect(settings.model, AiProvider.gemini.defaultModel);
      expect((await settings.connection()).apiKey, 'AIza');
    });

    test(
      'Custom needs an address, otherwise it counts as not set up',
      () async {
        final settings = AiSettings(keyStore: InMemoryAiKeyStore());
        await settings.setProvider(AiProvider.compatible);
        await settings.setModel('llama3');
        // No key needed — a local server doesn't want one.
        expect(settings.isConfigured, isFalse);
        await settings.setBaseUrl('  http://127.0.0.1:11434/v1  ');
        expect(settings.isConfigured, isTrue);
        expect(
          (await settings.connection()).baseUrl,
          'http://127.0.0.1:11434/v1',
        );
      },
    );

    test('a turned-off switch survives a restart', () async {
      final settings = AiSettings(keyStore: InMemoryAiKeyStore());
      await settings.setFeatureOn(AiFeature.profileDraft, false);

      final store = InMemoryAiKeyStore();
      await store.write(AiProvider.gemini, 'AIza');
      final reloaded = await AiSettings.load(keyStore: store);
      expect(reloaded.isFeatureOn(AiFeature.profileDraft), isFalse);
      expect(reloaded.isFeatureOn(AiFeature.beanForm), isTrue);
      expect(reloaded.hasKey(AiProvider.gemini), isTrue);
    });
  });

  group('AiService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AiSettings> configured() async {
      final settings = AiSettings(keyStore: InMemoryAiKeyStore());
      await settings.setProvider(AiProvider.claude);
      await settings.setKey(AiProvider.claude, 'sk-ant');
      return settings;
    }

    test(
      'without a key the service says what is missing — and makes no call',
      () async {
        final settings = AiSettings(keyStore: InMemoryAiKeyStore());
        await settings.setProvider(AiProvider.claude);
        final recorder = RecordingClient([claudeOk('{}')]);

        await expectLater(
          AiService(settings, httpClient: recorder.client).ping(),
          throwsA(
            isA<AiFailure>()
                .having((e) => e.kind, 'kind', AiFailureKind.notConfigured)
                .having((e) => e.message, 'message', contains('API key')),
          ),
        );
        expect(recorder.requests, isEmpty);
      },
    );

    test(
      'the connection test checks the whole chain up to the parsed JSON',
      () async {
        final recorder = RecordingClient([
          claudeOk('{"ready":true,"drink":"americano","missing":null}'),
        ]);
        final ping = await AiService(
          await configured(),
          httpClient: recorder.client,
        ).ping();

        expect(ping.answer, 'americano');
        expect(ping.model, 'claude-opus-5');
        expect(ping.tokenLine, '42 in / 7 out tokens');
        expect(ping.isStrict, isTrue);
        expect(ping.caveat, isNull);
        // The test also requires the enforced shape — otherwise it would
        // prove less than the features that later depend on it.
        expect(recorder.bodyOf(0).containsKey('output_config'), isTrue);
        // And it carries BOTH forms: a required field and one that may be
        // null. The second is behind every "what isn't readable stays null"
        // — a test without it would check a shape that never occurs later.
        final schema =
            ((recorder.bodyOf(0)['output_config'] as Map)['format']
                    as Map)['schema']
                as Map;
        expect((schema['properties'] as Map)['missing'], {
          'type': ['string', 'null'],
          'description': 'Always null. Nothing is asked for here.',
        });
        expect(schema['required'], contains('missing'));
      },
    );

    test('a silent fallback level is named in the result', () async {
      final recorder = RecordingClient([
        http.Response(
          jsonEncode({
            'error': {'message': 'output_config is not supported'},
          }),
          400,
        ),
        claudeOk('{"ready":true,"drink":"americano","missing":null}'),
      ]);
      final ping = await AiService(
        await configured(),
        httpClient: recorder.client,
      ).ping();

      // The connection works — but not on the footing the features assume.
      // Without this message it would look just like full success.
      expect(ping.answer, 'americano');
      expect(ping.isStrict, isFalse);
      expect(ping.caveat, contains('would not enforce the schema'));
    });

    test('an omitted nullable field is a caveat too', () async {
      final recorder = RecordingClient([
        claudeOk('{"ready":true,"drink":"americano"}'),
      ]);
      final ping = await AiService(
        await configured(),
        httpClient: recorder.client,
      ).ping();

      expect(ping.schemaEnforced, isTrue);
      expect(ping.nullableOk, isFalse);
      expect(ping.caveat, contains('instead of returning it as null'));
    });

    test(
      'fetching models works without a selected model, but not without a key',
      () async {
        final settings = AiSettings(keyStore: InMemoryAiKeyStore());
        await settings.setProvider(AiProvider.compatible);
        await settings.setBaseUrl('http://127.0.0.1:11434/v1');
        final recorder = RecordingClient([
          http.Response(
            jsonEncode({
              'data': [
                {'id': 'llama3'},
              ],
            }),
            200,
          ),
        ]);
        // No model selected — the list must still come, otherwise you'd
        // never get out of the empty selection.
        final models = await AiService(
          settings,
          httpClient: recorder.client,
        ).listModels();
        expect(models.single.id, 'llama3');

        final claude = AiSettings(keyStore: InMemoryAiKeyStore());
        await claude.setProvider(AiProvider.claude);
        await expectLater(
          AiService(claude, httpClient: recorder.client).listModels(),
          throwsA(
            isA<AiFailure>().having(
              (e) => e.kind,
              'kind',
              AiFailureKind.notConfigured,
            ),
          ),
        );
      },
    );
  });
}

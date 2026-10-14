import 'ai_client.dart';
import 'ai_prompt.dart';
import 'ai_provider.dart';

// Gemini via the Generative Language API
// (`POST /models/{model}:generateContent`).
//
// The provider for everyone who has no account with any AI service yet:
// Google AI Studio gives away a free tier that is enough for a few bean
// labels a day. That Google may use free-tier inputs is stated in a
// sentence in the settings — everyone should have read it before the first
// photo.
class GeminiClient extends HttpAiClient {
  GeminiClient(super.connection, {super.httpClient});

  // In the header, not as `?key=` in the URL: a key in the URL ends up in
  // every log the request passes through.
  Map<String, String> get _headers => {'x-goog-api-key': connection.apiKey};

  @override
  Future<AiJsonResult> completeJson(AiPrompt prompt) {
    // Gemini's schema dialect is only a subset of JSON Schema (see
    // [geminiSchema]). If a conversion is still rejected, level two remains:
    // request JSON, but enforce the shape only via the instructions.
    return attemptInOrder([
      () => _request(prompt, enforceSchema: true),
      () => _request(prompt, enforceSchema: false),
    ]);
  }

  Future<AiJsonResult> _request(
    AiPrompt prompt, {
    required bool enforceSchema,
  }) async {
    final body = <String, Object?>{
      'systemInstruction': {
        'parts': [
          {'text': prompt.system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            for (final image in prompt.images)
              {
                'inlineData': {
                  'mimeType': image.mediaType,
                  'data': image.base64Data,
                },
              },
            {'text': '${prompt.task}\n\n${prompt.schemaInstruction}'},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        if (enforceSchema) 'responseSchema': geminiSchema(prompt.schema),
        'maxOutputTokens': prompt.maxOutputTokens,
      },
    };

    final json = await postJson(
      '/models/${connection.model}:generateContent',
      _headers,
      body,
    );

    // A provider filter holds back the answer: HTTP 200, but no candidates
    // at all.
    final blocked = (json['promptFeedback'] as Map?)?['blockReason'];
    if (blocked != null) {
      throw AiFailure(
        AiFailureKind.refused,
        'Gemini blocked the request ($blocked).',
      );
    }

    final candidates = json['candidates'];
    final candidate = candidates is List && candidates.isNotEmpty
        ? candidates.first as Map
        : null;
    if (candidate == null) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'Gemini answered with no candidate.',
      );
    }

    final finish = candidate['finishReason'];
    if (finish == 'MAX_TOKENS') {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The answer hit the length limit and is incomplete.',
      );
    }
    if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') {
      throw AiFailure(AiFailureKind.refused, 'Gemini declined to answer this.');
    }

    final parts = (candidate['content'] as Map?)?['parts'];
    final text = parts is List
        ? parts
              .whereType<Map>()
              .map((part) => part['text'] as String? ?? '')
              .join()
        : '';
    if (text.trim().isEmpty) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'Gemini answered with no text.',
      );
    }

    final usage = json['usageMetadata'];
    return AiJsonResult(
      data: HttpAiClient.extractJson(text),
      model: json['modelVersion'] as String? ?? connection.model,
      schemaEnforced: enforceSchema,
      inputTokens: usage is Map ? usage['promptTokenCount'] as int? : null,
      outputTokens: usage is Map ? usage['candidatesTokenCount'] as int? : null,
    );
  }

  @override
  Future<List<AiModel>> listModels() async {
    final json = await getJson('/models?pageSize=200', _headers);
    final models = json['models'];
    if (models is! List) return const [];
    return [
      for (final entry in models.whereType<Map>())
        if (entry['name'] is String &&
            // Embedding and image models cannot answer anything; they do
            // not belong in a list that is picked from blindly.
            (entry['supportedGenerationMethods'] as List?)?.contains(
                  'generateContent',
                ) !=
                false)
          AiModel(
            _stripPrefix(entry['name'] as String),
            entry['displayName'] as String? ??
                _stripPrefix(entry['name'] as String),
            null,
          ),
    ];
  }

  // The list names models "models/gemini-2.5-flash", the call only wants
  // the part after that.
  static String _stripPrefix(String name) =>
      name.startsWith('models/') ? name.substring('models/'.length) : name;
}

/// Converts our JSON Schema into Gemini's dialect.
///
/// Gemini takes no JSON Schema but a subset of OpenAPI 3.0. Three
/// differences, each taking three lines of work:
///
///  * It does not know `additionalProperties` — dropped (Gemini closes
///    objects anyway).
///  * Types are uppercase: `STRING`, not `string`.
///  * A field that may also be `null` is written in JSON Schema as a type
///    list `["string","null"]`; Gemini writes it as `nullable: true` next to
///    the single type.
///
/// Plus `propertyOrdering`: the order in which Gemini should output the
/// fields. Without it the order is arbitrary, and on a package where roast
/// date and best-before date sit side by side, every decision the model
/// does not have to make itself helps.
Map<String, Object?> geminiSchema(Map<String, Object?> schema) {
  final result = <String, Object?>{};

  // Type and nullability.
  final type = schema['type'];
  if (type is List) {
    final concrete = type.whereType<String>().where((t) => t != 'null');
    if (concrete.isNotEmpty) result['type'] = concrete.first.toUpperCase();
    if (type.contains('null')) result['nullable'] = true;
  } else if (type is String) {
    result['type'] = type.toUpperCase();
  }

  // `anyOf: [{type: string}, {type: null}]` says the same as the type list
  // above, just written differently — so treat it the same way.
  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    final branches = anyOf.whereType<Map<String, Object?>>().toList();
    final concrete = branches.where((b) => b['type'] != 'null').toList();
    if (branches.any((b) => b['type'] == 'null')) result['nullable'] = true;
    if (concrete.length == 1) {
      result.addAll(geminiSchema(concrete.first));
    } else if (concrete.length > 1) {
      result['anyOf'] = [for (final branch in concrete) geminiSchema(branch)];
    }
  }

  for (final key in ['description', 'format', 'enum', 'required']) {
    if (schema.containsKey(key)) result[key] = schema[key];
  }

  final properties = schema['properties'];
  if (properties is Map) {
    result['properties'] = {
      for (final entry in properties.entries)
        entry.key: geminiSchema(entry.value as Map<String, Object?>),
    };
    result['propertyOrdering'] = properties.keys.toList();
  }

  final items = schema['items'];
  if (items is Map<String, Object?>) result['items'] = geminiSchema(items);

  return result;
}

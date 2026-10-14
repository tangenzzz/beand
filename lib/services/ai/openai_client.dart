import 'ai_client.dart';
import 'ai_prompt.dart';
import 'ai_provider.dart';

// OpenAI via `POST /chat/completions` — and with it everything that
// replicates this interface.
//
// That is why the settings list four providers instead of three:
// OpenRouter, Groq, Mistral, DeepSeek, Together, Ollama and LM Studio all
// speak exactly this language. Under "Custom" the user enters a base URL and
// uses the same code here — including a locally running model, where no
// data leaves the house at all.
class OpenAiClient extends HttpAiClient {
  OpenAiClient(super.connection, {super.httpClient});

  Map<String, String> get _headers => {
    // A local server does not want a key — then send no header either; some
    // answer an empty Bearer with 401.
    if (connection.apiKey.isNotEmpty)
      'authorization': 'Bearer ${connection.apiKey}',
  };

  @override
  Future<AiJsonResult> completeJson(AiPrompt prompt) {
    // Three levels, because anything can be behind "Custom":
    //   1. Enforced schema — OpenAI and those who replicate it support it.
    //   2. Only "answer in JSON" (`json_object`) — the old, widely
    //      supported mechanism.
    //   3. Enforce nothing and additionally use `max_tokens` instead of
    //      `max_completion_tokens` — the variant that older or home-built
    //      servers understand too.
    return attemptInOrder([
      () => _request(prompt, format: _Format.schema),
      () => _request(prompt, format: _Format.jsonObject),
      () => _request(prompt, format: _Format.none),
    ]);
  }

  Future<AiJsonResult> _request(
    AiPrompt prompt, {
    required _Format format,
  }) async {
    final body = <String, Object?>{
      'model': connection.model,
      if (format == _Format.none)
        'max_tokens': prompt.maxOutputTokens
      else
        'max_completion_tokens': prompt.maxOutputTokens,
      'messages': [
        {'role': 'system', 'content': prompt.system},
        {
          'role': 'user',
          'content': [
            for (final image in prompt.images)
              {
                'type': 'image_url',
                // As a data URL here, not as a link: the packaging photo is
                // on the phone and should not be uploaded anywhere, only into
                // this one request.
                'image_url': {
                  'url': 'data:${image.mediaType};base64,${image.base64Data}',
                },
              },
            {
              'type': 'text',
              'text': '${prompt.task}\n\n${prompt.schemaInstruction}',
            },
          ],
        },
      ],
      if (format == _Format.schema)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'beand_result',
            'strict': true,
            'schema': prompt.schema,
          },
        },
      if (format == _Format.jsonObject)
        'response_format': {'type': 'json_object'},
    };

    final json = await postJson('/chat/completions', _headers, body);

    final choices = json['choices'];
    final choice = choices is List && choices.isNotEmpty
        ? choices.first as Map
        : null;
    if (choice == null) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The provider answered with no choice.',
      );
    }

    final message = choice['message'] as Map? ?? const {};
    // With an enforced schema a refusal is in its own field, not in the
    // text.
    if (message['refusal'] is String) {
      throw AiFailure(AiFailureKind.refused, message['refusal'] as String);
    }
    if (choice['finish_reason'] == 'length') {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The answer hit the length limit and is incomplete.',
      );
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw AiFailure(
        AiFailureKind.refused,
        'A content filter stopped the answer.',
      );
    }

    final text = message['content'] as String? ?? '';
    if (text.trim().isEmpty) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The provider answered with no text.',
      );
    }

    final usage = json['usage'];
    return AiJsonResult(
      data: HttpAiClient.extractJson(text),
      model: json['model'] as String? ?? connection.model,
      schemaEnforced: format == _Format.schema,
      inputTokens: usage is Map ? usage['prompt_tokens'] as int? : null,
      outputTokens: usage is Map ? usage['completion_tokens'] as int? : null,
    );
  }

  @override
  Future<List<AiModel>> listModels() async {
    final json = await getJson('/models', _headers);
    final data = json['data'];
    if (data is! List) return const [];
    final ids = [
      for (final entry in data.whereType<Map>())
        if (entry['id'] is String) entry['id'] as String,
    ]..sort();
    // This interface provides no display names — the ID IS the name, and on
    // OpenRouter it is prefixed with the provider anyway
    // ("anthropic/claude-opus-5").
    return [for (final id in ids) AiModel(id, id, null)];
  }
}

enum _Format { schema, jsonObject, none }

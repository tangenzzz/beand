import 'ai_client.dart';
import 'ai_prompt.dart';
import 'ai_provider.dart';

// Claude via the Messages API (`POST /v1/messages`).
//
// There is no official Anthropic SDK for Dart, so plain HTTPS calls. The
// request shape follows the official reference: key in the `x-api-key`
// header, plus the mandatory `anthropic-version`.
//
// (If bean'd were ever built as a web app, it would also need the
// `anthropic-dangerous-direct-browser-access` header — not on Android/iOS.)
class ClaudeClient extends HttpAiClient {
  ClaudeClient(super.connection, {super.httpClient});

  static const apiVersion = '2023-06-01';

  // If a newer model's safety filter rejects a request (which sometimes
  // happens wrongly), Anthropic can answer it right away with a suitable
  // other model on request. Older models do not support this, so only for
  // these.
  static const fallbackBeta = 'server-side-fallback-2026-07-01';
  static const _fallbackModels = {
    'claude-sonnet-5-5',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-fable-5-1',
  };

  bool get _withFallback => _fallbackModels.contains(connection.model);

  Map<String, String> get _headers => {
    'x-api-key': connection.apiKey,
    'anthropic-version': apiVersion,
    if (_withFallback) 'anthropic-beta': fallbackBeta,
  };

  @override
  Future<AiJsonResult> completeJson(AiPrompt prompt) {
    // First the enforced shape, then without. Structured output exists on
    // Opus 5, Sonnet 5, Sonnet 5.5 and Haiku 4.5; if the user picks an older
    // model, the provider rejects `output_config` with 400 — then the
    // instruction in the prompt alone carries the shape.
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
      'model': connection.model,
      'max_tokens': prompt.maxOutputTokens,
      'system': prompt.system,
      'messages': [
        {
          'role': 'user',
          'content': [
            // Images before text: that is how the reference has it, and the
            // model then reads the task with the image already in view.
            for (final image in prompt.images)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': image.mediaType,
                  'data': image.base64Data,
                },
              },
            {
              'type': 'text',
              'text': '${prompt.task}\n\n${prompt.schemaInstruction}',
            },
          ],
        },
      ],
      if (_withFallback) 'fallbacks': 'default',
      if (enforceSchema)
        'output_config': {
          'format': {'type': 'json_schema', 'schema': prompt.schema},
        },
    };

    final json = await postJson('/messages', _headers, body);

    // Refusal and truncated response are both HTTP 200 — without this check
    // half a JSON would be reported as "no JSON" and the real reason hidden.
    final stop = json['stop_reason'];
    if (stop == 'refusal') {
      throw AiFailure(AiFailureKind.refused, 'Claude declined to answer this.');
    }
    if (stop == 'max_tokens') {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The answer hit the length limit and is incomplete.',
      );
    }

    final content = json['content'];
    final text = content is List
        ? content
              .whereType<Map>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'] as String? ?? '')
              .join()
        : '';
    if (text.trim().isEmpty) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'Claude answered with no text.',
      );
    }

    final usage = json['usage'];
    return AiJsonResult(
      data: HttpAiClient.extractJson(text),
      model: json['model'] as String? ?? connection.model,
      schemaEnforced: enforceSchema,
      inputTokens: usage is Map ? usage['input_tokens'] as int? : null,
      outputTokens: usage is Map ? usage['output_tokens'] as int? : null,
    );
  }

  @override
  Future<List<AiModel>> listModels() async {
    final json = await getJson('/models?limit=100', _headers);
    final data = json['data'];
    if (data is! List) return const [];
    return [
      for (final entry in data.whereType<Map>())
        if (entry['id'] is String)
          AiModel(
            entry['id'] as String,
            entry['display_name'] as String? ?? entry['id'] as String,
            null,
          ),
    ];
  }
}

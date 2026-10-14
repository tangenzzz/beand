// ignore_for_file: prefer_initializing_formals
// (The fields are private, and named parameters in Dart must not start with
// an underscore — so `{required this._feld}` does not exist.)
import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'bean_extraction.dart';
import 'ai_prompt.dart';
import 'ai_provider.dart';
import 'ai_settings.dart';
import 'shot_analysis.dart';

// The one place where the rest of the app talks to the AI.
//
// The three features go in here, in this order, because the risk grows that
// way:
//
//   1. extractBean   — fill the bean form from a photo/link
//   2. analyseShot   — shot analysis, result is stored with the shot
//   3. draftProfile  — profile draft; ALWAYS via ProfileDraft.fromJson,
//                      checkProfile() and the profile editor, never directly
//                      onto the machine
//
// Built: the foundation (providers, keys, models, [ping]), item 1
// ([extractBean]) and item 2 ([analyseShot]). The last one comes with its
// feature, together with the schema it requires — no empty shells here.
class AiService {
  AiService(this.settings, {http.Client? httpClient})
    : _httpClient = httpClient;

  final AiSettings settings;

  /// Tests only. In production every call builds its own HTTP client, so
  /// nothing stays open beyond the lifetime of a request.
  final http.Client? _httpClient;

  bool isEnabled(AiFeature feature) => settings.isEnabled(feature);

  /// Builds the client for the current settings. Throws [AiFailure] if
  /// something is still missing — instead of being sent with partial data
  /// and ending in a meaningless 400 at the provider.
  Future<AiClient> client() async {
    final connection = await settings.connection();
    if (!connection.isComplete) {
      throw AiFailure(
        AiFailureKind.notConfigured,
        connection.model.isEmpty
            ? 'No model selected.'
            : connection.baseUrl.isEmpty
            ? 'No base URL entered.'
            : 'No API key stored for ${connection.provider.label}.',
      );
    }
    return AiClient.forConnection(connection, httpClient: _httpClient);
  }

  /// Ask the provider for its models. The key is enough, a model does not
  /// need to be chosen yet — otherwise one could never get out of an empty
  /// picker.
  Future<List<AiModel>> listModels() async {
    final connection = await settings.connection();
    if (connection.provider.requiresKey && connection.apiKey.isEmpty) {
      throw AiFailure(
        AiFailureKind.notConfigured,
        'Enter the API key first, then the models can be fetched.',
      );
    }
    if (connection.baseUrl.isEmpty) {
      throw AiFailure(AiFailureKind.notConfigured, 'No base URL entered.');
    }
    final client = AiClient.forConnection(connection, httpClient: _httpClient);
    try {
      return await client.listModels();
    } finally {
      client.close();
    }
  }

  /// Item 1: read a bean from a packaging photo or a shop page. Exactly one
  /// input is set — an image OR a URL.
  ///
  /// The app fetches the URL itself and passes the text on: a model cannot
  /// open a page, and a link without content would be an invitation to make
  /// things up.
  ///
  /// Also returns whether the shape was enforced — whoever relies on the
  /// schema should know whether it really applied.
  Future<BeanExtraction> extractBean({AiImage? image, Uri? url}) async {
    assert((image == null) != (url == null), 'exactly one input: image or URL');

    final AiPrompt prompt;
    if (image != null) {
      prompt = AiPrompt(
        system: beanSystemPrompt,
        task: beanImageTask,
        images: [image],
        schema: beanDraftSchema(),
      );
    } else {
      final fetcher = _httpClient ?? http.Client();
      final String page;
      try {
        page = await fetchReadableText(url!, client: fetcher);
      } on AiFailure {
        rethrow;
      } catch (e) {
        throw AiFailure(
          AiFailureKind.network,
          'Could not load that page: $e',
          retryable: true,
        );
      } finally {
        if (_httpClient == null) fetcher.close();
      }
      prompt = AiPrompt(
        system: beanSystemPrompt,
        task: beanTextTask(url.host, page),
        schema: beanDraftSchema(),
      );
    }

    final client = await this.client();
    try {
      final result = await client.completeJson(prompt);
      return BeanExtraction(
        draft: BeanDraft.fromJson(result.data),
        model: result.model,
        schemaEnforced: result.schemaEnforced,
      );
    } finally {
      client.close();
    }
  }

  /// Item 2: assess a shot. Stores nothing — the caller does that with
  /// [AppDatabase.setShotAnalysis], so this service does not need to know
  /// about the DB.
  Future<ShotAnalysisResult> analyseShot(ShotAnalysisInput input) async {
    final client = await this.client();
    try {
      final result = await client.completeJson(
        AiPrompt(
          system: shotAnalysisSystemPrompt,
          task: shotAnalysisTask(input),
          schema: shotAnalysisSchema(),
        ),
      );
      final analysis = ShotAnalysis.fromJson(result.data);
      if (analysis.isEmpty) {
        throw AiFailure(
          AiFailureKind.badResponse,
          'The model answered, but without an analysis. Try again.',
          retryable: true,
        );
      }
      return ShotAnalysisResult(
        analysis: analysis,
        model: result.model,
        schemaEnforced: result.schemaEnforced,
      );
    } finally {
      client.close();
    }
  }

  /// The connection test behind "Test connection".
  ///
  /// Deliberately a real, tiny task and not just fetching the model list: it
  /// proves the whole chain at once — key, URL, model name, structured output
  /// and that the response can be parsed. All three features later depend on
  /// exactly this chain.
  ///
  /// The schema is therefore not a toy, but carries **both shapes** the real
  /// features rely on: a required field and a field that may be `null`
  /// (`["string","null"]`). The second is the trickier one — it is behind
  /// every "whatever is unreadable stays null", and providers write it
  /// differently. A test without it would check a shape that never occurs
  /// later. Cost: a few tokens.
  Future<AiPing> ping() async {
    final client = await this.client();
    try {
      final result = await client.completeJson(
        AiPrompt(
          system:
              'You are a connection check. Answer only in the required JSON.',
          task:
              'Reply with ready = true and name the coffee drink that is '
              'espresso with hot water, in one word. Leave "missing" null — '
              'nothing is being asked for there.',
          schema: aiObjectSchema({
            'ready': aiField('boolean'),
            'drink': aiField('string'),
            'missing': aiNullable(
              'string',
              description: 'Always null. Nothing is asked for here.',
            ),
          }),
          maxOutputTokens: 1000,
        ),
      );
      return AiPing(
        model: result.model,
        answer: result.data['drink'] as String? ?? '',
        schemaEnforced: result.schemaEnforced,
        // Did the nullable field really come back as null — and was it there
        // at all? A provider that omits it did not really enforce the
        // schema, whatever else it claims.
        nullableOk:
            result.data.containsKey('missing') &&
            result.data['missing'] == null,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
      );
    } finally {
      client.close();
    }
  }
}

/// What came out of reading a bean.
class BeanExtraction {
  const BeanExtraction({
    required this.draft,
    required this.model,
    required this.schemaEnforced,
  });

  final BeanDraft draft;
  final String model;
  final bool schemaEnforced;
}

/// What came out of a shot analysis.
class ShotAnalysisResult {
  const ShotAnalysisResult({
    required this.analysis,
    required this.model,
    required this.schemaEnforced,
  });

  final ShotAnalysis analysis;
  final String model;
  final bool schemaEnforced;
}

/// What the connection test reports. [model] is the name the provider itself
/// reported — it often differs from what was sent, and that is exactly what
/// you want to see.
class AiPing {
  const AiPing({
    required this.model,
    required this.answer,
    required this.schemaEnforced,
    required this.nullableOk,
    this.inputTokens,
    this.outputTokens,
  });

  final String model;
  final String answer;

  /// Did it run with an enforced shape — or did a fallback level kick in?
  final bool schemaEnforced;

  /// Did the field that may be `null` really come back as `null`?
  final bool nullableOk;

  final int? inputTokens;
  final int? outputTokens;

  /// The test is fully green only if both hold. Otherwise the connection
  /// works, but on weaker ground than the features assume.
  bool get isStrict => schemaEnforced && nullableOk;

  /// One sentence on what exactly is weaker — not just "Warning".
  String? get caveat {
    if (isStrict) return null;
    if (!schemaEnforced) {
      return 'This provider would not enforce the schema — the app asked for '
          'the form in the prompt instead. That usually works, but nothing '
          'guarantees it.';
    }
    return 'The answer left out the optional field instead of returning it as '
        'null. Fields that stay empty may come back missing.';
  }

  String get tokenLine {
    if (inputTokens == null && outputTokens == null) return '';
    return '${inputTokens ?? '?'} in / ${outputTokens ?? '?'} out tokens';
  }
}

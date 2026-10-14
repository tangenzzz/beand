import 'dart:convert';
import 'dart:typed_data';

// A request to a model in the form all providers understand. The
// provider-neutral middle of the AI layer: above, the features (beans, shot
// analysis, profile) build their request; below, one client per provider
// translates it into that provider's language.
//
// The consistent means is structured output: the model never answers in
// prose that we parse, but in JSON per [schema]. Parsing prose means
// guessing, and here guesses end up on an espresso machine.
class AiPrompt {
  const AiPrompt({
    required this.system,
    required this.task,
    required this.schema,
    this.images = const [],
    this.maxOutputTokens = 16000,
  });

  /// The role: what the model is and which rules apply. Goes into its own
  /// field at the provider (`system` / `system_instruction`), not into the
  /// user message.
  final String system;

  /// The actual request including data.
  final String task;

  /// JSON schema of the answer, built with [aiObjectSchema].
  final Map<String, Object?> schema;

  /// Images for the request — the bean's packaging, a shot's curve.
  final List<AiImage> images;

  /// Not too tight: if the limit is reached, the answer breaks off in the
  /// middle of the JSON and the whole call was paid for nothing.
  final int maxOutputTokens;

  /// Also include the schema as plain text. Two reasons: providers that
  /// don't support enforced shape (local models behind `compatible`) need it
  /// as an instruction; and for those that do, it doesn't hurt if the model
  /// has read the field names too.
  String get schemaInstruction =>
      'Answer with JSON only — no prose, no code fences — matching this '
      'JSON Schema exactly:\n${const JsonEncoder.withIndent('  ').convert(schema)}';
}

/// An image in the request. [mediaType] is the MIME type the provider
/// expects (`image/jpeg`, `image/png`).
class AiImage {
  const AiImage({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String mediaType;

  String get base64Data => base64Encode(bytes);
}

/// What comes back: the parsed answer and what it cost.
class AiJsonResult {
  const AiJsonResult({
    required this.data,
    required this.model,
    required this.schemaEnforced,
    this.inputTokens,
    this.outputTokens,
  });

  final Map<String, Object?> data;

  /// Which model actually answered — stored with shot analyses so it's
  /// traceable later who said that.
  final String model;

  /// Did the provider really enforce the shape, or did it go through a
  /// fallback level?
  ///
  /// This is passed up because the levels otherwise degrade SILENTLY: a
  /// provider that rejects the schema only gets the shape as a request in
  /// the prompt — that usually works and sometimes doesn't, and nobody
  /// notices the difference. So the connection test shows it.
  final bool schemaEnforced;

  final int? inputTokens;
  final int? outputTokens;
}

/// Why a call failed. Coarse enough for the UI to make a useful sentence out
/// of it, and fine enough for it to know whether a retry makes sense.
enum AiFailureKind {
  /// No key, no model, no address — not sent at all.
  notConfigured,

  /// Key wrong, expired or without permissions (401/403).
  auth,

  /// Too many requests or credit/free tier exhausted (429).
  rateLimit,

  /// The provider didn't like the request (400) — usually a model that
  /// doesn't exist under that name, or a schema it can't enforce.
  request,

  /// Something is broken at the provider (5xx) — try again later.
  server,

  /// No network, timeout, name not resolvable.
  network,

  /// An answer arrived but was not JSON in the requested shape.
  badResponse,

  /// The model refused to answer.
  refused,
}

class AiFailure implements Exception {
  AiFailure(this.kind, this.message, {this.retryable = false});

  final AiFailureKind kind;

  /// A sentence for the user, ideally with what the provider itself said —
  /// "Error" alone has never helped anyone.
  final String message;

  final bool retryable;

  @override
  String toString() => message;
}

/// Builds a JSON schema in the one variant all three providers accept:
///
///  * EVERY field is in `required`,
///  * `additionalProperties` is closed,
///  * and what may be missing is expressed via the type `null` — not by
///    omission.
///
/// This is not taste but the intersection: OpenAI's `strict` insists on a
/// complete `required` and closed objects, Claude's structured output
/// requires `additionalProperties: false`, and Gemini's schema dialect
/// doesn't know `additionalProperties` at all (the Gemini client strips it,
/// see gemini_client.dart).
///
/// And it fits the rule: what isn't readable stays `null` and is never
/// guessed. A field that doesn't exist can't be made up by the model — a
/// field that MAY be `null` doesn't have to be filled.
Map<String, Object?> aiObjectSchema(Map<String, Object?> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};

/// A field that may also be `null`. [type] is a basic JSON schema type
/// (`string`, `number`, `integer`, `boolean`).
Map<String, Object?> aiNullable(String type, {String? description}) => {
  'type': [type, 'null'],
  'description': ?description,
};

Map<String, Object?> aiField(String type, {String? description}) => {
  'type': type,
  'description': ?description,
};

Map<String, Object?> aiArray(
  Map<String, Object?> items, {
  String? description,
}) => {'type': 'array', 'items': items, 'description': ?description};

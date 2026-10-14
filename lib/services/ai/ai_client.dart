import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_prompt.dart';
import 'ai_provider.dart';
import 'claude_client.dart';
import 'gemini_client.dart';
import 'openai_client.dart';

// The interface behind which the providers disappear. Everything above it
// (bean form, shot analysis, profile draft) only knows these two methods and
// never learns who answered.
abstract class AiClient {
  /// Send off a request and get the JSON back.
  Future<AiJsonResult> completeJson(AiPrompt prompt);

  /// The models this key may use — asked from the provider itself. Each of
  /// the three has an endpoint for it; a built-in list would be wrong by the
  /// next model at the latest.
  Future<List<AiModel>> listModels();

  void close();

  /// The matching client for the connection. [httpClient] for tests only.
  factory AiClient.forConnection(
    AiConnection connection, {
    http.Client? httpClient,
  }) {
    return switch (connection.provider) {
      AiProvider.claude => ClaudeClient(connection, httpClient: httpClient),
      AiProvider.gemini => GeminiClient(connection, httpClient: httpClient),
      // OpenAI and "Custom" are the same client: anyone entering their own
      // address almost always speaks exactly this interface.
      AiProvider.openai ||
      AiProvider.compatible => OpenAiClient(connection, httpClient: httpClient),
    };
  }
}

/// Shared base: one HTTP call, error mapping, extracting the JSON.
/// Dart has no official SDK for any of the three providers, so these are
/// plain HTTPS calls — but the tedium of that lives exactly once, here.
abstract class HttpAiClient implements AiClient {
  HttpAiClient(this.connection, {http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  final AiConnection connection;
  final http.Client _http;
  final bool _ownsHttp;

  /// Generous: a model that thinks before answering needs a good minute for
  /// a profile draft.
  static const timeout = Duration(seconds: 120);

  @override
  void close() {
    if (_ownsHttp) _http.close();
  }

  /// The base address without a trailing slash so paths append cleanly.
  String get baseUrl {
    final raw = connection.baseUrl.isEmpty
        ? connection.provider.defaultBaseUrl
        : connection.baseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  Future<Map<String, Object?>> postJson(
    String path,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) async {
    return _send(
      () => _http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'content-type': 'application/json', ...headers},
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, Object?>> getJson(
    String path,
    Map<String, String> headers,
  ) async {
    return _send(() => _http.get(Uri.parse('$baseUrl$path'), headers: headers));
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request,
  ) async {
    http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw AiFailure(
        AiFailureKind.network,
        'The provider did not answer within ${timeout.inSeconds} s.',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw AiFailure(
        AiFailureKind.network,
        'Cannot reach the provider: ${e.message}',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw AiFailure(
        AiFailureKind.network,
        'Cannot reach the provider: ${e.message}',
        retryable: true,
      );
    }

    if (response.statusCode >= 400) throw _failureFor(response);

    // `allowMalformed`: a single broken byte must not end the whole call
    // with a bare FormatException. The providers send UTF-8; if something
    // slips anyway, a replacement character in the middle of a tasting note
    // is still better than no answer at all.
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, Object?>) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The provider answered with something other than a JSON object.',
      );
    }
    return decoded;
  }

  /// Translate the status into a reason — and keep the provider's message.
  /// "model not found" and "quota exceeded" in particular only appear there
  /// and are the only thing that really helps the user.
  AiFailure _failureFor(http.Response response) {
    final detail = _errorMessage(response.body);
    final suffix = detail == null ? '' : ' — $detail';
    return switch (response.statusCode) {
      401 || 403 => AiFailure(
        AiFailureKind.auth,
        'The provider rejected the key$suffix',
      ),
      404 => AiFailure(
        AiFailureKind.request,
        'Not found — check the model name and the base URL$suffix',
      ),
      429 => AiFailure(
        AiFailureKind.rateLimit,
        'Rate limit or quota reached$suffix',
        retryable: true,
      ),
      >= 500 => AiFailure(
        AiFailureKind.server,
        'The provider has a problem (${response.statusCode})$suffix',
        retryable: true,
      ),
      _ => AiFailure(
        AiFailureKind.request,
        'The provider rejected the request (${response.statusCode})$suffix',
      ),
    };
  }

  /// All three wrap their error message differently, but always in a field
  /// called `message` somewhere under `error`.
  String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {
      // Not JSON — then the raw body is still better than nothing.
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }

  /// Extract the JSON from the response text.
  ///
  /// Where the shape was enforced, the text is already pure JSON. Where not
  /// (local models, fallback levels), it often comes in ```json fences or
  /// with a leading sentence — so it is read from the first `{` to the last
  /// `}` instead of treating the case as an error.
  static Map<String, Object?> extractJson(String text) {
    var candidate = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(candidate);
    if (fence != null) candidate = fence.group(1)!.trim();

    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start >= 0 && end > start) {
      candidate = candidate.substring(start, end + 1);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } catch (_) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'The answer was not JSON: ${_preview(text)}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw AiFailure(
        AiFailureKind.badResponse,
        'Expected a JSON object, got ${decoded.runtimeType}.',
      );
    }
    return decoded;
  }

  static String _preview(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
  }

  /// Try the same request with decreasing demands.
  ///
  /// The providers don't agree on what enforced output shape they support,
  /// and an address behind "Custom" can be anything — from OpenRouter to an
  /// Ollama on your own computer. Instead of betting, each client goes from
  /// strict to loose: if a level is rejected as a BAD REQUEST (400/404), the
  /// next one is tried. Key and network errors abort immediately — they
  /// don't get better by relaxing.
  Future<AiJsonResult> attemptInOrder(
    List<Future<AiJsonResult> Function()> attempts,
  ) async {
    AiFailure? last;
    for (final attempt in attempts) {
      try {
        return await attempt();
      } on AiFailure catch (e) {
        if (e.kind != AiFailureKind.request) rethrow;
        last = e;
      }
    }
    throw last!;
  }
}

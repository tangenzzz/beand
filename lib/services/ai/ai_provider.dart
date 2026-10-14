// The providers bean'd can query.
//
// Principle: the user brings their OWN key, the app calls the provider
// directly, there is no server of ours. Without a key the AI stays invisible
// and the app behaves as before.
//
// Why several providers and not one: bean'd is meant for the app stores, and
// most users there have no AI account at all. Gemini offers a free tier to
// get started right away; whoever already pays for Claude or OpenAI uses
// that. And `compatible` is the master key — OpenRouter, Groq, Mistral,
// DeepSeek, Ollama and LM Studio all speak the same interface as OpenAI,
// they just need a different base URL.
enum AiProvider {
  claude(
    label: 'Claude',
    vendor: 'Anthropic',
    defaultBaseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    keyHint: 'sk-ant-…',
    note: 'Pay per use. An analysis costs cents.',
    // Sonnet 5.5 instead of Opus: for shot analysis it reads intent and
    // readings reliably enough, but costs less than half.
    defaultModel: 'claude-sonnet-5-5',
    fallbackModels: [
      AiModel(
        'claude-opus-5',
        'Claude Opus 5',
        'Strongest, \$5/\$25 per M tokens',
      ),
      AiModel(
        'claude-sonnet-5-5',
        'Claude Sonnet 5.5',
        'Recommended, \$2/\$10 per M tokens',
      ),
      AiModel('claude-sonnet-5', 'Claude Sonnet 5', '\$2/\$10 per M tokens'),
      AiModel(
        'claude-haiku-4-5',
        'Claude Haiku 4.5',
        'Cheapest, \$1/\$5 per M tokens',
      ),
    ],
  ),
  gemini(
    label: 'Gemini',
    vendor: 'Google AI Studio',
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHint: 'AIza…',
    note:
        // Gemini API terms as of 2026-03-23: Google may use the free tier to
        // improve its products, humans may read along — EXCEPT in the EEA,
        // Switzerland and the UK, where the paid-tier rules apply even for
        // free (no use for improvement, logs kept only briefly against
        // abuse).
        'Has a free tier. Outside the EU/EEA, Switzerland and the UK, Google '
        'may use free-tier input to improve its products and people may '
        'read it. In those regions, and on paid plans, it does not.',
    defaultModel: 'gemini-2.5-flash',
    fallbackModels: [
      AiModel('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Fast, free tier'),
      AiModel(
        'gemini-2.5-pro',
        'Gemini 2.5 Pro',
        'Stronger, tighter free limits',
      ),
    ],
  ),
  openai(
    label: 'OpenAI',
    vendor: 'OpenAI',
    defaultBaseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-…',
    note: 'Pay per use.',
    defaultModel: 'gpt-5',
    fallbackModels: [AiModel('gpt-5', 'GPT-5', null)],
  ),
  compatible(
    label: 'Custom',
    vendor: 'Any OpenAI-compatible endpoint',
    defaultBaseUrl: '',
    keyUrl: 'https://openrouter.ai/keys',
    keyHint: 'optional for local servers',
    note:
        'For OpenRouter, Groq, Mistral, DeepSeek, Ollama, LM Studio and '
        'anything else that speaks the OpenAI API. Enter the base URL '
        'including the version, e.g. https://openrouter.ai/api/v1.',
    defaultModel: '',
    fallbackModels: [],
  );

  const AiProvider({
    required this.label,
    required this.vendor,
    required this.defaultBaseUrl,
    required this.keyUrl,
    required this.keyHint,
    required this.note,
    required this.defaultModel,
    required this.fallbackModels,
  });

  /// What is shown in the picker.
  final String label;

  /// Who is behind it — the second line, so "Custom" is explained.
  final String vendor;

  /// Base URL including the version path. Empty for [compatible]: the user
  /// enters it.
  final String defaultBaseUrl;

  /// Where the user gets a key.
  final String keyUrl;

  /// What a key of this provider looks like (placeholder in the field).
  final String keyHint;

  /// One sentence on cost and data handling, right below the picker.
  final String note;

  /// Default as long as the user has not chosen a model.
  final String defaultModel;

  /// Only the fallback when the model list cannot be loaded (no network, no
  /// key). The normal path is [AiClient.listModels] — nobody knows in
  /// advance which names a provider will offer next year, and a hard-coded
  /// list would be exactly the kind of copy that lags behind reality.
  final List<AiModel> fallbackModels;

  /// A custom base URL is required and is not guessed.
  bool get requiresBaseUrl => this == AiProvider.compatible;

  /// Local servers (Ollama, LM Studio) do not want a key.
  bool get requiresKey => this != AiProvider.compatible;
}

/// A model as shown in the picker. [note] is free-form: for the fallback it
/// holds the price, for a loaded list usually nothing.
class AiModel {
  const AiModel(this.id, this.label, this.note);

  final String id;
  final String label;
  final String? note;

  @override
  bool operator ==(Object other) => other is AiModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Everything a call needs: provider, key, model, URL. Together instead of
/// separately, because a half-set state (key from Claude, URL from OpenAI)
/// must never arise.
class AiConnection {
  const AiConnection({
    required this.provider,
    required this.apiKey,
    required this.model,
    required this.baseUrl,
  });

  final AiProvider provider;
  final String apiKey;
  final String model;
  final String baseUrl;

  /// Is this enough to send?
  bool get isComplete =>
      model.isNotEmpty &&
      baseUrl.isNotEmpty &&
      (apiKey.isNotEmpty || !provider.requiresKey);
}

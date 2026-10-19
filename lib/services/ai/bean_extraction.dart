import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_prompt.dart';

// Reading a bean from a package or a shop link. This is the domain side of
// it — schema, instructions and unpacking the answer. Which provider
// answers does not matter to this file.
//
// Ground rule throughout: **What is not there stays `null`.** Not
// estimated, not inferred from the name, not "it'll be Washed anyway". An
// empty row costs the user a glance; a wrongly filled one costs them the
// rest of the bag.

/// What the model read from a package or a page. Every field may be
/// missing, and `null` here really means "was not there".
class BeanDraft {
  const BeanDraft({
    this.name,
    this.roaster,
    this.roastDate,
    this.isBlend,
    this.roastedFor,
    this.roastLevel,
    this.country,
    this.processing,
    this.variety,
    this.producer,
    this.weightGrams,
    this.cost,
    this.currency,
    this.taste = const [],
  });

  final String? name;
  final String? roaster;
  final DateTime? roastDate;
  final bool? isBlend;

  /// 'filter' | 'espresso' | 'omni'
  final String? roastedFor;

  /// 'ultra-light' | 'light' | 'medium' | 'dark'
  final String? roastLevel;

  final String? country;
  final String? processing;
  final String? variety;
  final String? producer;
  final double? weightGrams;
  final double? cost;

  /// The currency of the price. If it is anything other than euro, the
  /// price does NOT go into the form: that field is labeled "€", and a
  /// number from another country would look like a fact there.
  final String? currency;

  final List<String> taste;

  bool get isEmpty =>
      name == null &&
      roaster == null &&
      roastDate == null &&
      isBlend == null &&
      roastedFor == null &&
      roastLevel == null &&
      country == null &&
      processing == null &&
      variety == null &&
      producer == null &&
      weightGrams == null &&
      cost == null &&
      taste.isEmpty;

  /// The price, but only if it was given in euro.
  double? get costInEuro {
    if (cost == null) return null;
    final c = currency?.trim().toUpperCase();
    if (c == null || c.isEmpty) return cost;
    return (c == 'EUR' || c == '€') ? cost : null;
  }

  bool get hasForeignPrice => cost != null && costInEuro == null;

  factory BeanDraft.fromJson(Map<String, Object?> json) => BeanDraft(
    name: _text(json['name']),
    roaster: _text(json['roaster']),
    roastDate: _date(json['roastDate']),
    isBlend: _bool(json['isBlend']),
    roastedFor: _oneOf(json['roastedFor'], const [
      'filter',
      'espresso',
      'omni',
    ]),
    roastLevel: _oneOf(json['roastLevel'], const [
      'ultra-light',
      'light',
      'medium',
      'dark',
    ]),
    country: _text(json['country']),
    processing: _text(json['processing']),
    variety: _text(json['variety']),
    producer: _text(json['producer']),
    weightGrams: _number(json['weightGrams']),
    cost: _number(json['cost']),
    currency: _text(json['currency']),
    taste: _list(json['taste']),
  );

  // Everything here is deliberately lenient: the model mostly sticks to the
  // schema, but "mostly" is no basis when a number ends up in a weight
  // field. Whatever is not clearly readable becomes null — not half
  // adopted.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    // Some models write the word instead of the empty value.
    const empties = {'null', 'n/a', 'na', 'unknown', 'none', '-', '–', '—'};
    if (empties.contains(trimmed.toLowerCase())) return null;
    return trimmed;
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == 'blend') return true;
      if (v == 'false' || v == 'single origin') return false;
    }
    return null;
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      // "250 g", "17,50 €" — reading past the unit is friendlier than
      // throwing the value away.
      final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(value);
      if (match == null) return null;
      return double.tryParse(match.group(0)!.replaceAll(',', '.'));
    }
    return null;
  }

  static String? _oneOf(Object? value, List<String> allowed) {
    final text = _text(value)?.toLowerCase();
    return allowed.contains(text) ? text : null;
  }

  /// Only a real date, and only one that can lie in the past. A roast date
  /// in the future is almost always a best-before date that slipped
  /// through.
  static DateTime? _date(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final today = DateTime.now();
    if (parsed.isAfter(DateTime(today.year, today.month, today.day))) {
      return null;
    }
    if (parsed.year < 2000) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static List<String> _list(Object? value) {
    if (value is List) {
      return [for (final entry in value) ?_text(entry)];
    }
    // A comma-separated list in a string is fine too.
    final text = _text(value);
    if (text == null) return const [];
    return [for (final part in text.split(',')) ?_text(part)];
  }
}

/// The schema of the answer. Every field may be `null` — that is not
/// convenience here but the rule itself: the model MUST be able to say
/// "was not on it", otherwise it makes something up.
Map<String, Object?> beanDraftSchema() => aiObjectSchema({
  'name': aiNullable(
    'string',
    description:
        'The name of the coffee itself, not the roastery. E.g. "Kirinyaga AA".',
  ),
  'roaster': aiNullable('string', description: 'The roastery or brand.'),
  'roastDate': aiNullable(
    'string',
    description:
        'ISO date (YYYY-MM-DD) of ROASTING only — labelled "roasted on", '
        '"Röstdatum", "geröstet am". A best-before / use-by / '
        '"Mindesthaltbarkeitsdatum" is NOT a roast date: if only that is '
        'printed, return null. If in any doubt which one it is, return null.',
  ),
  'isBlend': aiNullable(
    'boolean',
    description: 'true for a blend, false for a single origin.',
  ),
  'roastedFor': aiNullable(
    'string',
    description:
        'One of "filter", "espresso", "omni" — only if the label says so.',
  ),
  'roastLevel': aiNullable(
    'string',
    description:
        'One of "ultra-light", "light", "medium", "dark" — only if the '
        'label names the roast level.',
  ),
  'country': aiNullable('string', description: 'Country of origin.'),
  'processing': aiNullable(
    'string',
    description: 'Washed, Natural, Honey, Anaerobic …',
  ),
  'variety': aiNullable('string', description: 'Bourbon, Geisha, Heirloom …'),
  'producer': aiNullable('string', description: 'Farm, co-op or producer.'),
  'weightGrams': aiNullable(
    'number',
    description: 'Net weight of the package in grams.',
  ),
  'cost': aiNullable(
    'number',
    description: 'Price of the package, number only.',
  ),
  'currency': aiNullable(
    'string',
    description: 'Currency of the price as a 3-letter code, e.g. EUR.',
  ),
  'taste': aiArray(
    aiField('string'),
    description:
        'Tasting notes as single words or short terms, as printed. Empty '
        'list if none are given.',
  ),
});

/// The role. The most important sentence is the one about not knowing: a
/// model that is praised for filling in, fills in.
const beanSystemPrompt =
    'You read coffee packaging and coffee shop pages and turn them into '
    'structured data.\n'
    'Rules, in order of importance:\n'
    '1. Only report what is actually there. If a field is not stated, return '
    'null for it. Never guess, never infer from the name, never fill a field '
    'because it would be plausible.\n'
    '2. A best-before date is not a roast date.\n'
    '3. Keep the wording of the label for origin, processing, variety and '
    'tasting notes — do not translate and do not tidy them up.\n'
    '4. If the input shows several different coffees, use the one that is '
    'most prominent, and nothing from the others.';

const beanImageTask =
    'This is a photo of a coffee package. Read every field you can see on it.';

String beanTextTask(String source, String text) =>
    'This is the text of a coffee product page ($source). Read the fields of '
    'the coffee it sells.\n\n$text';

/// Fetches a page and turns it into something a model can read.
///
/// The detour through the app is not a detour: a model cannot open an
/// address. Either the app fetches the page, or the link becomes an
/// invitation to make things up.
Future<String> fetchReadableText(
  Uri url, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 20),
  int maxChars = 20000,
}) async {
  final response = await client
      .get(
        url,
        headers: {
          // Without a recognizable browser many shops answer with a block
          // page instead of the product.
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
          'accept': 'text/html,application/xhtml+xml',
          'accept-language': 'de,en;q=0.8',
        },
      )
      .timeout(timeout);

  if (response.statusCode >= 400) {
    throw AiFailure(
      AiFailureKind.network,
      'The page answered with ${response.statusCode}.',
    );
  }
  final text = htmlToText(
    utf8.decode(response.bodyBytes, allowMalformed: true),
  );
  if (text.trim().length < 80) {
    // Typical for shops that build their page in the browser. Better to
    // report it honestly than to hand the model an empty page and then
    // wonder about empty fields.
    throw AiFailure(
      AiFailureKind.badResponse,
      'That page carries almost no readable text — it probably builds itself '
      'in the browser. A photo of the package works better.',
    );
  }
  return text.length > maxChars ? text.substring(0, maxChars) : text;
}

/// HTML to plain text. No parser, and that is enough: what is needed is not
/// the page's structure but its words.
String htmlToText(String html) {
  var text = html;
  // Scripts and styles add nothing but cost most of the tokens.
  text = text.replaceAll(
    RegExp(
      r'<(script|style|noscript|svg)[^>]*>[\s\S]*?</\1>',
      caseSensitive: false,
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  // Block ends as line breaks, otherwise "250 g" sticks to the next paragraph.
  text = text.replaceAll(
    RegExp(r'</(p|div|li|tr|h[1-6]|br)[^>]*>|<br\s*/?>', caseSensitive: false),
    '\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = _unescape(text);
  text = text.replaceAll(RegExp(r'[ \t\x00-\x08\x0b\x0c\x0e-\x1f]+'), ' ');
  // Strip whitespace around the line breaks: otherwise every line starts
  // with a space that only costs tokens.
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n\n\n+'), '\n\n');
  return text.trim();
}

String _unescape(String text) {
  const named = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&euro;': '€',
    '&auml;': 'ä',
    '&ouml;': 'ö',
    '&uuml;': 'ü',
    '&Auml;': 'Ä',
    '&Ouml;': 'Ö',
    '&Uuml;': 'Ü',
    '&szlig;': 'ß',
  };
  var result = text;
  named.forEach((entity, char) => result = result.replaceAll(entity, char));
  return result.replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(
      m.group(2)!,
      radix: m.group(1)!.isEmpty ? 10 : 16,
    );
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
}

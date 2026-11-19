// Coffee-growing countries, for the origin map in Statistics.
//
// The list covers the producing countries of the FAO production statistics
// plus smaller specialty origins (Jamaica, Hawaii, Taiwan, …). [lon]/[lat]
// mark the main growing region, not the middle of the country — Brazil sits
// in Minas Gerais, China in Yunnan, the United States on Hawaii — so the dots
// land where the coffee actually grows.

enum CoffeeRegion {
  africa('Africa'),
  americas('Americas'),
  asiaPacific('Asia & Pacific');

  const CoffeeRegion(this.label);
  final String label;
}

class CoffeeCountry {
  const CoffeeCountry(
    this.code,
    this.name,
    this.region,
    this.lon,
    this.lat, {
    this.aliases = const [],
    this.area,
  });

  /// ISO 3166-1 alpha-2.
  final String code;
  final String name;
  final CoffeeRegion region;

  /// Position of the main growing region.
  final double lon;
  final double lat;

  /// Other names a user may type: German names, islands, well-known areas.
  final List<String> aliases;

  /// The growing region the position stands for, where it differs from what
  /// one would expect.
  final String? area;
}

class CoffeeCountries {
  CoffeeCountries._();

  static const _af = CoffeeRegion.africa;
  static const _am = CoffeeRegion.americas;
  static const _as = CoffeeRegion.asiaPacific;

  static const List<CoffeeCountry> all = [
    // --- Africa ----------------------------------------------------------
    CoffeeCountry(
      'ET',
      'Ethiopia',
      _af,
      38.3,
      6.5,
      aliases: [
        'Äthiopien',
        'Aethiopien',
        'Ethiopie',
        'Yirgacheffe',
        'Sidamo',
        'Sidama',
        'Guji',
        'Harrar',
        'Limu',
      ],
    ),
    CoffeeCountry('KE', 'Kenya', _af, 36.95, -0.4, aliases: ['Kenia']),
    CoffeeCountry('RW', 'Rwanda', _af, 29.4, -2.2, aliases: ['Ruanda']),
    CoffeeCountry('BI', 'Burundi', _af, 29.6, -2.9),
    CoffeeCountry('UG', 'Uganda', _af, 34.4, 1.1, area: 'Mount Elgon'),
    CoffeeCountry(
      'TZ',
      'Tanzania',
      _af,
      37.3,
      -3.3,
      aliases: ['Tansania', 'Kilimanjaro'],
    ),
    CoffeeCountry(
      'CD',
      'DR Congo',
      _af,
      28.9,
      -2.5,
      aliases: [
        'Congo',
        'DRC',
        'Democratic Republic of the Congo',
        'Democratic Republic of Congo',
        'Kongo',
        'Kivu',
      ],
      area: 'Kivu',
    ),
    CoffeeCountry('MW', 'Malawi', _af, 33.9, -11.4),
    CoffeeCountry('ZM', 'Zambia', _af, 31.2, -10.2, aliases: ['Sambia']),
    CoffeeCountry('ZW', 'Zimbabwe', _af, 32.9, -19.8, aliases: ['Simbabwe']),
    CoffeeCountry(
      'MG',
      'Madagascar',
      _af,
      48.0,
      -19.0,
      aliases: ['Madagaskar'],
    ),
    CoffeeCountry('CM', 'Cameroon', _af, 10.4, 5.5, aliases: ['Kamerun']),
    CoffeeCountry(
      'CF',
      'Central African Republic',
      _af,
      18.6,
      4.4,
      aliases: ['CAR', 'Zentralafrikanische Republik'],
    ),
    CoffeeCountry(
      'CI',
      'Ivory Coast',
      _af,
      -6.0,
      6.5,
      aliases: ["Côte d'Ivoire", "Cote d'Ivoire", 'Elfenbeinküste'],
    ),
    CoffeeCountry('GN', 'Guinea', _af, -9.0, 8.5),
    CoffeeCountry('TG', 'Togo', _af, 0.8, 7.0),
    CoffeeCountry('AO', 'Angola', _af, 14.5, -11.0),

    // --- Americas --------------------------------------------------------
    CoffeeCountry(
      'BR',
      'Brazil',
      _am,
      -45.5,
      -21.0,
      aliases: ['Brasil', 'Brasilien', 'Minas Gerais', 'Cerrado', 'Mogiana'],
      area: 'Minas Gerais',
    ),
    CoffeeCountry(
      'CO',
      'Colombia',
      _am,
      -75.6,
      4.5,
      aliases: [
        'Kolumbien',
        'Columbia',
        'Huila',
        'Nariño',
        'Narino',
        'Cauca',
        'Tolima',
        'Antioquia',
      ],
    ),
    CoffeeCountry(
      'PE',
      'Peru',
      _am,
      -78.8,
      -6.0,
      aliases: ['Perú', 'Cajamarca'],
    ),
    CoffeeCountry(
      'EC',
      'Ecuador',
      _am,
      -79.2,
      -4.0,
      aliases: ['Loja', 'Galapagos'],
    ),
    CoffeeCountry(
      'BO',
      'Bolivia',
      _am,
      -67.6,
      -15.8,
      aliases: ['Bolivien', 'Caranavi'],
    ),
    CoffeeCountry('VE', 'Venezuela', _am, -69.8, 9.5),
    CoffeeCountry(
      'PA',
      'Panama',
      _am,
      -82.4,
      8.8,
      aliases: ['Panamá', 'Boquete', 'Chiriqui', 'Chiriquí'],
    ),
    CoffeeCountry(
      'CR',
      'Costa Rica',
      _am,
      -84.0,
      9.6,
      aliases: ['Tarrazu', 'Tarrazú'],
    ),
    CoffeeCountry('NI', 'Nicaragua', _am, -85.9, 13.1, aliases: ['Jinotega']),
    CoffeeCountry('HN', 'Honduras', _am, -88.0, 14.8),
    CoffeeCountry('SV', 'El Salvador', _am, -89.6, 13.9, aliases: ['Salvador']),
    CoffeeCountry(
      'GT',
      'Guatemala',
      _am,
      -90.7,
      14.6,
      aliases: ['Antigua', 'Huehuetenango'],
    ),
    CoffeeCountry(
      'MX',
      'Mexico',
      _am,
      -92.5,
      16.5,
      aliases: ['México', 'Mexiko', 'Chiapas', 'Oaxaca', 'Veracruz'],
      area: 'Chiapas',
    ),
    CoffeeCountry(
      'JM',
      'Jamaica',
      _am,
      -76.6,
      18.05,
      aliases: ['Jamaika', 'Blue Mountains'],
      area: 'Blue Mountains',
    ),
    CoffeeCountry('HT', 'Haiti', _am, -71.8, 18.25),
    CoffeeCountry(
      'DO',
      'Dominican Republic',
      _am,
      -70.7,
      18.8,
      aliases: ['Dominikanische Republik', 'República Dominicana'],
    ),
    CoffeeCountry('CU', 'Cuba', _am, -76.6, 20.1, aliases: ['Kuba']),
    CoffeeCountry('PR', 'Puerto Rico', _am, -66.7, 18.2),
    CoffeeCountry(
      'US',
      'United States',
      _am,
      -155.9,
      19.5,
      aliases: ['USA', 'Hawaii', 'Kona', 'Hawaii (USA)', 'Maui', 'Kauai'],
      area: 'Hawaii',
    ),

    // --- Asia & Pacific --------------------------------------------------
    CoffeeCountry('YE', 'Yemen', _as, 43.6, 15.2, aliases: ['Jemen', 'Haraz']),
    CoffeeCountry(
      'IN',
      'India',
      _as,
      75.7,
      13.3,
      aliases: ['Indien', 'Karnataka', 'Chikmagalur'],
      area: 'Karnataka',
    ),
    CoffeeCountry('LK', 'Sri Lanka', _as, 80.7, 7.0),
    CoffeeCountry('NP', 'Nepal', _as, 84.0, 28.0),
    CoffeeCountry('MM', 'Myanmar', _as, 96.6, 21.0, aliases: ['Burma', 'Shan']),
    CoffeeCountry(
      'CN',
      'China',
      _as,
      100.9,
      22.8,
      aliases: ['Yunnan', 'Pu’er', "Pu'er"],
      area: 'Yunnan',
    ),
    CoffeeCountry(
      'TH',
      'Thailand',
      _as,
      99.8,
      20.0,
      aliases: ['Chiang Rai', 'Chiang Mai'],
    ),
    CoffeeCountry('LA', 'Laos', _as, 106.3, 15.2, aliases: ['Bolaven']),
    CoffeeCountry(
      'VN',
      'Vietnam',
      _as,
      108.0,
      12.7,
      aliases: ['Viet Nam', 'Dak Lak', 'Da Lat', 'Dalat'],
    ),
    CoffeeCountry('KH', 'Cambodia', _as, 107.2, 12.5, aliases: ['Kambodscha']),
    CoffeeCountry('TW', 'Taiwan', _as, 120.8, 23.5, aliases: ['Alishan']),
    CoffeeCountry(
      'PH',
      'Philippines',
      _as,
      125.0,
      7.5,
      aliases: ['Philippinen'],
    ),
    CoffeeCountry(
      'ID',
      'Indonesia',
      _as,
      98.5,
      2.6,
      aliases: [
        'Indonesien',
        'Sumatra',
        'Java',
        'Sulawesi',
        'Bali',
        'Flores',
        'Aceh',
        'Toraja',
      ],
      area: 'Sumatra',
    ),
    CoffeeCountry(
      'TL',
      'Timor-Leste',
      _as,
      125.4,
      -8.8,
      aliases: ['East Timor', 'Osttimor', 'Timor'],
    ),
    CoffeeCountry(
      'PG',
      'Papua New Guinea',
      _as,
      145.4,
      -6.1,
      aliases: ['PNG', 'Papua-Neuguinea'],
    ),
    CoffeeCountry(
      'AU',
      'Australia',
      _as,
      145.5,
      -17.3,
      aliases: ['Australien'],
    ),
  ];

  static final Map<String, CoffeeCountry> byCode = {
    for (final c in all) c.code: c,
  };

  static final Map<String, CoffeeCountry> _byKey = {
    for (final c in all)
      for (final n in [c.name, c.code, ...c.aliases]) _key(n): c,
  };

  // Case, accents, spaces and punctuation do not matter.
  static String _key(String s) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'ae',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'oe',
      'ú': 'u',
      'ü': 'ue',
      'ñ': 'n',
      'ç': 'c',
    };
    final lower = s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// The country [text] names, or null if it is none we know.
  /// Two-letter codes only count in capitals, so "in" or "co" in running
  /// text never become India or Colombia.
  static CoffeeCountry? match(String text) {
    final t = text.trim();
    if (t.length == 2 && t != t.toUpperCase()) return null;
    return _byKey[_key(t)];
  }

  /// All countries in a bean's origin field, which may list several for a
  /// blend: "Brazil, Ethiopia", "Kolumbien & Peru".
  static List<CoffeeCountry> matchAll(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final whole = match(text);
    if (whole != null) return [whole];
    final found = <CoffeeCountry>[];
    for (final part in text.split(
      RegExp(r'\s*(?:,|;|/|&|\+|\band\b|\bund\b)\s*', caseSensitive: false),
    )) {
      final c = match(part);
      if (c != null && !found.contains(c)) found.add(c);
    }
    return found;
  }

  /// The countries of a bean: from its country field, or — when that is
  /// empty or unknown — from its region field ("Huila" → Colombia).
  static List<CoffeeCountry> forBean(String? country, String? region) {
    final fromCountry = matchAll(country);
    return fromCountry.isNotEmpty ? fromCountry : matchAll(region);
  }
}

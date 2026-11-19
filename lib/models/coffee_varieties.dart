// Arabica varieties and how they descend from each other, for the variety
// collection in Statistics.
//
// The facts (genetic group and parents) follow the World Coffee Research
// variety catalog, https://varieties.worldcoffeeresearch.org — written down
// here in our own words; the catalog's texts are not copied. Entries
// without a [CoffeeVariety.wcr] slug (specialty varieties the catalog does
// not list) come from other public sources and carry a [CoffeeVariety.note]
// where their origin is disputed.

/// The genetic lines a variety is sorted under.
enum VarietyLine {
  landrace('Ethiopian landraces'),
  typica('Typica line'),
  bourbon('Bourbon line'),
  typicaBourbon('Typica × Bourbon'),
  introgressed('Robusta hybrids'),
  catimor('Catimor'),
  sarchimor('Sarchimor'),
  f1Hybrid('F1 hybrids');

  const VarietyLine(this.label);
  final String label;
}

class CoffeeVariety {
  const CoffeeVariety(
    this.id,
    this.name,
    this.line, {
    this.parents = const [],
    this.aliases = const [],
    this.wcr,
    this.note,
  });

  final String id;
  final String name;
  final VarietyLine line;

  /// Ids of the direct parents. Empty for the roots of a line and for
  /// varieties whose parents are not in this list.
  final List<String> parents;

  /// Other spellings and names a user may type.
  final List<String> aliases;

  /// Slug of the variety's page in the World Coffee Research catalog.
  final String? wcr;

  /// Short remark shown with the variety, e.g. a parent outside the list
  /// or a disputed origin.
  final String? note;

  String? get sourceUrl => wcr == null
      ? null
      : 'https://varieties.worldcoffeeresearch.org/varieties/$wcr';

  bool get isRoot => parents.isEmpty;
}

class CoffeeVarieties {
  CoffeeVarieties._();

  static const _l = VarietyLine.landrace;
  static const _t = VarietyLine.typica;
  static const _b = VarietyLine.bourbon;
  static const _tb = VarietyLine.typicaBourbon;
  static const _cm = VarietyLine.catimor;
  static const _sm = VarietyLine.sarchimor;
  static const _in = VarietyLine.introgressed;
  static const _f1 = VarietyLine.f1Hybrid;

  static const List<CoffeeVariety> all = [
    // --- Ethiopian landraces -------------------------------------------
    CoffeeVariety(
      'ethiopian-landrace',
      'Ethiopian landrace',
      _l,
      aliases: [
        'Heirloom',
        'Ethiopian heirloom',
        'Landrace',
        'Ethiopian landraces',
        'Local landrace',
      ],
    ),
    CoffeeVariety(
      'gesha',
      'Gesha',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['Geisha', 'Geisha (Panama)', 'Gesha 1931', 'Panama Geisha'],
      wcr: 'geisha-panama',
    ),
    CoffeeVariety(
      'java',
      'Java',
      _l,
      parents: ['ethiopian-landrace'],
      wcr: 'java',
    ),
    CoffeeVariety(
      'ab3',
      'AB3',
      _l,
      parents: ['ethiopian-landrace'],
      wcr: 'ab3',
    ),
    CoffeeVariety(
      'rume-sudan',
      'Rume Sudan',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['Sudan Rume'],
      note: 'Wild coffee from the Boma Plateau, Sudan',
    ),
    CoffeeVariety(
      'wush-wush',
      'Wush Wush',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['Wushwush'],
    ),
    CoffeeVariety(
      '74110',
      '74110',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['JARC 74110'],
      note: 'Selection of the Jimma research centre',
    ),
    CoffeeVariety(
      '74158',
      '74158',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['JARC 74158'],
      note: 'Selection of the Jimma research centre',
    ),
    CoffeeVariety(
      'pink-bourbon',
      'Pink Bourbon',
      _l,
      parents: ['ethiopian-landrace'],
      aliases: ['Bourbon Rosado', 'Rosado'],
      note: 'Despite the name, DNA tests point to an Ethiopian landrace',
    ),
    CoffeeVariety(
      'sidra',
      'Sidra',
      _l,
      parents: ['ethiopian-landrace'],
      note: 'Origin disputed: often called Bourbon × Typica, DNA tests point to Ethiopia',
    ),

    // --- Typica line ---------------------------------------------------
    CoffeeVariety(
      'typica',
      'Typica',
      _t,
      aliases: ['Criollo', 'Arabigo', 'Blue Mountain', 'Sumatra'],
      wcr: 'typica',
    ),
    CoffeeVariety(
      'maragogipe',
      'Maragogipe',
      _t,
      parents: ['typica'],
      aliases: ['Maragogype', 'Elephant bean'],
      wcr: 'maragogipe',
    ),
    CoffeeVariety('pache', 'Pache', _t, parents: ['typica'], wcr: 'pache'),
    CoffeeVariety(
      'sl34',
      'SL34',
      _t,
      parents: ['typica'],
      aliases: ['SL 34', 'SL-34'],
      wcr: 'sl34',
    ),
    CoffeeVariety(
      'sl14',
      'SL14',
      _t,
      parents: ['typica'],
      aliases: ['SL 14', 'SL-14'],
      wcr: 'sl14',
    ),
    CoffeeVariety(
      'mibirizi',
      'Mibirizi',
      _t,
      parents: ['typica'],
      wcr: 'mibirizi',
    ),
    CoffeeVariety(
      'nyasaland',
      'Nyasaland',
      _t,
      parents: ['typica'],
      aliases: ['Nyasa'],
      wcr: 'nyasaland',
    ),
    CoffeeVariety(
      'harar-rwanda',
      'Harar Rwanda',
      _t,
      parents: ['typica'],
      wcr: 'harar-rwanda',
    ),
    CoffeeVariety('bpl10', 'BPL10', _t, parents: ['typica'], wcr: 'bpl10'),
    CoffeeVariety('caripe', 'Caripe', _t, parents: ['typica'], wcr: 'caripe'),
    CoffeeVariety(
      'pop3303',
      'Pop3303/21',
      _t,
      parents: ['typica'],
      aliases: ['Pop 3303'],
      wcr: 'pop3303',
      note: 'Selection of Blue Mountain',
    ),

    // --- Bourbon line --------------------------------------------------
    CoffeeVariety(
      'bourbon',
      'Bourbon',
      _b,
      aliases: ['Red Bourbon', 'Bourbon Rouge'],
      wcr: 'bourbon',
    ),
    CoffeeVariety(
      'yellow-bourbon',
      'Yellow Bourbon',
      _b,
      parents: ['bourbon'],
      aliases: ['Bourbon Amarelo'],
    ),
    CoffeeVariety(
      'laurina',
      'Laurina',
      _b,
      parents: ['bourbon'],
      aliases: ['Bourbon Pointu'],
    ),
    CoffeeVariety(
      'caturra',
      'Caturra',
      _b,
      parents: ['bourbon'],
      wcr: 'caturra',
    ),
    CoffeeVariety('pacas', 'Pacas', _b, parents: ['bourbon'], wcr: 'pacas'),
    CoffeeVariety(
      'villa-sarchi',
      'Villa Sarchi',
      _b,
      parents: ['bourbon'],
      aliases: ['Villalobos Sarchi'],
      wcr: 'villa-sarchi',
    ),
    CoffeeVariety(
      'venecia',
      'Venecia',
      _b,
      parents: ['bourbon'],
      wcr: 'venecia',
    ),
    CoffeeVariety(
      'tekisic',
      'Tekisic',
      _b,
      parents: ['bourbon'],
      wcr: 'tekisic',
    ),
    CoffeeVariety(
      'sl28',
      'SL28',
      _b,
      parents: ['bourbon'],
      aliases: ['SL 28', 'SL-28'],
      wcr: 'sl28',
    ),
    CoffeeVariety('k7', 'K7', _b, parents: ['bourbon'], wcr: 'k7'),
    CoffeeVariety(
      'bm71',
      'Bourbon Mayaguez 71',
      _b,
      parents: ['bourbon'],
      aliases: ['BM71'],
      wcr: 'bourbon-mayaguez-71',
    ),
    CoffeeVariety(
      'bm139',
      'Bourbon Mayaguez 139',
      _b,
      parents: ['bourbon'],
      aliases: ['BM139'],
      wcr: 'bourbon-mayaguez-139',
    ),
    CoffeeVariety(
      'jackson',
      'Jackson 2/1257',
      _b,
      parents: ['bourbon'],
      aliases: ['Jackson'],
      wcr: 'jackson-2-1257',
    ),
    CoffeeVariety('kent', 'Kent', _b, parents: ['bourbon'], aliases: ['Kents']),
    CoffeeVariety('kp423', 'KP423', _b, parents: ['kent'], wcr: 'kp423'),

    // --- Typica × Bourbon ----------------------------------------------
    CoffeeVariety(
      'mundo-novo',
      'Mundo Novo',
      _tb,
      parents: ['typica', 'bourbon'],
      wcr: 'mundo-novo',
    ),
    CoffeeVariety('acaia', 'Acaia', _tb, parents: ['mundo-novo']),
    CoffeeVariety(
      'catuai',
      'Catuai',
      _tb,
      parents: ['mundo-novo', 'caturra'],
      aliases: [
        'Catuaí',
        'Yellow Catuai',
        'Red Catuai',
        'Catuai Amarelo',
        'Catuai Vermelho',
      ],
      wcr: 'catuai',
    ),
    CoffeeVariety(
      'pacamara',
      'Pacamara',
      _tb,
      parents: ['pacas', 'maragogipe'],
      wcr: 'pacamara',
    ),

    // --- Robusta hybrids: the Timor Hybrid and what came from it -------
    CoffeeVariety(
      'timor-hybrid',
      'Timor Hybrid',
      _in,
      aliases: ['Hibrido de Timor', 'HdT'],
      note: 'Natural cross of arabica and robusta from Timor',
    ),

    // Catimor: Timor Hybrid × Caturra
    CoffeeVariety(
      'castillo',
      'Castillo',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
    ),
    CoffeeVariety(
      'colombia',
      'Colombia',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      aliases: ['Variedad Colombia'],
    ),
    CoffeeVariety(
      'costa-rica-95',
      'Costa Rica 95',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      aliases: ['CR95'],
      wcr: 'costa-rica-95',
    ),
    CoffeeVariety(
      'ihcafe-90',
      'IHCAFE 90',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'ihcafe-90',
    ),
    CoffeeVariety(
      'lempira',
      'Lempira',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'lempira',
    ),
    CoffeeVariety(
      'oro-azteca',
      'Oro Azteca',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'oro-azteca',
    ),
    CoffeeVariety(
      't5175',
      'T5175',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 't5175',
    ),
    CoffeeVariety(
      't8667',
      'T8667',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 't8667',
    ),
    CoffeeVariety(
      'catisic',
      'Catisic',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'catisic',
    ),
    CoffeeVariety(
      'fronton',
      'Fronton',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'fronton',
    ),
    CoffeeVariety(
      'catimor-129',
      'Catimor 129',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      aliases: ['Nyika'],
      wcr: 'catimor-129',
    ),
    CoffeeVariety(
      'kartika-1',
      'Kartika 1',
      _cm,
      parents: ['timor-hybrid', 'caturra'],
      wcr: 'kartika-1',
    ),
    CoffeeVariety(
      'anacafe-14',
      'Anacafe 14',
      _cm,
      parents: ['timor-hybrid', 'caturra', 'pacamara'],
      wcr: 'anacafe-14',
    ),

    // Sarchimor: Timor Hybrid × Villa Sarchi
    CoffeeVariety(
      't5296',
      'T5296',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      wcr: 't5296',
    ),
    CoffeeVariety(
      'iapar-59',
      'IAPAR 59',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      wcr: 'iapar-59',
    ),
    CoffeeVariety(
      'limani',
      'Limani',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      wcr: 'limani',
    ),
    CoffeeVariety(
      'marsellesa',
      'Marsellesa',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      wcr: 'marsellesa',
    ),
    CoffeeVariety(
      'monte-claro',
      'Monte Claro',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      wcr: 'monte-claro',
    ),
    CoffeeVariety(
      'obata',
      'Obata',
      _sm,
      parents: ['timor-hybrid', 'villa-sarchi'],
      aliases: ['Obata Red', 'Obatã'],
      wcr: 'obata-red',
    ),
    CoffeeVariety(
      'cuscatleco',
      'Cuscatleco',
      _sm,
      parents: ['t5296'],
      wcr: 'cuscatleco',
    ),
    CoffeeVariety(
      'parainema',
      'Parainema',
      _sm,
      parents: ['t5296'],
      wcr: 'parainema',
    ),
    CoffeeVariety(
      'ipr-107',
      'IPR 107',
      _sm,
      parents: ['iapar-59'],
      wcr: 'ipr-107',
    ),
    CoffeeVariety(
      'ipr-103',
      'IPR 103',
      _sm,
      parents: ['catuai'],
      wcr: 'ipr-103',
      note: 'Catuai × Icatu',
    ),
    CoffeeVariety(
      'paraiso',
      'Paraiso',
      _sm,
      parents: ['catuai', 'timor-hybrid'],
      aliases: ['Paraíso'],
      wcr: 'paraiso',
    ),
    CoffeeVariety('arara', 'Arara', _sm, parents: ['obata', 'catuai']),

    // Other robusta hybrids
    CoffeeVariety(
      'tabi',
      'Tabi',
      _in,
      parents: ['typica', 'bourbon', 'timor-hybrid'],
    ),
    CoffeeVariety(
      'batian',
      'Batian',
      _in,
      parents: ['sl28', 'sl34', 'k7', 'rume-sudan', 'timor-hybrid'],
      wcr: 'batian',
    ),
    CoffeeVariety(
      'catigua-mg2',
      'Catigua MG2',
      _in,
      parents: ['catuai', 'timor-hybrid'],
      wcr: 'catigua-mg2',
    ),
    CoffeeVariety(
      's4808',
      'S4808',
      _in,
      parents: ['catuai', 'timor-hybrid'],
      wcr: 's4808',
    ),
    CoffeeVariety(
      's795',
      'S795',
      _in,
      parents: ['kent'],
      aliases: ['Selection 3'],
      wcr: 's795',
      note: 'S288 × Kent',
    ),
    CoffeeVariety(
      'sln-6',
      'Sln.6',
      _in,
      parents: ['kent'],
      aliases: ['S.2828'],
      wcr: 'sln-6',
      note: 'Kent × robusta',
    ),
    CoffeeVariety(
      'rab-c15',
      'RAB C15',
      _in,
      parents: ['sln-6'],
      wcr: 'rab-c15',
    ),
    CoffeeVariety(
      'sln-5b',
      'Sln.5B',
      _in,
      aliases: ['S.2931'],
      wcr: 'sln-5b',
      note: 'Devamachy × arabica',
    ),

    // --- F1 hybrids ----------------------------------------------------
    CoffeeVariety(
      'centroamericano',
      'Centroamericano',
      _f1,
      parents: ['t5296', 'rume-sudan'],
      aliases: ['H1'],
      wcr: 'centroamericano',
    ),
    CoffeeVariety(
      'milenio',
      'Milenio',
      _f1,
      parents: ['t5296', 'rume-sudan'],
      aliases: ['H10'],
      wcr: 'milenio',
    ),
    CoffeeVariety(
      'esperanza',
      'Esperanza',
      _f1,
      parents: ['t5296', 'ethiopian-landrace'],
      aliases: ['L4A5'],
      wcr: 'esperanza',
    ),
    CoffeeVariety(
      'mundo-maya',
      'Mundo Maya',
      _f1,
      parents: ['t5296', 'ethiopian-landrace'],
      aliases: ['EC16'],
      wcr: 'mundo-maya',
    ),
    CoffeeVariety(
      'h3',
      'H3',
      _f1,
      parents: ['caturra', 'ethiopian-landrace'],
      wcr: 'h3',
    ),
    CoffeeVariety(
      'casiopea',
      'Casiopea',
      _f1,
      parents: ['caturra', 'ethiopian-landrace'],
      wcr: 'casiopea',
    ),
    CoffeeVariety(
      'starmaya',
      'Starmaya',
      _f1,
      parents: ['marsellesa', 'ethiopian-landrace'],
      wcr: 'starmaya',
    ),
    CoffeeVariety(
      'ec15',
      'EC15',
      _f1,
      parents: ['ethiopian-landrace'],
      aliases: ['MundoMex'],
      wcr: 'ec15',
      note: 'Catimor × Ethiopian landrace',
    ),
    CoffeeVariety(
      'evaluna',
      'Evaluna',
      _f1,
      parents: ['ethiopian-landrace'],
      aliases: ['EC18'],
      wcr: 'evaluna',
      note: 'Catimor × Ethiopian landrace',
    ),
    CoffeeVariety(
      'nayarita',
      'Nayarita',
      _f1,
      parents: ['ethiopian-landrace'],
      aliases: ['EC19'],
      wcr: 'nayarita',
      note: 'Catimor × Ethiopian landrace',
    ),
    CoffeeVariety(
      'ruiru-11',
      'Ruiru 11',
      _f1,
      parents: ['sl28', 'k7', 'rume-sudan'],
      aliases: ['Ruiru11'],
      wcr: 'ruiru-11',
      note: 'Catimor × a cross of Kenyan varieties',
    ),
  ];

  static final Map<String, CoffeeVariety> byId = {for (final v in all) v.id: v};

  static final Map<String, CoffeeVariety> _byKey = {
    for (final v in all)
      for (final n in [v.name, ...v.aliases]) _key(n): v,
  };

  // Case, accents, spaces and punctuation do not matter: "SL-28", "sl 28"
  // and "SL28" are the same variety.
  static String _key(String s) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'í': 'i',
      'ó': 'o',
      'õ': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    final lower = s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// The variety [text] names, or null if it is none we know.
  static CoffeeVariety? match(String text) => _byKey[_key(text)];

  /// All known varieties in a bean's variety field, which may list several:
  /// "Caturra, Castillo", "SL28 & SL34", "Bourbon / Typica".
  static List<CoffeeVariety> matchAll(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final whole = match(text);
    if (whole != null) return [whole];
    final found = <CoffeeVariety>[];
    for (final part in text.split(
      RegExp(r'\s*(?:,|;|/|&|\+|\band\b|\bund\b)\s*', caseSensitive: false),
    )) {
      final v = match(part);
      if (v != null && !found.contains(v)) found.add(v);
    }
    return found;
  }

  /// Direct children of [id], in list order.
  static List<CoffeeVariety> childrenOf(String id) => [
    for (final v in all)
      if (v.parents.contains(id)) v,
  ];

  /// Every ancestor of [id], nearest first, without duplicates.
  static List<CoffeeVariety> ancestorsOf(String id) {
    final out = <CoffeeVariety>[];
    final queue = [...?byId[id]?.parents];
    while (queue.isNotEmpty) {
      final p = byId[queue.removeAt(0)];
      if (p == null || out.contains(p)) continue;
      out.add(p);
      queue.addAll(p.parents);
    }
    return out;
  }
}

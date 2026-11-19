// A short profile per coffee country — the reward that unlocks in
// Statistics once a bean from that country has been brewed.
//
// Facts (altitude, harvest, processing, varieties) are the commonly given
// ranges, written in our own words; production figures are FAO tonnes as
// listed on Wikipedia's "List of countries by coffee production" (null for
// small producers outside that list). "Typical cup" is a generalisation by
// nature and is shown as such.

import 'coffee_countries.dart';

class CoffeeCountryProfile {
  const CoffeeCountryProfile(
    this.code, {
    required this.altitude,
    required this.harvest,
    required this.process,
    this.varieties = const [],
    this.productionTonnes,
    required this.typicalCup,
    required this.fact,
  });

  /// ISO code, a key of [CoffeeCountries.byCode].
  final String code;

  /// Usual growing altitude, e.g. "1,400–2,000 m".
  final String altitude;

  /// Main harvest months, e.g. "Oct–Dec · fly crop Apr–Jun".
  final String harvest;
  final List<String> process;

  /// Ids from [CoffeeVarieties] — tapping one opens the variety tree.
  final List<String> varieties;
  final int? productionTonnes;

  /// Two to four words, e.g. ["blackcurrant", "juicy", "bright"].
  final List<String> typicalCup;

  /// One sentence worth knowing.
  final String fact;

  CoffeeCountry get country => CoffeeCountries.byCode[code]!;
}

class CoffeeCountryProfiles {
  CoffeeCountryProfiles._();

  static const List<CoffeeCountryProfile> all = [
    // --- Africa ------------------------------------------------------------
    CoffeeCountryProfile(
      'ET',
      altitude: '1,500–2,200 m',
      harvest: 'Oct–Jan',
      process: ['washed', 'natural'],
      varieties: ['ethiopian-landrace', '74110', '74158'],
      productionTonnes: 559400,
      typicalCup: ['floral', 'citrus', 'berries'],
      fact: "Arabica's birthplace: coffee still grows wild in the forests, and about half the harvest is drunk at home.",
    ),
    CoffeeCountryProfile(
      'KE',
      altitude: '1,400–2,000 m',
      harvest: 'Oct–Dec · fly crop Apr–Jun',
      process: ['washed'],
      varieties: ['sl28', 'sl34', 'ruiru-11', 'batian'],
      productionTonnes: 48700,
      typicalCup: ['blackcurrant', 'juicy', 'bright'],
      fact: 'Beans are sorted by size (AA, AB) and traditionally sold at a weekly auction in Nairobi.',
    ),
    CoffeeCountryProfile(
      'RW',
      altitude: '1,400–2,000 m',
      harvest: 'Mar–Jul',
      process: ['washed', 'natural'],
      varieties: ['bourbon'],
      productionTonnes: 27104,
      typicalCup: ['red fruit', 'floral', 'sweet'],
      fact: 'Most coffee goes through small washing stations spread over the "land of a thousand hills".',
    ),
    CoffeeCountryProfile(
      'BI',
      altitude: '1,500–2,000 m',
      harvest: 'Mar–Jul',
      process: ['washed', 'natural'],
      varieties: ['bourbon'],
      typicalCup: ['red berries', 'black tea', 'sweet'],
      fact: 'Grown almost entirely by smallholders, each with a small plot of trees.',
    ),
    CoffeeCountryProfile(
      'UG',
      altitude: '1,200–2,300 m',
      harvest: 'Oct–Feb',
      process: ['natural', 'washed'],
      varieties: ['sl14', 'sl28', 'nyasaland'],
      productionTonnes: 384000,
      typicalCup: ['chocolate', 'winey', 'full body'],
      fact: "One of Africa's largest exporters – mostly robusta, which grows wild in its forests.",
    ),
    CoffeeCountryProfile(
      'TZ',
      altitude: '1,200–2,000 m',
      harvest: 'Jul–Dec',
      process: ['washed'],
      varieties: ['bourbon', 'kent'],
      productionTonnes: 62917,
      typicalCup: ['bright', 'black tea', 'citrus'],
      fact: 'Known for peaberries – single round beans that are sorted out and sold on their own.',
    ),
    CoffeeCountryProfile(
      'CD',
      altitude: '1,400–2,000 m',
      harvest: 'Mar–Jul (Kivu)',
      process: ['washed'],
      varieties: ['bourbon'],
      productionTonnes: 62217,
      typicalCup: ['fruity', 'winey', 'sweet'],
      fact: 'Kivu coffee grows on the volcanic shores of Lake Kivu, right across the water from Rwanda.',
    ),
    CoffeeCountryProfile(
      'MW',
      altitude: '1,200–2,000 m',
      harvest: 'Apr–Aug',
      process: ['washed'],
      varieties: ['nyasaland', 'catimor-129'],
      productionTonnes: 11000,
      typicalCup: ['soft', 'nutty', 'tea-like'],
      fact: 'The Nyasaland variety still carries the name the country had before independence.',
    ),
    CoffeeCountryProfile(
      'ZM',
      altitude: '1,200–1,800 m',
      harvest: 'Apr–Aug',
      process: ['washed'],
      varieties: ['catimor-129'],
      typicalCup: ['mild', 'citrus', 'floral'],
      fact:
          'A small origin: most of its coffee comes from a handful of estates.',
    ),
    CoffeeCountryProfile(
      'ZW',
      altitude: '1,000–2,000 m',
      harvest: 'Apr–Sep',
      process: ['washed'],
      varieties: ['catimor-129', 'sl28'],
      typicalCup: ['bright', 'blackcurrant', 'sweet'],
      fact: 'Production collapsed in the 2000s and is slowly coming back in the Eastern Highlands.',
    ),
    CoffeeCountryProfile(
      'MG',
      altitude: '0–1,500 m',
      harvest: 'May–Oct',
      process: ['natural'],
      productionTonnes: 49344,
      typicalCup: ['earthy', 'woody'],
      fact:
          'Home to dozens of wild coffee species found nowhere else on earth.',
    ),
    CoffeeCountryProfile(
      'CM',
      altitude: '1,000–2,000 m',
      harvest: 'Oct–Jan',
      process: ['washed', 'natural'],
      varieties: ['java'],
      typicalCup: ['earthy', 'chocolate'],
      fact: 'The Java variety now grown in Central America was selected here.',
    ),
    CoffeeCountryProfile(
      'CF',
      altitude: '400–900 m',
      harvest: 'Nov–Feb',
      process: ['natural'],
      productionTonnes: 316108,
      typicalCup: ['earthy', 'dark chocolate'],
      fact: 'Almost all of its coffee is robusta.',
    ),
    CoffeeCountryProfile(
      'CI',
      altitude: '200–600 m',
      harvest: 'Oct–Feb',
      process: ['natural'],
      productionTonnes: 91327,
      typicalCup: ['earthy', 'nutty'],
      fact: "In the 1970s one of the world's three largest producers – almost entirely robusta.",
    ),
    CoffeeCountryProfile(
      'GN',
      altitude: '400–1,000 m',
      harvest: 'Nov–Feb',
      process: ['natural'],
      productionTonnes: 200000,
      typicalCup: ['earthy', 'woody'],
      fact: 'Coffee from the forest region around Macenta carries a protected origin name, "Ziama-Macenta".',
    ),
    CoffeeCountryProfile(
      'TG',
      altitude: '300–900 m',
      harvest: 'Oct–Jan',
      process: ['natural'],
      productionTonnes: 22895,
      typicalCup: ['earthy', 'nutty'],
      fact: 'Coffee grows in the hilly Plateaux region along the border with Ghana.',
    ),
    CoffeeCountryProfile(
      'AO',
      altitude: '800–1,500 m',
      harvest: 'May–Aug',
      process: ['natural'],
      productionTonnes: 20071,
      typicalCup: ['earthy', 'chocolate'],
      fact: "In the early 1970s one of the world's largest producers – until the civil war.",
    ),

    // --- Americas ----------------------------------------------------------
    CoffeeCountryProfile(
      'BR',
      altitude: '700–1,400 m',
      harvest: 'May–Sep',
      process: ['natural', 'pulped natural'],
      varieties: ['mundo-novo', 'catuai', 'bourbon', 'yellow-bourbon', 'acaia'],
      productionTonnes: 3405267,
      typicalCup: ['chocolate', 'nutty', 'low acidity'],
      fact: "About a third of the world's coffee – on the flat Cerrado largely picked by machine.",
    ),
    CoffeeCountryProfile(
      'CO',
      altitude: '1,200–2,000 m',
      harvest: 'Oct–Jan · mitaca Apr–Jun',
      process: ['washed'],
      varieties: ['caturra', 'castillo', 'colombia', 'typica'],
      productionTonnes: 680858,
      typicalCup: ['caramel', 'red fruit', 'balanced'],
      fact: 'Two harvests a year in many regions: the main crop and a smaller one, the "mitaca".',
    ),
    CoffeeCountryProfile(
      'PE',
      altitude: '1,000–2,000 m',
      harvest: 'May–Sep',
      process: ['washed'],
      varieties: ['typica', 'caturra', 'bourbon'],
      productionTonnes: 369551,
      typicalCup: ['soft', 'sweet', 'nutty'],
      fact: 'One of the largest sources of certified organic coffee.',
    ),
    CoffeeCountryProfile(
      'EC',
      altitude: '1,200–2,000 m',
      harvest: 'May–Sep',
      process: ['washed', 'natural'],
      varieties: ['typica', 'sidra', 'caturra'],
      typicalCup: ['floral', 'sweet', 'delicate'],
      fact: 'Sidra became known here – and coffee even grows on the Galápagos.',
    ),
    CoffeeCountryProfile(
      'BO',
      altitude: '1,200–2,300 m',
      harvest: 'Jul–Oct',
      process: ['washed'],
      varieties: ['typica', 'caturra'],
      productionTonnes: 23579,
      typicalCup: ['sweet', 'floral', 'clean'],
      fact: 'Most coffee grows in the steep Yungas valleys below La Paz.',
    ),
    CoffeeCountryProfile(
      'VE',
      altitude: '600–1,800 m',
      harvest: 'Sep–Feb',
      process: ['washed'],
      varieties: ['typica', 'bourbon'],
      productionTonnes: 56381,
      typicalCup: ['mild', 'nutty'],
      fact: 'Coffee was the main export – until oil took over.',
    ),
    CoffeeCountryProfile(
      'PA',
      altitude: '1,200–2,000 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'natural'],
      varieties: ['gesha', 'caturra', 'catuai', 'typica'],
      productionTonnes: 12760,
      typicalCup: ['jasmine', 'bergamot', 'tropical fruit'],
      fact: 'Gesha from Boquete regularly sets world-record prices at auction.',
    ),
    CoffeeCountryProfile(
      'CR',
      altitude: '1,200–1,900 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'honey'],
      varieties: ['caturra', 'catuai', 'villa-sarchi'],
      productionTonnes: 78822,
      typicalCup: ['bright', 'clean', 'honey'],
      fact: 'Its micro-mills made "honey" processing famous: sticky fruit is left on the bean while it dries.',
    ),
    CoffeeCountryProfile(
      'NI',
      altitude: '1,100–1,700 m',
      harvest: 'Nov–Mar',
      process: ['washed'],
      varieties: ['caturra', 'bourbon', 'maragogipe', 'pacamara'],
      productionTonnes: 143337,
      typicalCup: ['chocolate', 'sweet', 'mild'],
      fact: 'Much of it grows under shade trees in the cloud forests of Jinotega and Matagalpa.',
    ),
    CoffeeCountryProfile(
      'HN',
      altitude: '1,000–1,800 m',
      harvest: 'Nov–Apr',
      process: ['washed'],
      varieties: ['caturra', 'catuai', 'ihcafe-90', 'parainema', 'lempira'],
      productionTonnes: 384361,
      typicalCup: ['caramel', 'stone fruit', 'sweet'],
      fact: "Central America's largest coffee producer.",
    ),
    CoffeeCountryProfile(
      'SV',
      altitude: '1,000–1,800 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'natural', 'honey'],
      varieties: ['bourbon', 'pacas', 'pacamara'],
      productionTonnes: 32326,
      typicalCup: ['sweet', 'chocolate', 'soft'],
      fact: 'Pacas and Pacamara were born here, and many farms still grow old Bourbon.',
    ),
    CoffeeCountryProfile(
      'GT',
      altitude: '1,300–2,000 m',
      harvest: 'Dec–Apr',
      process: ['washed'],
      varieties: ['bourbon', 'caturra', 'catuai', 'typica'],
      productionTonnes: 225327,
      typicalCup: ['chocolate', 'spice', 'bright'],
      fact: "Volcanoes, lakes and rainforest shape its eight regions – Antigua's soil is volcanic ash.",
    ),
    CoffeeCountryProfile(
      'MX',
      altitude: '900–1,700 m',
      harvest: 'Nov–Mar',
      process: ['washed'],
      varieties: ['typica', 'bourbon', 'caturra'],
      productionTonnes: 194916,
      typicalCup: ['light', 'nutty', 'chocolate'],
      fact:
          'A large share comes from small organic farms in Chiapas and Oaxaca.',
    ),
    CoffeeCountryProfile(
      'JM',
      altitude: '900–1,700 m',
      harvest: 'Aug–Mar',
      process: ['washed'],
      varieties: ['typica'],
      typicalCup: ['mild', 'clean', 'sweet'],
      fact: 'Jamaica Blue Mountain is shipped in wooden barrels instead of sacks.',
    ),
    CoffeeCountryProfile(
      'HT',
      altitude: '600–1,500 m',
      harvest: 'Sep–Jan',
      process: ['washed', 'natural'],
      varieties: ['typica'],
      typicalCup: ['mild', 'sweet', 'nutty'],
      fact: "In the late 1700s it produced about half of the world's coffee.",
    ),
    CoffeeCountryProfile(
      'DO',
      altitude: '600–1,500 m',
      harvest: 'Oct–Feb',
      process: ['washed'],
      varieties: ['typica', 'caturra'],
      productionTonnes: 23446,
      typicalCup: ['chocolate', 'mild'],
      fact: 'Barahona in the south-west is its best-known coffee region.',
    ),
    CoffeeCountryProfile(
      'CU',
      altitude: '300–1,000 m',
      harvest: 'Sep–Jan',
      process: ['washed'],
      varieties: ['typica'],
      typicalCup: ['mild', 'earthy', 'sweet'],
      fact: 'Coffee arrived in the 1740s; today it grows mainly in the Sierra Maestra.',
    ),
    CoffeeCountryProfile(
      'PR',
      altitude: '600–1,000 m',
      harvest: 'Aug–Feb',
      process: ['washed'],
      varieties: ['typica', 'bourbon'],
      typicalCup: ['sweet', 'nutty', 'mild'],
      fact: 'Prized in Europe in the late 1800s – hurricanes have shrunk the industry since.',
    ),
    CoffeeCountryProfile(
      'US',
      altitude: '150–900 m',
      harvest: 'Aug–Jan',
      process: ['washed'],
      varieties: ['typica'],
      typicalCup: ['smooth', 'sweet', 'mild'],
      fact: 'Hawaii is the only US state that grows coffee commercially.',
    ),

    // --- Asia & Pacific ----------------------------------------------------
    CoffeeCountryProfile(
      'YE',
      altitude: '1,500–2,500 m',
      harvest: 'Oct–Feb',
      process: ['natural'],
      productionTonnes: 30291,
      typicalCup: ['winey', 'dried fruit', 'spice'],
      fact: 'The port of Mocha gave its name to coffee from here – and later to the drink.',
    ),
    CoffeeCountryProfile(
      'IN',
      altitude: '1,000–1,500 m',
      harvest: 'Nov–Feb',
      process: ['washed', 'natural', 'monsooned'],
      varieties: ['kent', 'sln-6'],
      productionTonnes: 332848,
      typicalCup: ['spice', 'low acidity', 'full body'],
      fact: '"Monsooned Malabar" beans are left in monsoon winds for weeks until they turn pale and mellow.',
    ),
    CoffeeCountryProfile(
      'LK',
      altitude: '600–1,500 m',
      harvest: 'Nov–Feb',
      process: ['natural'],
      varieties: ['typica'],
      typicalCup: ['mild', 'earthy'],
      fact: 'A big coffee island until leaf rust wiped out the farms in the 1870s – it switched to tea.',
    ),
    CoffeeCountryProfile(
      'NP',
      altitude: '800–1,600 m',
      harvest: 'Nov–Feb',
      process: ['washed'],
      varieties: ['bourbon', 'typica'],
      typicalCup: ['sweet', 'nutty', 'mild'],
      fact: 'A young origin: smallholders in the hills, mostly organic by default.',
    ),
    CoffeeCountryProfile(
      'MM',
      altitude: '1,000–1,500 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'natural'],
      varieties: ['sl34', 'catuai'],
      typicalCup: ['fruity', 'sweet'],
      fact: 'Specialty coffee took off only in the 2010s, often replacing opium poppy.',
    ),
    CoffeeCountryProfile(
      'CN',
      altitude: '1,000–1,700 m',
      harvest: 'Nov–Mar',
      process: ['washed'],
      productionTonnes: 108000,
      typicalCup: ['sweet', 'nutty', 'mild'],
      fact: "Yunnan grows almost all of China's coffee – first planted there by a French missionary around 1900.",
    ),
    CoffeeCountryProfile(
      'TH',
      altitude: '1,000–1,500 m',
      harvest: 'Nov–Mar',
      process: ['washed'],
      productionTonnes: 16575,
      typicalCup: ['sweet', 'nutty'],
      fact: 'Arabica in the north was promoted by the Royal Projects as a replacement for opium.',
    ),
    CoffeeCountryProfile(
      'LA',
      altitude: '1,000–1,300 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'natural'],
      varieties: ['typica'],
      productionTonnes: 177662,
      typicalCup: ['nutty', 'mild'],
      fact: 'The French first planted coffee on the volcanic Bolaven Plateau in the early 1900s.',
    ),
    CoffeeCountryProfile(
      'VN',
      altitude: '500–1,500 m',
      harvest: 'Oct–Jan',
      process: ['natural', 'washed'],
      productionTonnes: 1956782,
      typicalCup: ['bold', 'dark chocolate'],
      fact: "The world's second-largest producer – mostly robusta – and home of egg coffee.",
    ),
    CoffeeCountryProfile(
      'KH',
      altitude: '300–800 m',
      harvest: 'Nov–Feb',
      process: ['natural'],
      productionTonnes: 24266,
      typicalCup: ['earthy', 'bold'],
      fact: 'Coffee grows mainly in Mondulkiri and Ratanakiri along the border with Vietnam.',
    ),
    CoffeeCountryProfile(
      'TW',
      altitude: '800–1,200 m',
      harvest: 'Oct–Mar',
      process: ['washed', 'natural'],
      varieties: ['typica', 'gesha'],
      typicalCup: ['sweet', 'floral', 'tea-like'],
      fact: 'A tiny origin, but coffee from the tea mountains of Alishan fetches very high prices.',
    ),
    CoffeeCountryProfile(
      'PH',
      altitude: '600–1,600 m',
      harvest: 'Nov–Mar',
      process: ['natural', 'washed'],
      productionTonnes: 30023,
      typicalCup: ['bold', 'earthy', 'smoky'],
      fact: 'One of the few places growing arabica, robusta and liberica – locally "Kapeng Barako".',
    ),
    CoffeeCountryProfile(
      'ID',
      altitude: '1,000–1,700 m',
      harvest: 'Varies by island',
      process: ['wet-hulled', 'washed'],
      varieties: ['typica'],
      productionTonnes: 760192,
      typicalCup: ['earthy', 'herbal', 'full body'],
      fact: 'Wet-hulling ("giling basah") gives Sumatra its famously earthy, heavy cup.',
    ),
    CoffeeCountryProfile(
      'TL',
      altitude: '800–1,600 m',
      harvest: 'May–Sep',
      process: ['washed'],
      varieties: ['timor-hybrid', 'typica'],
      typicalCup: ['sweet', 'chocolate', 'herbal'],
      fact: 'The Timor Hybrid – parent of Catimor and Sarchimor – was found here in the 1920s.',
    ),
    CoffeeCountryProfile(
      'PG',
      altitude: '1,300–1,900 m',
      harvest: 'Apr–Sep',
      process: ['washed'],
      varieties: ['typica', 'bourbon'],
      productionTonnes: 45371,
      typicalCup: ['fruity', 'sweet', 'herbal'],
      fact: 'Its Typica descends from Jamaica Blue Mountain seed brought in during the 1930s.',
    ),
    CoffeeCountryProfile(
      'AU',
      altitude: '300–1,000 m',
      harvest: 'May–Oct',
      process: ['washed'],
      typicalCup: ['mild', 'sweet', 'low acidity'],
      fact: 'One of the few wealthy countries growing coffee – largely picked by machine.',
    ),
  ];

  static final Map<String, CoffeeCountryProfile> byCode = {
    for (final p in all) p.code: p,
  };

  /// Rank by production among the countries with a figure: 1 = largest.
  static int? productionRank(String code) {
    final p = byCode[code]?.productionTonnes;
    if (p == null) return null;
    return 1 + all.where((o) => (o.productionTonnes ?? 0) > p).length;
  }
}

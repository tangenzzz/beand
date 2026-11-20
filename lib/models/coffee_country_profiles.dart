// A short profile per coffee country — the reward that unlocks in
// Statistics once a bean from that country has been brewed.
//
// Every value was checked against the sources listed with it (Cafe Imports
// origin pages, Wikipedia, Starbucks origin sheets hosted by ASU, an FAO
// country table, World Coffee Research and a few trade articles; checked
// 2026-11-20) and written in our own words. Where no source gave a value it
// is left out rather than guessed — the UI shows only what is there.
// Production figures are FAO tonnes as listed on Wikipedia's "List of
// countries by coffee production" (null for small producers outside it).
// Ranges are the ones the sources state; sources disagree on harvest months
// more than on anything else, so those are the best-supported window.

import 'coffee_countries.dart';

class CoffeeCountryProfile {
  const CoffeeCountryProfile(
    this.code, {
    this.altitude,
    this.harvest,
    this.process = const [],
    this.varieties = const [],
    this.productionTonnes,
    this.typicalCup = const [],
    required this.fact,
    required this.sources,
  });

  /// ISO code, a key of [CoffeeCountries.byCode].
  final String code;

  /// Growing altitude as the sources state it, e.g. "1,400–2,000+ m".
  final String? altitude;

  /// Main harvest months, e.g. "Aug–Jan · fly crop Apr–Jul".
  final String? harvest;
  final List<String> process;

  /// Ids from [CoffeeVarieties] — tapping one opens the variety tree.
  final List<String> varieties;
  final int? productionTonnes;

  /// Up to four words a source uses for the cup; empty when none does.
  final List<String> typicalCup;

  /// One sourced sentence worth knowing.
  final String fact;

  /// Where the values come from.
  final List<String> sources;

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
      varieties: ['ethiopian-landrace', 'gesha'],
      productionTonnes: 559400,
      typicalCup: ['floral', 'citrus', 'berries'],
      fact: 'Arabica\'s birthplace: coffee still grows wild in the forests, and about half the harvest is drunk at home.',
      sources: [
        'https://www.cafeimports.com/north-america/ethiopia',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Ethiopia',
      ],
    ),
    CoffeeCountryProfile(
      'KE',
      altitude: '1,400–2,000+ m',
      harvest: 'Aug–Jan · fly crop Apr–Jul',
      process: ['washed'],
      varieties: ['sl28', 'sl34', 'ruiru-11', 'batian'],
      productionTonnes: 48700,
      typicalCup: ['blackcurrant', 'juicy', 'bright'],
      fact: 'Beans are sorted by size (AA, AB) and sold at a weekly auction in Nairobi.',
      sources: [
        'https://www.cafeimports.com/north-america/kenya',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Kenya',
      ],
    ),
    CoffeeCountryProfile(
      'RW',
      altitude: '1,200–2,200 m',
      harvest: 'Mar–Jul',
      process: ['washed', 'natural', 'honey'],
      varieties: ['bourbon', 'caturra', 'catuai', 'mibirizi'],
      productionTonnes: 27104,
      fact: 'From 2001 to 2006 USAID funded washing stations and farmer training across the country.',
      sources: [
        'https://www.cafeimports.com/north-america/rwanda',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Rwanda',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-10/Rwanda%20Map_Updated.pdf',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'BI',
      altitude: '1,250–1,800 m',
      harvest: 'Mar–Jul',
      process: ['washed', 'natural'],
      varieties: ['bourbon', 'jackson', 'mibirizi'],
      typicalCup: ['fig jam', 'floral', 'citrus'],
      fact: 'Farmers own less than a hectare on average and bring their cherries to shared washing stations.',
      sources: [
        'https://www.cafeimports.com/north-america/burundi',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2022-10/English_Burundi_0.pdf',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'UG',
      altitude: '1,300–2,300 m (arabica)',
      harvest: 'Aug–Feb (arabica)',
      process: ['natural', 'washed'],
      varieties: ['sl14', 'sl28', 'nyasaland', 'kp423'],
      productionTonnes: 384000,
      fact: 'Coffee is Uganda\'s top-earning export crop – most of it robusta.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Uganda',
        'https://pmc.ncbi.nlm.nih.gov/articles/PMC4978507',
        'https://royalcoffee.com/uganda-green-coffee-export-review/',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'TZ',
      altitude: '1,000–2,500 m',
      harvest: 'North Jul–Nov · south May–Sep',
      process: ['washed'],
      varieties: ['bourbon', 'kent', 'typica'],
      productionTonnes: 62917,
      fact: 'Known for peaberries – single round beans sorted out and sold on their own.',
      sources: [
        'https://www.cafeimports.com/north-america/tanzania',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-04/Tanzania_CoffeeGrowingMap_ENG.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'CD',
      altitude: '1,400–2,000 m (Kivu)',
      harvest: 'Mar–Jul · fly crop Sep–Jan',
      process: ['washed'],
      varieties: ['bourbon'],
      productionTonnes: 62217,
      fact: 'Kivu arabica grows on volcanic soils around Lake Kivu, often above 1,500 m.',
      sources: [
        'https://www.cafeimports.com/north-america/dr-congo',
        'https://globalpressjournal.com/africa/democratic-republic-of-congo/drcs-dominant-coffee-industry-struggles-survive/',
      ],
    ),
    CoffeeCountryProfile(
      'MW',
      altitude: '1,500–2,000 m',
      harvest: 'Apr–Sep',
      process: ['washed'],
      varieties: ['bourbon', 'caturra', 'gesha', 'sl28'],
      productionTonnes: 11000,
      fact: 'Coffee arrived in the 1890s, when the country was the British colony of Nyasaland.',
      sources: [
        'https://www.cafeimports.com/north-america/malawi',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-05/English_Malawi%20%283%29.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'ZM',
      altitude: '1,300–1,600 m',
      harvest: 'May–Sep',
      process: ['washed'],
      varieties: ['sl28', 'sl34'],
      fact: 'Most of its coffee comes from large estates in Northern Province, around Kasama.',
      sources: [
        'https://perfectdailygrind.com/2021/10/exploring-zambia-as-a-coffee-origin/',
        'https://algrano.com/origins/zambia',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'ZW',
      altitude: '800–1,200 m',
      harvest: 'May–Sep',
      process: ['washed'],
      varieties: ['sl28'],
      fact: 'Only a handful of estates around Chipinge survived the land invasions of the 2000s.',
      sources: [
        'https://perfectdailygrind.com/2021/04/remodelling-to-make-a-real-difference-a-guide-to-coffee-production-in-zimbabwe/',
        'https://perfectdailygrind.com/2018/03/could-zimbabwean-coffee-once-again-be-on-specialty-menus/',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'MG',
      harvest: 'May–Oct',
      process: ['natural'],
      productionTonnes: 49344,
      fact: 'Mostly robusta – and home to wild coffee species: Kew named seven new ones here in 2008–09.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Madagascar',
        'https://en.wikipedia.org/wiki/Coffea',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'CM',
      altitude: 'above 1,000 m (arabica)',
      harvest: 'Sep–Feb (arabica) · Nov–Feb (robusta)',
      process: ['washed', 'natural'],
      varieties: ['java'],
      fact: 'The Java variety was selected here and released in the 1980s; it later reached Central America.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Cameroon',
        'https://varieties.worldcoffeeresearch.org/varieties/java',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'CF',
      harvest: 'Nov–Feb',
      process: ['natural'],
      productionTonnes: 316108,
      fact: 'Robusta, dried in the cherry – coffee is one of its main export crops.',
      sources: [
        'https://www.fao.org/4/x6939e/X6939e10.htm',
        'https://en.wikipedia.org/wiki/Economy_of_the_Central_African_Republic',
      ],
    ),
    CoffeeCountryProfile(
      'CI',
      harvest: 'Oct–Mar',
      process: ['natural'],
      productionTonnes: 91327,
      fact: 'In the 1970s the world\'s third-largest coffee producer, after Brazil and Colombia – mostly robusta.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Ivory_Coast',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    CoffeeCountryProfile(
      'GN',
      harvest: 'Dec–Mar',
      process: ['natural'],
      productionTonnes: 200000,
      fact: 'Robusta from the Mount Ziama forest, \'Ziama-Macenta\', was one of sub-Saharan Africa\'s first protected origins.',
      sources: [
        'https://www.fao.org/4/x6939e/X6939e10.htm',
        'https://www.origin-gi.com/web_articles/27-03-2015-origin-contributes-to-the-crowdfunding-for-the-gi-ziama-macenta/',
      ],
    ),
    CoffeeCountryProfile(
      'TG',
      harvest: 'Dec–Feb',
      process: ['natural'],
      productionTonnes: 22895,
      fact: 'Mostly robusta – and the country plans to double its coffee output by 2030.',
      sources: [
        'https://www.fao.org/4/x6939e/X6939e10.htm',
        'https://stir-tea-coffee.com/tea-coffee-news/togo-plans-to-double-coffee-output-by-2030/',
      ],
    ),
    CoffeeCountryProfile(
      'AO',
      harvest: 'Jun–Oct',
      process: ['natural'],
      productionTonnes: 20071,
      fact: 'In the early 1970s the world\'s third-largest producer – then civil war devastated the plantations.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Angola',
        'https://www.fao.org/4/x6939e/X6939e10.htm',
      ],
    ),
    // --- Americas ----------------------------------------------------------
    CoffeeCountryProfile(
      'BR',
      altitude: '800–1,300 m',
      harvest: 'Apr–Sep',
      process: ['natural', 'pulped natural', 'washed'],
      varieties: ['bourbon', 'yellow-bourbon', 'catuai', 'caturra'],
      productionTonnes: 3405267,
      typicalCup: ['chocolate', 'nutty'],
      fact: 'About a third of the world\'s coffee – large farms pick with machines that shake the trees.',
      sources: [
        'https://www.cafeimports.com/north-america/brazil',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Brazil',
        'https://www.coffeereview.com/coffee-reference/coffee-categories/geographic-origins/coffees-from-the-americas/brazil/',
      ],
    ),
    CoffeeCountryProfile(
      'CO',
      altitude: '800–2,200 m',
      harvest: 'Apr–Aug · Oct–Dec',
      process: ['washed'],
      varieties: ['caturra', 'castillo', 'colombia', 'typica'],
      productionTonnes: 680858,
      typicalCup: ['mild', 'balanced'],
      fact: 'Many regions have two harvests a year: a main crop and a smaller one.',
      sources: [
        'https://www.cafeimports.com/north-america/colombia',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Colombia',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-10/Colombia%20Map%20FINAL.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'PE',
      altitude: '1,000–1,800 m',
      harvest: 'Jun–Sep',
      process: ['washed'],
      varieties: ['typica', 'caturra', 'bourbon'],
      productionTonnes: 369551,
      typicalCup: ['mild'],
      fact: 'About 90,000 hectares of its coffee are grown organically.',
      sources: [
        'https://www.cafeimports.com/north-america/peru',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Peru',
      ],
    ),
    CoffeeCountryProfile(
      'EC',
      altitude: '1,500–2,100 m',
      harvest: 'Year-round',
      process: ['washed', 'natural'],
      varieties: ['typica', 'sidra', 'caturra', 'bourbon'],
      typicalCup: ['floral', 'fruity'],
      fact: 'Sidra became known here – and coffee even grows on the Galápagos.',
      sources: [
        'https://www.cafeimports.com/north-america/ecuador',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Ecuador',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2024-01/Ecuador%20Map%20FINAL%20%282%29.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'BO',
      altitude: '800–2,300 m',
      harvest: 'Jun–Oct',
      process: ['washed', 'natural'],
      varieties: ['typica', 'catuai'],
      productionTonnes: 23579,
      fact: 'Caranavi, in the department of La Paz, is its most productive coffee region.',
      sources: [
        'https://www.cafeimports.com/north-america/bolivia',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Bolivia',
      ],
    ),
    CoffeeCountryProfile(
      'VE',
      altitude: '800–1,700 m',
      harvest: 'Sep–Jan',
      process: ['washed', 'honey', 'natural'],
      productionTonnes: 56381,
      typicalCup: ['bright', 'clean'],
      fact: 'Coffee and cacao were the main exports – until oil took over.',
      sources: [
        'https://www.cafeimports.com/north-america/venezuela',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Venezuela',
      ],
    ),
    CoffeeCountryProfile(
      'PA',
      altitude: '1,000–1,650 m',
      harvest: 'Nov–Mar',
      process: ['washed', 'natural'],
      varieties: ['gesha', 'caturra', 'catuai', 'mundo-novo'],
      productionTonnes: 12760,
      typicalCup: ['floral', 'tea-like', 'delicate'],
      fact: 'In 2025 a Panama Gesha set a Best of Panama auction record of US\$13,700 per pound.',
      sources: [
        'https://www.cafeimports.com/north-america/panama',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Panama',
        'https://en.wikipedia.org/wiki/Geisha_coffee',
      ],
    ),
    CoffeeCountryProfile(
      'CR',
      altitude: '1,200–1,700 m',
      harvest: 'Dec–Apr',
      process: ['washed', 'natural', 'honey'],
      varieties: ['caturra', 'catuai', 'villa-sarchi', 'bourbon'],
      productionTonnes: 78822,
      typicalCup: ['crisp acidity', 'smooth'],
      fact: 'Honey processing – halfway between washed and pulped natural – originated here.',
      sources: [
        'https://www.cafeimports.com/north-america/costa-rica',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Costa_Rica',
      ],
    ),
    CoffeeCountryProfile(
      'NI',
      altitude: '1,000–1,700 m',
      harvest: 'Oct–Mar',
      process: ['washed'],
      varieties: ['bourbon', 'caturra', 'catuai', 'maragogipe'],
      productionTonnes: 143337,
      fact:
          'Historically, its best coffee has come from Matagalpa and Jinotega.',
      sources: [
        'https://www.cafeimports.com/north-america/nicaragua',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Nicaragua',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-10/Nicaragua%20Map%20FINAL.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'HN',
      altitude: '800–1,800 m',
      harvest: 'Nov–Apr',
      process: ['washed'],
      varieties: ['ihcafe-90', 'lempira', 'catuai', 'caturra'],
      productionTonnes: 384361,
      typicalCup: ['nutty', 'sweet', 'full body'],
      fact: 'Since 2011 Central America\'s largest coffee producer.',
      sources: [
        'https://www.cafeimports.com/north-america/honduras',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Honduras',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-10/Honduras%20Map%20FINAL.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'SV',
      altitude: '500–1,200+ m',
      harvest: 'Nov–Apr',
      process: ['washed', 'natural', 'honey'],
      varieties: ['bourbon', 'pacas', 'pacamara', 'typica'],
      productionTonnes: 32326,
      fact: 'Pacas (a Bourbon mutation) and Pacamara (Pacas × Maragogipe) were both born here.',
      sources: [
        'https://www.cafeimports.com/north-america/el-salvador',
        'https://en.wikipedia.org/wiki/Coffee_production_in_El_Salvador',
      ],
    ),
    CoffeeCountryProfile(
      'GT',
      altitude: '1,300–2,000 m',
      harvest: 'Sep–Apr',
      process: ['washed'],
      varieties: ['bourbon', 'caturra', 'catuai', 'typica'],
      productionTonnes: 225327,
      typicalCup: ['chocolate', 'nutty', 'citrus'],
      fact: 'Anacafé defines eight coffee regions, among them Antigua, Atitlán and Huehuetenango.',
      sources: [
        'https://www.cafeimports.com/north-america/guatemala',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Guatemala',
      ],
    ),
    CoffeeCountryProfile(
      'MX',
      altitude: '600–1,800 m',
      harvest: 'Nov–Mar',
      process: ['washed'],
      varieties: ['typica', 'bourbon', 'caturra', 'marsellesa'],
      productionTonnes: 194916,
      typicalCup: ['chocolate', 'nutty', 'mild'],
      fact: 'Organic and Fair Trade coffee is abundant, especially in Oaxaca, Veracruz and Chiapas.',
      sources: [
        'https://www.cafeimports.com/north-america/mexico',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Mexico',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2022-09/Spring%202022%20Coffee%20Growing%20Maps%20Mexico-Eng.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'JM',
      altitude: 'up to 1,600 m',
      harvest: 'Aug–May',
      process: ['washed'],
      varieties: ['typica', 'bourbon'],
      typicalCup: ['mild', 'sweet'],
      fact: 'Some Blue Mountain coffee is still shipped in wooden barrels instead of sacks.',
      sources: [
        'https://www.cafeimports.com/north-america/jamaica',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Jamaica',
        'https://en.wikipedia.org/wiki/Jamaican_Blue_Mountain_Coffee',
        'https://rocksteadycoffee.com/pages/harvest',
      ],
    ),
    CoffeeCountryProfile(
      'HT',
      altitude: '1,200–1,600 m (specialty)',
      harvest: 'Sep–Jun',
      process: ['natural', 'washed'],
      varieties: ['typica'],
      fact: 'By 1788 it supplied about half of the world\'s coffee.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Haiti',
        'https://perfectdailygrind.com/2022/05/coffee-production-in-haiti/',
      ],
    ),
    CoffeeCountryProfile(
      'DO',
      altitude: '1,000–1,600 m',
      harvest: 'Oct–Jun',
      process: ['washed'],
      varieties: ['typica', 'caturra'],
      productionTonnes: 23446,
      fact: 'Its main coffee areas include the Neyba and Bahoruco mountain ranges.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_the_Dominican_Republic',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2023-08/DominicanRepublic_EN_Updated.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'CU',
      altitude: '400–800 m',
      harvest: 'Sep–Jan',
      process: ['washed'],
      fact: 'Coffee arrived in 1748; today most of it grows in the Sierra Maestra.',
      sources: ['https://en.wikipedia.org/wiki/Coffee_production_in_Cuba'],
    ),
    CoffeeCountryProfile(
      'PR',
      altitude: '730–850 m',
      harvest: 'Sep–Feb',
      process: ['washed'],
      varieties: ['bourbon', 'typica', 'pacas'],
      typicalCup: ['smooth', 'sweet'],
      fact: 'In the late 19th century the world\'s seventh-largest coffee producer.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Puerto_Rico',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2022-09/Maps_Puerto%20Rico.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'US',
      altitude: '150–975 m',
      harvest: 'Aug–Dec',
      process: ['washed'],
      varieties: ['typica', 'bourbon'],
      typicalCup: ['mild', 'clean', 'sweet'],
      fact: 'Hawaii is the only US state that grows coffee commercially.',
      sources: [
        'https://www.cafeimports.com/north-america/hawaii',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Hawaii',
        'https://en.wikipedia.org/wiki/Kona_coffee',
      ],
    ),
    // --- Asia & Pacific ----------------------------------------------------
    CoffeeCountryProfile(
      'YE',
      harvest: 'Oct–Mar',
      process: ['natural'],
      productionTonnes: 30291,
      typicalCup: ['winey', 'chocolate'],
      fact: 'The port of Mokha gave its name to mocha coffee – though no coffee grew in the town itself.',
      sources: [
        'https://www.cafeimports.com/north-america/yemen',
        'https://en.wikipedia.org/wiki/Mokha',
      ],
    ),
    CoffeeCountryProfile(
      'IN',
      altitude: '1,000–1,500 m',
      harvest: 'Nov–Jan',
      process: ['washed', 'natural', 'monsooned'],
      varieties: ['kent', 's795'],
      productionTonnes: 332848,
      typicalCup: ['spice', 'nutty', 'full body'],
      fact: '"Monsooned Malabar" beans are left in monsoon winds for weeks until they turn pale and mellow.',
      sources: [
        'https://www.cafeimports.com/north-america/india',
        'https://en.wikipedia.org/wiki/Coffee_production_in_India',
        'https://en.wikipedia.org/wiki/Monsooned_Malabar',
      ],
    ),
    CoffeeCountryProfile(
      'LK',
      altitude: 'above 800 m (arabica)',
      harvest: 'Oct–Feb',
      fact: 'Coffee peaked here in 1870; leaf rust then ruined the estates and the island switched to tea.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Sri_Lanka',
        'https://en.wikipedia.org/wiki/Hemileia_vastatrix',
        'https://www.srilankabusiness.com/blog/coffee-from-sri-lanka.html',
      ],
    ),
    CoffeeCountryProfile(
      'NP',
      altitude: '800–1,600 m',
      harvest: 'Dec–Mar',
      varieties: ['bourbon', 'typica', 'caturra', 'pacamara'],
      fact: 'Much of its coffee is organic by default – chemical fertilisers are hard to get in the hills.',
      sources: [
        'https://perfectdailygrind.com/2025/06/how-nepal-is-emerging-as-specialty-coffee-origin/',
        'https://kathmandupost.com/29/2019/12/22/coffee-sector-performing-below-potential-due-to-archaic-ways',
      ],
    ),
    CoffeeCountryProfile(
      'MM',
      altitude: '1,000–1,500 m',
      harvest: 'Nov–Mar',
      varieties: ['catuai', 'sl34', 'caturra'],
      fact: 'Coffee came to Shan State in the 1980s as a replacement crop for opium poppy.',
      sources: [
        'https://www.algrano.com/origins/myanmar',
        'https://www.unodc.org/unodc/en/frontpage/2018/October/from-opium-to-coffee_-green-gold-cooperative-exports-its-first-container-of-coffee-to-the-european-market.html',
      ],
    ),
    CoffeeCountryProfile(
      'CN',
      altitude: '800–1,800 m',
      harvest: 'Dec–Mar',
      productionTonnes: 108000,
      fact: 'Yunnan grows almost all of China\'s coffee – a French missionary brought it there in the late 19th century.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_China',
        'https://sucafina.com/na/origins/china',
      ],
    ),
    CoffeeCountryProfile(
      'TH',
      altitude: '800–1,200 m',
      harvest: 'Nov–Mar',
      productionTonnes: 16575,
      fact: 'In the 1970s King Bhumibol promoted coffee in the north as an alternative to opium.',
      sources: ['https://en.wikipedia.org/wiki/Coffee_production_in_Thailand'],
    ),
    CoffeeCountryProfile(
      'LA',
      altitude: '800–1,350 m',
      harvest: 'Nov–Mar',
      productionTonnes: 177662,
      typicalCup: ['mild', 'citrus', 'floral'],
      fact: 'French colonists brought coffee around 1915; the volcanic Bolaven Plateau became its heart.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Laos',
        'https://rove.me/to/laos/coffee-harvest',
      ],
    ),
    CoffeeCountryProfile(
      'VN',
      altitude: '1,000–1,400 m (arabica)',
      harvest: 'Oct–Jan',
      productionTonnes: 1956782,
      fact: 'The world\'s second-largest producer – mostly robusta – and home of egg coffee.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Vietnam',
        'https://en.wikipedia.org/wiki/Egg_coffee',
        'https://sucafina.com/na/origins/vietnam',
        'https://live-sgacms.ws.asu.edu/sites/default/files/2022-09/Vietnam_ENG_1.pdf',
      ],
    ),
    CoffeeCountryProfile(
      'KH',
      productionTonnes: 24266,
      fact: 'Mondulkiri, its main coffee province, grows mostly robusta – rated \'Fine Robusta\'.',
      sources: [
        'https://www.thestar.com.my/aseanplus/aseanplus-news/2024/08/18/mondulkiri-coffee-farmers-urged-to-expand-after-fine-robusta-recognition',
      ],
    ),
    CoffeeCountryProfile(
      'TW',
      altitude: '1,000–1,400 m',
      process: ['natural', 'honey', 'washed'],
      varieties: ['gesha', 'sl34', 'typica'],
      fact: 'Small output (856 t in 2023), but Alishan lots have fetched over US\$500 per pound at auction.',
      sources: [
        'https://en.wikipedia.org/wiki/Agriculture_in_Taiwan',
        'https://auction.allianceforcoffeeexcellence.org/en/lots/zhuo-wu-mountain-coffee-farm',
      ],
    ),
    CoffeeCountryProfile(
      'PH',
      altitude: '1,000–1,800 m (Luzon)',
      harvest: 'Oct–Mar',
      productionTonnes: 30023,
      fact: 'One of the few countries growing all four commercial coffees, liberica included – "Kapeng Barako".',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_the_Philippines',
        'https://en.wikipedia.org/wiki/Kapeng_barako',
        'https://philcoffeeboard.com/philippine-coffee/',
      ],
    ),
    CoffeeCountryProfile(
      'ID',
      altitude: '1,100–1,800 m',
      harvest: 'Varies by island',
      process: ['wet-hulled', 'washed'],
      varieties: ['typica', 'timor-hybrid', 's795'],
      productionTonnes: 760192,
      typicalCup: ['earthy', 'herbal', 'full body'],
      fact: 'Wet-hulling ("giling basah") is thought to lower acidity and add body – the classic Sumatran cup.',
      sources: [
        'https://en.wikipedia.org/wiki/Coffee_production_in_Indonesia',
        'https://en.wikipedia.org/wiki/Giling_basah',
      ],
    ),
    CoffeeCountryProfile(
      'TL',
      altitude: '800–1,900 m',
      harvest: 'May–Sep',
      process: ['washed'],
      varieties: ['timor-hybrid', 'typica'],
      fact: 'The Timor Hybrid – a natural arabica × robusta cross – was found here in the 1920s.',
      sources: [
        'https://live-sgacms.ws.asu.edu/sites/default/files/2022-12/English_East_Timor.pdf',
        'https://www.fondazioneslowfood.com/en/?p=81534',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Indonesia',
      ],
    ),
    CoffeeCountryProfile(
      'PG',
      harvest: 'May–Sep · fly crop Jan–Feb',
      process: ['washed'],
      varieties: ['typica'],
      productionTonnes: 45371,
      typicalCup: ['fruity'],
      fact: 'Its Typica came from Jamaica Blue Mountain seed in the 1920s.',
      sources: [
        'https://www.cafeimports.com/north-america/papua-new-guinea',
        'https://en.wikipedia.org/wiki/Coffee_production_in_Papua_New_Guinea',
      ],
    ),
    CoffeeCountryProfile(
      'AU',
      varieties: ['k7', 'marsellesa'],
      fact: 'Machine harvesting began in 1983 near Mareeba – one harvester can pick up to 10,000 trees a day.',
      sources: [
        'https://webarchive.library.unt.edu/eot2008/20090116180159/http://www.rirdc.gov.au/reports/NPP/03-056.pdf',
        'https://www.beanscenemag.com.au/is-this-the-future-of-australian-grown-coffee/',
      ],
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

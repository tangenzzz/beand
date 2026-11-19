// Coffee-growing regions per country — the names that end up on bags
// ("Huila", "Yirgacheffe", "Gayo"), for the origin statistics.
//
// Where a country defines its regions officially, the list follows that
// (Guatemala: Anacafé's eight regions, Costa Rica: ICAFE's eight, Honduras:
// IHCAFE's six, El Salvador: the six regions of the coffee council,
// Colombia: the coffee departments, Ethiopia: the usual trade names);
// elsewhere it holds the regions roasters commonly name. Positions are the
// rough middle of each region — good enough for a dot on a small map.

import 'coffee_countries.dart';

class CoffeeGrowingRegion {
  const CoffeeGrowingRegion(
    this.id,
    this.name,
    this.country,
    this.lon,
    this.lat, {
    this.aliases = const [],
  });

  final String id;
  final String name;

  /// ISO code of the country, a key of [CoffeeCountries.byCode].
  final String country;
  final double lon;
  final double lat;

  /// Other spellings, towns and sub-areas that point to this region.
  final List<String> aliases;
}

class CoffeeRegions {
  CoffeeRegions._();

  static const List<CoffeeGrowingRegion> all = [
    // --- Ethiopia (trade names) -------------------------------------------
    CoffeeGrowingRegion(
      'et-yirgacheffe',
      'Yirgacheffe',
      'ET',
      38.2,
      6.16,
      aliases: ['Yirgachefe', 'Yirga Cheffe', 'Gedeo', 'Kochere', 'Gedeb'],
    ),
    CoffeeGrowingRegion(
      'et-sidama',
      'Sidama',
      'ET',
      38.5,
      6.7,
      aliases: ['Sidamo', 'Bensa', 'Aroresa'],
    ),
    CoffeeGrowingRegion(
      'et-guji',
      'Guji',
      'ET',
      38.9,
      5.6,
      aliases: ['Hambela', 'Uraga', 'Shakiso', 'Odo Shakiso'],
    ),
    CoffeeGrowingRegion(
      'et-harrar',
      'Harrar',
      'ET',
      42.1,
      9.3,
      aliases: ['Harar', 'Harrar Longberry'],
    ),
    CoffeeGrowingRegion('et-limu', 'Limu', 'ET', 36.9, 8.1),
    CoffeeGrowingRegion(
      'et-jimma',
      'Jimma',
      'ET',
      36.8,
      7.7,
      aliases: ['Djimmah', 'Agaro', 'Gera'],
    ),
    CoffeeGrowingRegion(
      'et-lekempti',
      'Lekempti',
      'ET',
      36.5,
      9.1,
      aliases: ['Nekemte', 'Wellega', 'Wollega', 'Welega', 'Gimbi'],
    ),
    CoffeeGrowingRegion(
      'et-kaffa',
      'Kaffa',
      'ET',
      36.2,
      7.3,
      aliases: ['Kafa'],
    ),
    CoffeeGrowingRegion(
      'et-bench-maji',
      'Bench Maji',
      'ET',
      35.6,
      6.9,
      aliases: ['Bench Sheko'],
    ),
    CoffeeGrowingRegion(
      'et-west-arsi',
      'West Arsi',
      'ET',
      38.7,
      7.2,
      aliases: ['Nensebo'],
    ),

    // --- Kenya (counties) -------------------------------------------------
    CoffeeGrowingRegion(
      'ke-nyeri',
      'Nyeri',
      'KE',
      36.95,
      -0.42,
      aliases: ['Othaya', 'Mathira'],
    ),
    CoffeeGrowingRegion('ke-kirinyaga', 'Kirinyaga', 'KE', 37.3, -0.5),
    CoffeeGrowingRegion(
      'ke-kiambu',
      'Kiambu',
      'KE',
      36.8,
      -1.0,
      aliases: ['Ruiru', 'Thika'],
    ),
    CoffeeGrowingRegion(
      'ke-muranga',
      "Murang'a",
      'KE',
      37.0,
      -0.8,
      aliases: ['Muranga'],
    ),
    CoffeeGrowingRegion('ke-embu', 'Embu', 'KE', 37.45, -0.53),
    CoffeeGrowingRegion('ke-meru', 'Meru', 'KE', 37.65, 0.05),
    CoffeeGrowingRegion('ke-machakos', 'Machakos', 'KE', 37.3, -1.5),
    CoffeeGrowingRegion(
      'ke-elgon',
      'Mount Elgon (Kenya)',
      'KE',
      34.6,
      0.7,
      aliases: ['Bungoma'],
    ),
    CoffeeGrowingRegion('ke-kisii', 'Kisii', 'KE', 34.8, -0.7),

    // --- Rwanda (districts) -----------------------------------------------
    CoffeeGrowingRegion('rw-nyamasheke', 'Nyamasheke', 'RW', 29.1, -2.33),
    CoffeeGrowingRegion(
      'rw-huye',
      'Huye',
      'RW',
      29.75,
      -2.6,
      aliases: ['Butare'],
    ),
    CoffeeGrowingRegion('rw-rutsiro', 'Rutsiro', 'RW', 29.3, -1.95),
    CoffeeGrowingRegion(
      'rw-karongi',
      'Karongi',
      'RW',
      29.4,
      -2.07,
      aliases: ['Kibuye'],
    ),
    CoffeeGrowingRegion('rw-rusizi', 'Rusizi', 'RW', 28.95, -2.5),
    CoffeeGrowingRegion('rw-nyaruguru', 'Nyaruguru', 'RW', 29.5, -2.7),
    CoffeeGrowingRegion('rw-gakenke', 'Gakenke', 'RW', 29.8, -1.7),
    CoffeeGrowingRegion('rw-rulindo', 'Rulindo', 'RW', 29.95, -1.75),

    // --- Burundi (provinces) ----------------------------------------------
    CoffeeGrowingRegion('bi-kayanza', 'Kayanza', 'BI', 29.63, -2.92),
    CoffeeGrowingRegion('bi-ngozi', 'Ngozi', 'BI', 29.83, -2.9),
    CoffeeGrowingRegion('bi-kirundo', 'Kirundo', 'BI', 30.1, -2.58),
    CoffeeGrowingRegion('bi-muramvya', 'Muramvya', 'BI', 29.6, -3.27),
    CoffeeGrowingRegion('bi-gitega', 'Gitega', 'BI', 29.93, -3.43),

    // --- Uganda, Tanzania, DR Congo, Malawi, Zimbabwe ----------------------
    CoffeeGrowingRegion(
      'ug-elgon',
      'Mount Elgon',
      'UG',
      34.4,
      1.1,
      aliases: ['Bugisu', 'Mbale', 'Sipi', 'Mt. Elgon'],
    ),
    CoffeeGrowingRegion(
      'ug-rwenzori',
      'Rwenzori',
      'UG',
      30.0,
      0.4,
      aliases: ['Ruwenzori'],
    ),
    CoffeeGrowingRegion(
      'tz-kilimanjaro',
      'Kilimanjaro',
      'TZ',
      37.3,
      -3.2,
      aliases: ['Moshi'],
    ),
    CoffeeGrowingRegion(
      'tz-arusha',
      'Arusha',
      'TZ',
      36.7,
      -3.37,
      aliases: ['Karatu', 'Ngorongoro'],
    ),
    CoffeeGrowingRegion(
      'tz-mbeya',
      'Mbeya',
      'TZ',
      33.45,
      -8.9,
      aliases: ['Mbozi', 'Songwe'],
    ),
    CoffeeGrowingRegion(
      'tz-ruvuma',
      'Ruvuma',
      'TZ',
      35.0,
      -10.9,
      aliases: ['Mbinga'],
    ),
    CoffeeGrowingRegion(
      'cd-south-kivu',
      'South Kivu',
      'CD',
      28.86,
      -2.5,
      aliases: ['Sud-Kivu', 'Lake Kivu', 'Idjwi'],
    ),
    CoffeeGrowingRegion(
      'cd-north-kivu',
      'North Kivu',
      'CD',
      29.2,
      -0.7,
      aliases: ['Nord-Kivu', 'Beni', 'Butembo'],
    ),
    CoffeeGrowingRegion(
      'mw-misuku',
      'Misuku Hills',
      'MW',
      33.5,
      -9.7,
      aliases: ['Misuku', 'Chitipa'],
    ),
    CoffeeGrowingRegion(
      'mw-viphya',
      'Viphya',
      'MW',
      33.9,
      -11.6,
      aliases: ['Mzuzu'],
    ),
    CoffeeGrowingRegion(
      'zw-chimanimani',
      'Chimanimani',
      'ZW',
      32.9,
      -19.8,
      aliases: ['Eastern Highlands (Zimbabwe)'],
    ),

    // --- Yemen ------------------------------------------------------------
    CoffeeGrowingRegion(
      'ye-haraz',
      'Haraz',
      'YE',
      43.6,
      15.2,
      aliases: ['Haraaz'],
    ),
    CoffeeGrowingRegion(
      'ye-bani-matar',
      'Bani Matar',
      'YE',
      44.0,
      15.3,
      aliases: ['Bani Mattar'],
    ),
    CoffeeGrowingRegion(
      'ye-yafa',
      'Yafa',
      'YE',
      45.3,
      13.8,
      aliases: ["Yafa'i", 'Yafai'],
    ),

    // --- Colombia (coffee departments) ------------------------------------
    CoffeeGrowingRegion(
      'co-huila',
      'Huila',
      'CO',
      -75.7,
      2.5,
      aliases: [
        'Pitalito',
        'San Agustín',
        'San Agustin',
        'Acevedo',
        'La Plata',
        'Gigante',
      ],
    ),
    CoffeeGrowingRegion(
      'co-narino',
      'Nariño',
      'CO',
      -77.3,
      1.2,
      aliases: ['Narino', 'La Unión', 'La Union', 'Buesaco', 'San Lorenzo'],
    ),
    CoffeeGrowingRegion(
      'co-cauca',
      'Cauca',
      'CO',
      -76.6,
      2.4,
      aliases: ['Popayán', 'Popayan', 'Inzá', 'Inza', 'Piendamó', 'Piendamo'],
    ),
    CoffeeGrowingRegion(
      'co-tolima',
      'Tolima',
      'CO',
      -75.2,
      4.0,
      aliases: ['Planadas', 'Ataco', 'Chaparral'],
    ),
    CoffeeGrowingRegion(
      'co-antioquia',
      'Antioquia',
      'CO',
      -75.6,
      6.2,
      aliases: ['Medellín', 'Medellin', 'Urrao', 'Jardín', 'Jardin'],
    ),
    CoffeeGrowingRegion(
      'co-caldas',
      'Caldas',
      'CO',
      -75.5,
      5.1,
      aliases: ['Manizales'],
    ),
    CoffeeGrowingRegion(
      'co-risaralda',
      'Risaralda',
      'CO',
      -75.8,
      5.0,
      aliases: ['Pereira'],
    ),
    CoffeeGrowingRegion(
      'co-quindio',
      'Quindío',
      'CO',
      -75.7,
      4.5,
      aliases: ['Quindio', 'Armenia'],
    ),
    CoffeeGrowingRegion(
      'co-valle',
      'Valle del Cauca',
      'CO',
      -76.3,
      4.0,
      aliases: ['Valle', 'Trujillo'],
    ),
    CoffeeGrowingRegion(
      'co-santander',
      'Santander',
      'CO',
      -73.3,
      6.6,
      aliases: ['San Gil'],
    ),
    CoffeeGrowingRegion(
      'co-norte-santander',
      'Norte de Santander',
      'CO',
      -72.8,
      7.9,
      aliases: ['Cúcuta', 'Cucuta'],
    ),
    CoffeeGrowingRegion('co-cundinamarca', 'Cundinamarca', 'CO', -74.2, 4.7),
    CoffeeGrowingRegion(
      'co-boyaca',
      'Boyacá',
      'CO',
      -73.3,
      5.5,
      aliases: ['Boyaca'],
    ),
    CoffeeGrowingRegion(
      'co-santa-marta',
      'Sierra Nevada de Santa Marta',
      'CO',
      -73.9,
      10.9,
      aliases: ['Sierra Nevada', 'Santa Marta', 'Magdalena'],
    ),

    // --- Brazil -----------------------------------------------------------
    CoffeeGrowingRegion(
      'br-sul-de-minas',
      'Sul de Minas',
      'BR',
      -45.4,
      -21.6,
      aliases: ['South Minas', 'Southern Minas'],
    ),
    CoffeeGrowingRegion(
      'br-mantiqueira',
      'Mantiqueira de Minas',
      'BR',
      -45.4,
      -22.3,
      aliases: ['Mantiqueira', 'Carmo de Minas'],
    ),
    CoffeeGrowingRegion(
      'br-cerrado',
      'Cerrado Mineiro',
      'BR',
      -46.9,
      -18.9,
      aliases: ['Cerrado', 'Patrocínio', 'Patrocinio'],
    ),
    CoffeeGrowingRegion(
      'br-mogiana',
      'Mogiana',
      'BR',
      -47.4,
      -21.0,
      aliases: ['Alta Mogiana', 'Franca'],
    ),
    CoffeeGrowingRegion(
      'br-matas-de-minas',
      'Matas de Minas',
      'BR',
      -42.4,
      -20.5,
      aliases: ['Zona da Mata'],
    ),
    CoffeeGrowingRegion(
      'br-chapada-diamantina',
      'Chapada Diamantina',
      'BR',
      -41.5,
      -13.0,
      aliases: ['Bahia', 'Piatã', 'Piata'],
    ),
    CoffeeGrowingRegion(
      'br-espirito-santo',
      'Espírito Santo',
      'BR',
      -41.0,
      -20.0,
      aliases: [
        'Espirito Santo',
        'Montanhas do Espírito Santo',
        'Caparaó',
        'Caparao',
      ],
    ),
    CoffeeGrowingRegion(
      'br-parana',
      'Paraná',
      'BR',
      -51.0,
      -23.5,
      aliases: ['Parana', 'Norte Pioneiro'],
    ),
    CoffeeGrowingRegion(
      'br-rondonia',
      'Rondônia',
      'BR',
      -62.0,
      -11.0,
      aliases: ['Rondonia', 'Matas de Rondônia'],
    ),

    // --- Peru, Ecuador, Bolivia -------------------------------------------
    CoffeeGrowingRegion(
      'pe-cajamarca',
      'Cajamarca',
      'PE',
      -78.5,
      -6.0,
      aliases: ['Jaén', 'Jaen', 'San Ignacio'],
    ),
    CoffeeGrowingRegion(
      'pe-amazonas',
      'Amazonas',
      'PE',
      -77.9,
      -6.2,
      aliases: ['Rodríguez de Mendoza', 'Rodriguez de Mendoza'],
    ),
    CoffeeGrowingRegion(
      'pe-cusco',
      'Cusco',
      'PE',
      -72.7,
      -12.9,
      aliases: ['Cuzco', 'Quillabamba', 'La Convención', 'La Convencion'],
    ),
    CoffeeGrowingRegion(
      'pe-junin',
      'Junín',
      'PE',
      -75.3,
      -11.1,
      aliases: ['Junin', 'Chanchamayo', 'Satipo'],
    ),
    CoffeeGrowingRegion(
      'pe-puno',
      'Puno',
      'PE',
      -69.4,
      -14.1,
      aliases: ['Sandia'],
    ),
    CoffeeGrowingRegion(
      'pe-san-martin',
      'San Martín',
      'PE',
      -76.9,
      -6.5,
      aliases: ['San Martin', 'Moyobamba'],
    ),
    CoffeeGrowingRegion(
      'pe-pasco',
      'Pasco',
      'PE',
      -75.4,
      -10.6,
      aliases: ['Villa Rica', 'Oxapampa'],
    ),
    CoffeeGrowingRegion(
      'ec-loja',
      'Loja',
      'EC',
      -79.3,
      -4.1,
      aliases: ['Vilcabamba'],
    ),
    CoffeeGrowingRegion(
      'ec-zamora',
      'Zamora-Chinchipe',
      'EC',
      -78.9,
      -4.1,
      aliases: ['Zamora', 'Palanda'],
    ),
    CoffeeGrowingRegion(
      'ec-pichincha',
      'Pichincha',
      'EC',
      -78.6,
      0.0,
      aliases: ['Nanegal'],
    ),
    CoffeeGrowingRegion(
      'ec-imbabura',
      'Imbabura',
      'EC',
      -78.4,
      0.35,
      aliases: ['Intag'],
    ),
    CoffeeGrowingRegion(
      'ec-galapagos',
      'Galápagos',
      'EC',
      -90.4,
      -0.7,
      aliases: ['Galapagos', 'San Cristóbal'],
    ),
    CoffeeGrowingRegion('bo-caranavi', 'Caranavi', 'BO', -67.6, -15.8),
    CoffeeGrowingRegion(
      'bo-yungas',
      'Yungas',
      'BO',
      -67.5,
      -16.3,
      aliases: ['Nor Yungas', 'Sud Yungas'],
    ),
    CoffeeGrowingRegion('bo-samaipata', 'Samaipata', 'BO', -63.9, -18.2),

    // --- Panama, Costa Rica (ICAFE) ---------------------------------------
    CoffeeGrowingRegion(
      'pa-boquete',
      'Boquete',
      'PA',
      -82.43,
      8.78,
      aliases: ['Jaramillo'],
    ),
    CoffeeGrowingRegion(
      'pa-volcan',
      'Volcán',
      'PA',
      -82.63,
      8.77,
      aliases: ['Volcan', 'Volcán Barú', 'Volcan Baru', 'Candela'],
    ),
    CoffeeGrowingRegion(
      'pa-renacimiento',
      'Renacimiento',
      'PA',
      -82.85,
      8.75,
      aliases: ['Santa Clara'],
    ),
    CoffeeGrowingRegion(
      'cr-tarrazu',
      'Tarrazú',
      'CR',
      -84.0,
      9.65,
      aliases: ['Tarrazu', 'Los Santos', 'Dota', 'León Cortés', 'Leon Cortes'],
    ),
    CoffeeGrowingRegion(
      'cr-west-valley',
      'West Valley',
      'CR',
      -84.4,
      10.05,
      aliases: ['Valle Occidental', 'Naranjo', 'Grecia', 'Sarchí', 'Sarchi'],
    ),
    CoffeeGrowingRegion(
      'cr-central-valley',
      'Central Valley',
      'CR',
      -84.1,
      9.95,
      aliases: ['Valle Central', 'Heredia', 'Poás', 'Poas'],
    ),
    CoffeeGrowingRegion(
      'cr-tres-rios',
      'Tres Ríos',
      'CR',
      -83.95,
      9.9,
      aliases: ['Tres Rios'],
    ),
    CoffeeGrowingRegion('cr-orosi', 'Orosi', 'CR', -83.85, 9.8),
    CoffeeGrowingRegion('cr-turrialba', 'Turrialba', 'CR', -83.7, 9.9),
    CoffeeGrowingRegion(
      'cr-brunca',
      'Brunca',
      'CR',
      -83.4,
      9.0,
      aliases: [
        'Pérez Zeledón',
        'Perez Zeledon',
        'Coto Brus',
        'Chirripó',
        'Chirripo',
      ],
    ),
    CoffeeGrowingRegion(
      'cr-guanacaste',
      'Guanacaste',
      'CR',
      -85.0,
      10.5,
      aliases: ['Hojancha'],
    ),

    // --- Nicaragua, Honduras (IHCAFE), El Salvador ------------------------
    CoffeeGrowingRegion('ni-jinotega', 'Jinotega', 'NI', -85.95, 13.1),
    CoffeeGrowingRegion('ni-matagalpa', 'Matagalpa', 'NI', -85.9, 12.9),
    CoffeeGrowingRegion(
      'ni-nueva-segovia',
      'Nueva Segovia',
      'NI',
      -86.3,
      13.7,
      aliases: ['Dipilto', 'Mozonte', 'Jalapa'],
    ),
    CoffeeGrowingRegion('ni-madriz', 'Madriz', 'NI', -86.4, 13.5),
    CoffeeGrowingRegion(
      'hn-copan',
      'Copán',
      'HN',
      -88.9,
      14.8,
      aliases: ['Copan', 'Ocotepeque'],
    ),
    CoffeeGrowingRegion(
      'hn-opalaca',
      'Opalaca',
      'HN',
      -88.3,
      14.6,
      aliases: [
        'Santa Bárbara',
        'Santa Barbara',
        'Intibucá',
        'Intibuca',
        'Lempira',
      ],
    ),
    CoffeeGrowingRegion(
      'hn-montecillos',
      'Montecillos',
      'HN',
      -87.9,
      14.3,
      aliases: ['Marcala'],
    ),
    CoffeeGrowingRegion('hn-comayagua', 'Comayagua', 'HN', -87.6, 14.5),
    CoffeeGrowingRegion(
      'hn-agalta',
      'Agalta',
      'HN',
      -86.0,
      15.0,
      aliases: ['Olancho'],
    ),
    CoffeeGrowingRegion(
      'hn-el-paraiso',
      'El Paraíso',
      'HN',
      -86.4,
      13.9,
      aliases: ['El Paraiso'],
    ),
    CoffeeGrowingRegion(
      'sv-apaneca',
      'Apaneca-Ilamatepec',
      'SV',
      -89.8,
      13.85,
      aliases: ['Apaneca', 'Ilamatepec', 'Santa Ana'],
    ),
    CoffeeGrowingRegion(
      'sv-alotepec',
      'Alotepec-Metapán',
      'SV',
      -89.4,
      14.3,
      aliases: ['Alotepec', 'Metapán', 'Metapan'],
    ),
    CoffeeGrowingRegion('sv-chalatenango', 'Chalatenango', 'SV', -89.0, 14.1),
    CoffeeGrowingRegion(
      'sv-balsamo',
      'El Bálsamo-Quetzaltepec',
      'SV',
      -89.4,
      13.6,
      aliases: ['El Bálsamo', 'El Balsamo', 'Quetzaltepec'],
    ),
    CoffeeGrowingRegion(
      'sv-tecapa',
      'Tecapa-Chinameca',
      'SV',
      -88.4,
      13.5,
      aliases: ['Tecapa', 'Chinameca'],
    ),
    CoffeeGrowingRegion('sv-cacahuatique', 'Cacahuatique', 'SV', -88.15, 13.8),

    // --- Guatemala (Anacafé) ----------------------------------------------
    CoffeeGrowingRegion(
      'gt-antigua',
      'Antigua',
      'GT',
      -90.73,
      14.56,
      aliases: ['Antigua Guatemala'],
    ),
    CoffeeGrowingRegion(
      'gt-acatenango',
      'Acatenango',
      'GT',
      -90.95,
      14.5,
      aliases: ['Acatenango Valley', 'Chimaltenango'],
    ),
    CoffeeGrowingRegion(
      'gt-atitlan',
      'Atitlán',
      'GT',
      -91.2,
      14.7,
      aliases: ['Atitlan', 'Lake Atitlán', 'Lake Atitlan'],
    ),
    CoffeeGrowingRegion(
      'gt-huehuetenango',
      'Huehuetenango',
      'GT',
      -91.47,
      15.32,
      aliases: ['Huehue', 'Todos Santos'],
    ),
    CoffeeGrowingRegion(
      'gt-coban',
      'Cobán',
      'GT',
      -90.4,
      15.47,
      aliases: ['Coban', 'Rainforest Cobán', 'Alta Verapaz'],
    ),
    CoffeeGrowingRegion(
      'gt-fraijanes',
      'Fraijanes',
      'GT',
      -90.43,
      14.46,
      aliases: ['Fraijanes Plateau'],
    ),
    CoffeeGrowingRegion('gt-nuevo-oriente', 'Nuevo Oriente', 'GT', -89.7, 14.6),
    CoffeeGrowingRegion(
      'gt-san-marcos',
      'San Marcos',
      'GT',
      -91.8,
      14.96,
      aliases: ['Volcanic San Marcos'],
    ),

    // --- Mexico, Caribbean, Hawaii ----------------------------------------
    CoffeeGrowingRegion(
      'mx-chiapas',
      'Chiapas',
      'MX',
      -92.3,
      15.7,
      aliases: ['Soconusco', 'Tapachula'],
    ),
    CoffeeGrowingRegion(
      'mx-oaxaca',
      'Oaxaca',
      'MX',
      -96.7,
      16.4,
      aliases: ['Pluma Hidalgo'],
    ),
    CoffeeGrowingRegion(
      'mx-veracruz',
      'Veracruz',
      'MX',
      -96.9,
      19.4,
      aliases: ['Coatepec', 'Huatusco'],
    ),
    CoffeeGrowingRegion(
      'mx-puebla',
      'Puebla',
      'MX',
      -97.5,
      20.0,
      aliases: ['Cuetzalan'],
    ),
    CoffeeGrowingRegion(
      'jm-blue-mountains',
      'Blue Mountains',
      'JM',
      -76.6,
      18.05,
      aliases: ['Jamaica Blue Mountain', 'Blue Mountain', 'JBM'],
    ),
    CoffeeGrowingRegion('do-barahona', 'Barahona', 'DO', -71.1, 18.2),
    CoffeeGrowingRegion('do-jarabacoa', 'Jarabacoa', 'DO', -70.6, 19.1),
    CoffeeGrowingRegion(
      'us-kona',
      'Kona',
      'US',
      -155.9,
      19.5,
      aliases: ['Kona Coast', 'Holualoa'],
    ),
    CoffeeGrowingRegion('us-kau', "Ka'u", 'US', -155.6, 19.2, aliases: ['Kau']),
    CoffeeGrowingRegion('us-maui', 'Maui', 'US', -156.3, 20.8),
    CoffeeGrowingRegion(
      'us-kauai',
      'Kauai',
      'US',
      -159.5,
      22.0,
      aliases: ["Kaua'i"],
    ),

    // --- Asia & Pacific ---------------------------------------------------
    CoffeeGrowingRegion(
      'in-chikmagalur',
      'Chikmagalur',
      'IN',
      75.77,
      13.3,
      aliases: ['Chikkamagaluru', 'Baba Budangiri', 'Bababudangiri'],
    ),
    CoffeeGrowingRegion(
      'in-coorg',
      'Coorg',
      'IN',
      75.8,
      12.4,
      aliases: ['Kodagu'],
    ),
    CoffeeGrowingRegion(
      'in-araku',
      'Araku Valley',
      'IN',
      82.88,
      18.3,
      aliases: ['Araku'],
    ),
    CoffeeGrowingRegion('in-wayanad', 'Wayanad', 'IN', 76.1, 11.7),
    CoffeeGrowingRegion(
      'in-nilgiris',
      'Nilgiris',
      'IN',
      76.7,
      11.4,
      aliases: ['Nilgiri'],
    ),
    CoffeeGrowingRegion(
      'id-gayo',
      'Aceh Gayo',
      'ID',
      96.8,
      4.6,
      aliases: ['Gayo', 'Takengon', 'Aceh'],
    ),
    CoffeeGrowingRegion(
      'id-north-sumatra',
      'North Sumatra',
      'ID',
      98.9,
      2.3,
      aliases: [
        'Lintong',
        'Mandheling',
        'Mandailing',
        'Sidikalang',
        'Lake Toba',
      ],
    ),
    CoffeeGrowingRegion(
      'id-west-java',
      'West Java',
      'ID',
      107.6,
      -7.1,
      aliases: ['Java Preanger', 'Preanger', 'Garut'],
    ),
    CoffeeGrowingRegion(
      'id-east-java',
      'East Java',
      'ID',
      114.2,
      -7.9,
      aliases: ['Ijen', 'Java Ijen'],
    ),
    CoffeeGrowingRegion(
      'id-toraja',
      'Toraja',
      'ID',
      119.9,
      -3.0,
      aliases: ['Sulawesi Toraja', 'Kalosi', 'Tana Toraja'],
    ),
    CoffeeGrowingRegion(
      'id-kintamani',
      'Kintamani',
      'ID',
      115.3,
      -8.25,
      aliases: ['Bali Kintamani'],
    ),
    CoffeeGrowingRegion(
      'id-bajawa',
      'Bajawa',
      'ID',
      120.95,
      -8.8,
      aliases: ['Flores Bajawa', 'Ngada'],
    ),
    CoffeeGrowingRegion(
      'id-wamena',
      'Wamena',
      'ID',
      138.9,
      -4.1,
      aliases: ['Baliem', 'Baliem Valley', 'Papua'],
    ),
    CoffeeGrowingRegion(
      'pg-eastern-highlands',
      'Eastern Highlands',
      'PG',
      145.4,
      -6.1,
      aliases: ['Goroka'],
    ),
    CoffeeGrowingRegion(
      'pg-western-highlands',
      'Western Highlands',
      'PG',
      144.3,
      -5.85,
      aliases: ['Mount Hagen', 'Wahgi', 'Waghi'],
    ),
    CoffeeGrowingRegion(
      'th-chiang-rai',
      'Chiang Rai',
      'TH',
      99.83,
      19.9,
      aliases: ['Doi Chang', 'Doi Chaang'],
    ),
    CoffeeGrowingRegion('th-chiang-mai', 'Chiang Mai', 'TH', 98.98, 18.8),
    CoffeeGrowingRegion(
      'vn-lam-dong',
      'Lâm Đồng',
      'VN',
      108.44,
      11.94,
      aliases: ['Lam Dong', 'Da Lat', 'Dalat', 'Cau Dat'],
    ),
    CoffeeGrowingRegion(
      'vn-dak-lak',
      'Đắk Lắk',
      'VN',
      108.05,
      12.67,
      aliases: ['Dak Lak', 'Daklak', 'Buon Ma Thuot'],
    ),
    CoffeeGrowingRegion(
      'vn-son-la',
      'Sơn La',
      'VN',
      103.9,
      21.3,
      aliases: ['Son La'],
    ),
    CoffeeGrowingRegion(
      'la-bolaven',
      'Bolaven Plateau',
      'LA',
      106.3,
      15.2,
      aliases: ['Bolaven', 'Paksong'],
    ),
    CoffeeGrowingRegion(
      'cn-puer',
      "Pu'er",
      'CN',
      100.97,
      22.78,
      aliases: ['Puer', 'Simao'],
    ),
    CoffeeGrowingRegion('cn-baoshan', 'Baoshan', 'CN', 99.16, 25.1),
    CoffeeGrowingRegion('cn-lincang', 'Lincang', 'CN', 100.08, 23.88),
    CoffeeGrowingRegion(
      'mm-ywangan',
      'Ywangan',
      'MM',
      96.7,
      21.0,
      aliases: ['Southern Shan'],
    ),
    CoffeeGrowingRegion(
      'mm-pyin-oo-lwin',
      'Pyin Oo Lwin',
      'MM',
      96.46,
      22.03,
      aliases: ['Mandalay'],
    ),
    CoffeeGrowingRegion(
      'tw-alishan',
      'Alishan',
      'TW',
      120.8,
      23.5,
      aliases: ['Ali Shan'],
    ),
    CoffeeGrowingRegion(
      'ph-benguet',
      'Benguet',
      'PH',
      120.6,
      16.4,
      aliases: ['Atok'],
    ),
    CoffeeGrowingRegion(
      'ph-sagada',
      'Sagada',
      'PH',
      120.9,
      17.1,
      aliases: ['Mountain Province'],
    ),
    CoffeeGrowingRegion(
      'ph-mount-apo',
      'Mount Apo',
      'PH',
      125.3,
      7.0,
      aliases: ['Mt. Apo', 'Davao'],
    ),
    CoffeeGrowingRegion(
      'tl-ermera',
      'Ermera',
      'TL',
      125.4,
      -8.75,
      aliases: ['Letefoho'],
    ),
    CoffeeGrowingRegion('tl-aileu', 'Aileu', 'TL', 125.57, -8.73),
    CoffeeGrowingRegion(
      'tl-maubisse',
      'Maubisse',
      'TL',
      125.6,
      -8.84,
      aliases: ['Ainaro'],
    ),
    CoffeeGrowingRegion('np-gulmi', 'Gulmi', 'NP', 83.3, 28.08),
    CoffeeGrowingRegion('np-palpa', 'Palpa', 'NP', 83.55, 27.87),
    CoffeeGrowingRegion(
      'au-atherton',
      'Atherton Tablelands',
      'AU',
      145.5,
      -17.3,
      aliases: ['Atherton', 'Mareeba'],
    ),
    CoffeeGrowingRegion(
      'au-northern-rivers',
      'Northern Rivers',
      'AU',
      153.4,
      -28.6,
      aliases: ['Byron Bay'],
    ),
  ];

  static final Map<String, CoffeeGrowingRegion> byId = {
    for (final r in all) r.id: r,
  };

  /// Regions of one country, in list order.
  static List<CoffeeGrowingRegion> ofCountry(String code) => [
    for (final r in all)
      if (r.country == code) r,
  ];

  // Several regions may share a name across countries (none do yet, but
  // "Santa Barbara" or "San Marcos" easily could), so a key maps to a list.
  static final Map<String, List<CoffeeGrowingRegion>> _byKey = () {
    final m = <String, List<CoffeeGrowingRegion>>{};
    for (final r in all) {
      for (final n in [r.name, ...r.aliases]) {
        final list = m[_key(n)] ??= [];
        if (!list.contains(r)) list.add(r);
      }
    }
    return m;
  }();

  static String _key(String s) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'ắ': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ồ': 'o',
      'ơ': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
      'đ': 'd',
      'ầ': 'a',
    };
    final lower = s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// The region [text] names. With [country] (ISO code) set, a name shared
  /// by several countries resolves to the one in that country.
  static CoffeeGrowingRegion? match(String text, {String? country}) {
    final hits = _byKey[_key(text)];
    if (hits == null) return null;
    if (country != null) {
      for (final r in hits) {
        if (r.country == country) return r;
      }
      return null;
    }
    return hits.length == 1 ? hits.first : null;
  }

  /// What a bean says about its origin: the countries (from the country
  /// field, else from the regions) and the regions. A region that belongs
  /// to none of the named countries is ignored rather than guessed.
  static ({List<CoffeeCountry> countries, List<CoffeeGrowingRegion> regions})
  forBean(String? country, String? region) {
    final countries = CoffeeCountries.matchAll(country);
    if (countries.isEmpty) {
      final regions = matchAll(region);
      final fromRegions = <CoffeeCountry>[];
      for (final r in regions) {
        final c = CoffeeCountries.byCode[r.country]!;
        if (!fromRegions.contains(c)) fromRegions.add(c);
      }
      if (fromRegions.isEmpty) {
        // "Huila" typed into the country field instead of the region.
        final misplaced = matchAll(country);
        return (
          countries: [
            for (final r in misplaced) CoffeeCountries.byCode[r.country]!,
          ],
          regions: misplaced,
        );
      }
      return (countries: fromRegions, regions: regions);
    }
    final regions = <CoffeeGrowingRegion>[];
    for (final c in countries) {
      for (final r in matchAll(region, country: c.code)) {
        if (!regions.contains(r)) regions.add(r);
      }
    }
    return (countries: countries, regions: regions);
  }

  /// All regions in a bean's region field: "Huila, Pitalito" → Huila once;
  /// "Sidama / Guji" → both.
  static List<CoffeeGrowingRegion> matchAll(String? text, {String? country}) {
    if (text == null || text.trim().isEmpty) return const [];
    final whole = match(text, country: country);
    if (whole != null) return [whole];
    final found = <CoffeeGrowingRegion>[];
    for (final part in text.split(
      RegExp(
        r'\s*(?:,|;|/|&|\+|\band\b|\bund\b|\s-\s)\s*',
        caseSensitive: false,
      ),
    )) {
      final r = match(part, country: country);
      if (r != null && !found.contains(r)) found.add(r);
    }
    return found;
  }
}

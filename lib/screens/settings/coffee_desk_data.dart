import '../../models/gear.dart';
import '../../models/grinder.dart';
import '../../models/water.dart';

// What My Coffee Desk shows until gear has a store of its own: the real
// grinders and waters (edited in their existing forms), plus demo pieces for
// the categories that have no data yet. Demo pieces carry the `demo:` ID
// prefix and are never saved.

const demoPrefix = 'demo:';

bool isDemoGear(Gear g) => g.id.startsWith(demoPrefix);

Gear gearFromGrinder(Grinder g) => Gear(
  id: g.id,
  type: GearType.grinder,
  brand: g.brand,
  model: g.name,
  specs: {'burrs': ?g.activeBurrs, if (g.burrs.length > 1) 'burrSets': g.burrs},
);

Gear gearFromWater(Water w) => Gear(
  id: w.id,
  type: GearType.water,
  model: w.recipe,
  brewModes: switch (w.use) {
    WaterUse.espresso => const {BrewMode.espresso},
    WaterUse.pourOver => const {BrewMode.pourOver},
    _ => const {BrewMode.espresso, BrewMode.pourOver},
  },
  specs: {
    'gh': ?w.gh,
    'kh': ?w.kh,
    if (_minerals(w).isNotEmpty) 'recipe': _minerals(w),
  },
);

String _minerals(Water w) => [
  for (final m in Mineral.values)
    if (w.ghMinerals.contains(m) || w.khMinerals.contains(m)) m.label,
].join(', ');

const _e = {BrewMode.espresso};
const _p = {BrewMode.pourOver};

const demoGear = [
  Gear(
    id: '${demoPrefix}df64',
    type: GearType.grinder,
    brand: 'Turin',
    model: 'DF64 Gen 2',
    specs: {'burrs': 'SSP MP', 'grindScale': '0–90, zero at 4', 'shots': 212},
  ),
  Gear(
    id: '${demoPrefix}comandante',
    type: GearType.grinder,
    brand: 'Comandante',
    model: 'C40 MK4',
    brewModes: _p,
    specs: {'shape': 'hand', 'grindScale': 'Clicks, zero at 0'},
  ),
  Gear(
    id: '${demoPrefix}meticulous',
    type: GearType.machine,
    brand: 'Meticulous',
    model: 'Meticulous',
    brewModes: _e,
    specs: {'group': '58 mm'},
  ),
  Gear(
    id: '${demoPrefix}gaggia',
    type: GearType.machine,
    brand: 'Gaggia',
    model: 'Classic Pro · GaggiMate',
    brewModes: _e,
    specs: {'group': '58 mm', 'boiler': 'Single'},
  ),
  Gear(
    id: '${demoPrefix}ims18',
    type: GearType.basket,
    brand: 'IMS',
    model: 'Precision 18',
    brewModes: _e,
    specs: {'dose': 18, 'size': '58 mm'},
  ),
  Gear(
    id: '${demoPrefix}vst20',
    type: GearType.basket,
    brand: 'VST',
    model: 'Ridged 20',
    brewModes: _e,
    specs: {'dose': 20, 'size': '58 mm'},
  ),
  Gear(
    id: '${demoPrefix}normcore',
    type: GearType.tamper,
    brand: 'Normcore',
    model: 'Spring Tamper V4',
    brewModes: _e,
    specs: {'size': '58.5 mm'},
  ),
  Gear(
    id: '${demoPrefix}v60',
    type: GearType.brewer,
    brand: 'Hario',
    model: 'V60 02',
    brewModes: _p,
    specs: {'material': 'Plastic'},
  ),
  Gear(
    id: '${demoPrefix}origami',
    type: GearType.brewer,
    brand: 'Origami',
    model: 'Air M',
    brewModes: _p,
    specs: {'shape': 'flat', 'material': 'Resin'},
  ),
  Gear(
    id: '${demoPrefix}aeropress',
    type: GearType.brewer,
    brand: 'AeroPress',
    model: 'Original',
    brewModes: _p,
    specs: {'shape': 'press'},
  ),
  Gear(
    id: '${demoPrefix}v60paper',
    type: GearType.filter,
    brand: 'Hario',
    model: 'V60 02 Tabbed',
    brewModes: _p,
    specs: {'flow': 'Medium'},
    stock: 64,
  ),
  Gear(
    id: '${demoPrefix}sibarist',
    type: GearType.filter,
    brand: 'Sibarist',
    model: 'FAST Flat',
    brewModes: _p,
    specs: {'flow': 'Fast'},
    stock: 12,
  ),
  Gear(
    id: '${demoPrefix}puckscreen',
    type: GearType.filter,
    brand: 'Normcore',
    model: 'Puck screen 1.7',
    brewModes: _e,
    specs: {'size': '58.5 mm'},
  ),
  Gear(
    id: '${demoPrefix}stagg',
    type: GearType.kettle,
    brand: 'Fellow',
    model: 'Stagg EKG',
    brewModes: _p,
    specs: {'capacity': '0.9 L'},
  ),
  Gear(
    id: '${demoPrefix}lunar',
    type: GearType.scale,
    brand: 'Acaia',
    model: 'Lunar',
    brewModes: _e,
    specs: {'connection': 'Bluetooth'},
  ),
  Gear(
    id: '${demoPrefix}pearl',
    type: GearType.scale,
    brand: 'Acaia',
    model: 'Pearl',
    brewModes: _p,
    specs: {'connection': 'Bluetooth'},
  ),
  Gear(
    id: '${demoPrefix}twe',
    type: GearType.water,
    brand: 'Third Wave Water',
    model: 'Espresso',
    brewModes: _e,
    specs: {'gh': 68, 'kh': 40, 'recipe': 'Mineral sachet'},
  ),
];

/// Demo chains: what is "in use". The first real grinder and water join the
/// espresso bar so the ring shows on real data too.
List<BrewChain> demoChains({String? grinderId, String? waterId}) => [
  BrewChain(
    id: '${demoPrefix}espresso',
    name: 'Espresso bar',
    gearIds: [
      '${demoPrefix}meticulous',
      '${demoPrefix}df64',
      '${demoPrefix}ims18',
      '${demoPrefix}normcore',
      '${demoPrefix}puckscreen',
      '${demoPrefix}lunar',
      ?grinderId,
      ?waterId,
    ],
  ),
  const BrewChain(
    id: '${demoPrefix}pourover',
    name: 'Pour over',
    gearIds: [
      '${demoPrefix}comandante',
      '${demoPrefix}v60',
      '${demoPrefix}v60paper',
      '${demoPrefix}stagg',
      '${demoPrefix}pearl',
    ],
  ),
  const BrewChain(
    id: '${demoPrefix}travel',
    name: 'Travel',
    gearIds: ['${demoPrefix}aeropress'],
    active: false,
  ),
];

/// Key-value lines of the detail, in a fixed order per key.
List<(String, String)> gearDetailRows(Gear g) {
  String fmt(String key, Object value) => switch (key) {
    'dose' => '$value g',
    'gh' || 'kh' => '${_n(value)} ppm',
    _ => '$value',
  };
  const labels = {
    'burrs': 'Burrs',
    'grindScale': 'Grind scale',
    'shots': 'Shots',
    'group': 'Group',
    'boiler': 'Boiler',
    'dose': 'Dose',
    'size': 'Size',
    'material': 'Material',
    'flow': 'Flow',
    'capacity': 'Capacity',
    'connection': 'Connection',
    'gh': 'GH',
    'kh': 'KH',
    'recipe': 'Recipe',
  };
  return [
    for (final e in labels.entries)
      if (g.specs[e.key] case final Object v) (e.value, fmt(e.key, v)),
    if (g.stock != null) ('Stock', '${g.stock}'),
    ('Used for', g.brewModes.map((m) => m.label).join(' · ')),
  ];
}

String _n(Object v) =>
    v is num ? v.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '') : '$v';

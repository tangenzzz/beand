import '../../models/gear.dart';
import '../../models/grind_scale.dart';
import '../../services/gear_store.dart' show grinderFromGear;
import '../../models/water.dart';

// What My Coffee Desk asks and shows per kind of gear. Grinders and waters
// have their own dialogs (burr sets, minerals); every other type uses the
// generic gear form with the fields listed here.

/// One free-text (or number) field of the gear form, stored in
/// [Gear.specs] under [key].
class SpecField {
  const SpecField(this.key, this.label, {this.unit, this.numeric = false});

  final String key;
  final String label;
  final String? unit;
  final bool numeric;
}

const specFields = <GearType, List<SpecField>>{
  GearType.machine: [
    SpecField('group', 'Group'),
    SpecField('boiler', 'Boiler'),
  ],
  GearType.basket: [
    SpecField('dose', 'Dose', unit: 'g', numeric: true),
    SpecField('size', 'Size'),
  ],
  GearType.tamper: [SpecField('size', 'Size')],
  GearType.brewer: [SpecField('material', 'Material')],
  GearType.filter: [SpecField('flow', 'Flow'), SpecField('size', 'Size')],
  GearType.puckScreen: [
    SpecField('size', 'Size'),
    SpecField('thickness', 'Thickness', unit: 'mm', numeric: true),
  ],
  GearType.kettle: [SpecField('capacity', 'Capacity')],
  GearType.scale: [SpecField('connection', 'Connection')],
};

/// Shape variants with their own icon (GearType.iconAsset), null = none.
const gearShapes = <GearType, List<(String?, String)>>{
  GearType.brewer: [(null, 'Cone'), ('flat', 'Flat'), ('press', 'Press')],
};

/// Consumables with a count on hand.
bool hasStock(GearType type) => type == GearType.filter;

/// What a new piece serves until the user says otherwise.
Set<BrewMode> defaultBrewModes(GearType type) => switch (type) {
  GearType.machine ||
  GearType.basket ||
  GearType.puckScreen ||
  GearType.tamper => const {BrewMode.espresso},
  GearType.brewer || GearType.kettle => const {BrewMode.pourOver},
  _ => const {BrewMode.espresso, BrewMode.pourOver},
};

/// Key-value lines of the detail. [shots] is the grinder's shot count,
/// [chains] the names of the chains the piece belongs to.
List<(String, String)> gearDetailRows(
  Gear g, {
  int? shots,
  List<String> chains = const [],
}) => [
  if (g.type == GearType.grinder)
    if (g.specs['activeBurr'] case final String burrs) ('Burrs', burrs),
  if (g.type == GearType.grinder) ..._grinderRows(g),
  if (g.type == GearType.water) ..._waterRows(g),
  for (final f in specFields[g.type] ?? const <SpecField>[])
    if (g.specs[f.key] case final Object v)
      if ('$v'.trim().isNotEmpty)
        (f.label, f.unit == null ? _n(v) : '${_n(v)} ${f.unit}'),
  if (g.type == GearType.grinder && shots != null) ('Shots', '$shots'),
  if (g.stock != null) ('Stock', '${g.stock}'),
  if (chains.isNotEmpty) ('Chains', chains.join(', ')),
];

// Scale ("Dial 0–50 · steps of 0.5") and zero point ("−0.3 · 19 Oct 2026").
List<(String, String)> _grinderRows(Gear g) {
  final grinder = grinderFromGear(g);
  final scale = grinder.scale;
  final zero = grinder.zeroPoint;
  String n(double v, GrindScale s) => s.format(v, withUnit: false);
  return [
    if (scale != null)
      (
        'Scale',
        [
          scale.unit.label,
          '${n(scale.min, scale)}–${n(scale.max, scale)}'
              '${scale.unit.suffix.isEmpty ? '' : ' ${scale.unit.suffix}'}',
          if (scale.unit.steps.length > 1) 'steps of ${_n(scale.step)}',
        ].join(' · '),
      ),
    if (scale != null && scale.hasMarkers)
      (
        'Markers',
        [
          for (final m in scale.markers)
            m.offset == 0
                ? m.name
                : '${m.name} ${m.offset > 0 ? '+' : ''}${_n(m.offset)}',
        ].join(' · '),
      ),
    if (zero != null) ('Zero point', '${_n(zero.value)} · ${_date(zero.at)}'),
  ];
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

List<(String, String)> _waterRows(Gear g) {
  final gh = g.specs['gh'];
  final kh = g.specs['kh'];
  final ppm = g.specs['ppm'];
  final names = Mineral.values.asNameMap();
  final minerals = [
    for (final key in ['ghMinerals', 'khMinerals'])
      if (g.specs[key] case final List list)
        for (final m in list)
          if (names[m] case final Mineral mineral) mineral.label,
  ];
  return [
    if (gh != null) ('GH', '${_n(gh)} ppm'),
    if (kh != null) ('KH', '${_n(kh)} ppm'),
    if (minerals.isNotEmpty) ('Minerals', minerals.join(', ')),
    if (ppm != null) ('TDS', '${_n(ppm)} ppm'),
  ];
}

String _n(Object v) =>
    v is num ? v.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '') : '$v';

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/gear.dart';
import '../../services/gear_store.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import 'coffee_desk_data.dart';
import 'gear_dialogs.dart';
import 'my_setup_dialogs.dart';
import 'settings_widgets.dart';

// Settings → My Coffee Desk: all the user's gear as shelves, one per
// category — a row of round avatars standing on a 3 dp "shelf board". A
// filter on top narrows to espresso, pour over or what is stored (in no
// active brew chain). Tapping an avatar folds its details out below that
// shelf; one piece at a time.
//
// Grinders and waters open their own dialogs (burr sets, minerals),
// everything else the generic gear form (gear_dialogs.dart).
enum DeskFilter {
  all('All'),
  espresso('Espresso'),
  pourOver('Pour over'),
  stored('Stored');

  const DeskFilter(this.label);
  final String label;
}

class MyCoffeeDeskScreen extends StatefulWidget {
  const MyCoffeeDeskScreen({super.key});

  @override
  State<MyCoffeeDeskScreen> createState() => _MyCoffeeDeskScreenState();
}

class _MyCoffeeDeskScreenState extends State<MyCoffeeDeskScreen> {
  DeskFilter _filter = DeskFilter.all;
  String? _openId;
  // Shots per grinder name; empty without a database (tests, previews).
  Stream<Map<String, int>>? _shotCounts;

  @override
  void initState() {
    super.initState();
    try {
      _shotCounts = context.read<AppDatabase>().watchGrinderShotCounts();
    } on ProviderNotFoundException {
      _shotCounts = null;
    }
  }

  bool _matches(Gear g, Set<String> active) => switch (_filter) {
    DeskFilter.all => true,
    DeskFilter.espresso => g.usedFor(BrewMode.espresso),
    DeskFilter.pourOver => g.usedFor(BrewMode.pourOver),
    DeskFilter.stored => !active.contains(g.id),
  };

  Future<void> _add(GearType type) async {
    switch (type) {
      case GearType.grinder:
        await showGrinderDialog(context);
      case GearType.water:
        await showWaterDialog(context);
      default:
        await showGearDialog(context, type: type);
    }
  }

  Future<void> _edit(Gear g) async {
    switch (g.type) {
      case GearType.grinder:
        final grinder = context.read<GrinderStore>().byId(g.id);
        if (grinder != null) await showGrinderDialog(context, grinder: grinder);
      case GearType.water:
        final water = context.read<WaterStore>().byId(g.id);
        if (water != null) await showWaterDialog(context, water: water);
      default:
        await showGearDialog(context, type: g.type, gear: g);
    }
  }

  Future<void> _choosePhoto(Gear g) async {
    final colors = context.colors;
    final store = context.read<GearStore>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: colors.textSecondary,
              ),
              title: Text(
                'Take photo',
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: colors.textSecondary,
              ),
              title: Text(
                'Choose from gallery',
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (g.photoPath != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colors.danger),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: colors.danger),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      store.removePhoto(g.id);
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      await store.setPhoto(g.id, picked.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load photo'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GearStore>();
    final active = store.activeIds;
    final shelves =
        [
              for (final type in GearType.values)
                (
                  type,
                  [
                    for (final g in store.ofType(type))
                      if (_matches(g, active)) g,
                  ],
                ),
            ]
            // "All" shows every category, empty ones with just "New"; a filter
            // drops what it leaves empty.
            .where((s) => _filter == DeskFilter.all || s.$2.isNotEmpty)
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Coffee Desk')),
      body: StreamBuilder<Map<String, int>>(
        stream: _shotCounts,
        builder: (context, counts) => ListView(
          padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
          children: [
            // One card: the filter, then one block per category, the brew
            // chains last — the hairlines between blocks are the card's own.
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.dividerInset,
                    8,
                    AppSpacing.dividerInset,
                    4,
                  ),
                  child: UnderlineSelect<DeskFilter>(
                    options: [
                      for (final f in DeskFilter.values)
                        UnderlineOption(f, f.label),
                    ],
                    value: _filter,
                    onChanged: (f) => setState(() {
                      _filter = f!;
                      _openId = null;
                    }),
                  ),
                ),
                if (shelves.isEmpty)
                  const SettingsSection(child: SettingsText('Nothing here.')),
                for (final (type, items) in shelves)
                  _Shelf(
                    type: type,
                    items: items,
                    active: active,
                    openId: _openId,
                    photoOf: store.photoFile,
                    shotsOf: (g) => g.type == GearType.grinder
                        ? (counts.data?[g.model] ?? 0)
                        : null,
                    chainsOf: (g) => [
                      for (final c in store.chainsOf(g.id)) c.name,
                    ],
                    onTap: (g) =>
                        setState(() => _openId = _openId == g.id ? null : g.id),
                    onAdd: () => _add(type),
                    onEdit: _edit,
                    onPhoto: _choosePhoto,
                  ),
                _Chains(chains: store.chains),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// The brew chains: which gear is used together. Gear in a chain that is in
// use gets the ring on its shelf; everything else counts as stored.
class _Chains extends StatelessWidget {
  const _Chains({required this.chains});

  final List<BrewChain> chains;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SettingsGroup(
      children: [
        SettingsGroupLabel(
          'Brew chains',
          icon: Icons.link,
          count: chains.length,
          trailing: IconButton(
            tooltip: 'Add brew chain',
            icon: Icon(Icons.add, color: colors.textSecondary),
            onPressed: () => showChainDialog(context),
          ),
        ),
        if (chains.isEmpty)
          const SettingsSection(
            child: SettingsText(
              'Group the gear you brew with — it then counts as in use.',
            ),
          ),
        for (final c in chains)
          SettingsRow(
            key: ValueKey('chain-${c.id}'),
            icon: c.active ? Icons.link : Icons.link_off,
            title: c.name,
            subtitle: [
              '${c.gearIds.length} ${c.gearIds.length == 1 ? 'piece' : 'pieces'}',
              if (!c.active) 'put away',
            ].join(' · '),
            onTap: () => showChainDialog(context, chain: c),
          ),
      ],
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.type,
    required this.items,
    required this.active,
    required this.openId,
    required this.photoOf,
    required this.shotsOf,
    required this.chainsOf,
    required this.onTap,
    required this.onAdd,
    required this.onEdit,
    required this.onPhoto,
  });

  final GearType type;
  final List<Gear> items;
  final Set<String> active;
  final String? openId;
  final File? Function(Gear) photoOf;
  final int? Function(Gear) shotsOf;
  final List<String> Function(Gear) chainsOf;
  final ValueChanged<Gear> onTap;
  final VoidCallback onAdd;
  final ValueChanged<Gear> onEdit;
  final ValueChanged<Gear> onPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final open = items.where((g) => g.id == openId).firstOrNull;
    return SettingsGroup(
      children: [
        SettingsGroupLabel(
          type.label,
          leading: GearIcon(
            asset: type.iconAsset(const {}),
            size: 17,
            color: colors.textSecondary,
          ),
          count: items.length,
          trailing: IconButton(
            tooltip: 'Add ${type.single.toLowerCase()}',
            icon: Icon(Icons.add, color: colors.textSecondary),
            onPressed: onAdd,
          ),
        ),
        SizedBox(
          height: GearAvatar.slotHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.dividerInset - GearAvatar.ringGap,
            ),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) => i == items.length
                ? _NewAvatar(onTap: onAdd)
                : GearAvatar(
                    gear: items[i],
                    photo: photoOf(items[i]),
                    active: active.contains(items[i].id),
                    selected: items[i].id == openId,
                    onTap: () => onTap(items[i]),
                  ),
          ),
        ),
        // The shelf board.
        Container(
          height: 3,
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dividerInset,
          ),
          decoration: BoxDecoration(
            color: colors.textTertiary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open == null
              ? const SizedBox(width: double.infinity, height: 12)
              : _GearDetail(
                  key: ValueKey(open.id),
                  gear: open,
                  shots: shotsOf(open),
                  chains: chainsOf(open),
                  onEdit: () => onEdit(open),
                  onPhoto: () => onPhoto(open),
                ),
        ),
      ],
    );
  }
}

/// A gear type's line icon, tinted like text.
class GearIcon extends StatelessWidget {
  const GearIcon({
    super.key,
    required this.asset,
    required this.size,
    required this.color,
  });

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    asset,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

/// Round 56 dp avatar of one piece of gear: its photo, else the type's line
/// icon. Kept quiet (user feedback 2026-10-18 on the first draft: the rings
/// were far too loud): a thin, muted accent hairline when an active chain
/// uses it, a faint hairline when stored; the selected one only gets a
/// faint outer hairline and a brighter name. Badge: "E" or a dripper when
/// it serves only one brew mode.
class GearAvatar extends StatelessWidget {
  const GearAvatar({
    super.key,
    required this.gear,
    required this.active,
    required this.selected,
    required this.onTap,
    this.photo,
  });

  final Gear gear;
  final File? photo;
  final bool active;
  final bool selected;
  final VoidCallback onTap;

  static const size = 56.0;
  static const ringGap = 4.0;
  static const _slot = size + 2 * ringGap;
  static const slotHeight = _slot + 4 + 16;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photo = this.photo;
    final iconColor = active
        ? colors.textPrimary
        : colors.textPrimary.withValues(alpha: 0.4);
    final mode = gear.brewModes.length == 1 ? gear.brewModes.first : null;
    return Semantics(
      button: true,
      selected: selected,
      label: [gear.brand, gear.model].whereType<String>().join(' '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _slot,
          child: Column(
            children: [
              SizedBox.square(
                dimension: _slot,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (selected)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.textTertiary.withValues(alpha: 0.6),
                            width: 0.5,
                          ),
                        ),
                      ),
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active
                              ? colors.accent.withValues(alpha: 0.55)
                              : colors.textTertiary.withValues(alpha: 0.5),
                          width: active ? 1 : 0.5,
                        ),
                      ),
                      padding: const EdgeInsets.all(1),
                      child: CircleAvatar(
                        backgroundColor: colors.bg,
                        foregroundImage: photo == null
                            ? null
                            : ResizeImage(FileImage(photo), width: 160),
                        child: GearIcon(
                          asset: gear.type.iconAsset(gear.specs),
                          size: 28,
                          color: iconColor,
                        ),
                      ),
                    ),
                    if (mode != null)
                      Positioned(
                        right: ringGap,
                        bottom: ringGap,
                        child: _ModeBadge(mode: mode),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                gear.model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final BrewMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.card,
        shape: BoxShape.circle,
        border: Border.all(color: colors.textTertiary, width: 0.5),
      ),
      child: mode == BrewMode.espresso
          ? Text(
              'E',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            )
          : GearIcon(
              asset: 'assets/icons/gear/dripper_cone.svg',
              size: 12,
              color: colors.textPrimary,
            ),
    );
  }
}

// The "+" at the end of a shelf: dashed circle, "New" below.
class _NewAvatar extends StatelessWidget {
  const _NewAvatar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'New',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: GearAvatar._slot,
          child: Column(
            children: [
              SizedBox.square(
                dimension: GearAvatar._slot,
                child: Center(
                  child: CustomPaint(
                    painter: _DashedCircle(colors.textTertiary),
                    child: SizedBox.square(
                      dimension: GearAvatar.size,
                      child: Icon(Icons.add, color: colors.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'New',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    const dashes = 24;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(0.5), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

// The open piece: editorial, no card — brand small and gray, the model
// large, then key-value lines on hairlines; Edit and Photo at the bottom.
class _GearDetail extends StatelessWidget {
  const _GearDetail({
    super.key,
    required this.gear,
    required this.onEdit,
    required this.onPhoto,
    this.shots,
    this.chains = const [],
  });

  final Gear gear;
  final int? shots;
  final List<String> chains;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;

  // A grinder with several burr sets: the fitted one is picked right here,
  // as before in My Setup.
  Widget? _burrSwitch(BuildContext context, String key) {
    final sets = gear.specs['burrs'];
    if (key != 'Burrs' || sets is! List || sets.length < 2) return null;
    return UnderlineSelect<String>(
      options: [
        for (final b in sets.whereType<String>()) UnderlineOption(b, b),
      ],
      value: gear.specs['activeBurr'] as String?,
      onChanged: (b) {
        if (b != null) context.read<GrinderStore>().setActiveBurr(gear.id, b);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        14,
        AppSpacing.dividerInset,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gear.brand != null)
            Text(
              gear.brand!,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          Text(
            gear.model,
            style: TextStyle(color: colors.textPrimary, fontSize: 20),
          ),
          const SizedBox(height: 10),
          for (final (key, value) in gearDetailRows(
            gear,
            shots: shots,
            chains: chains,
          ))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.divider, width: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child:
                          _burrSwitch(context, key) ??
                          Text(
                            value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              UnderlineItem(label: 'Edit', selected: true, onTap: onEdit),
              const SizedBox(width: UnderlineSelect.spacing),
              UnderlineItem(label: 'Photo', selected: true, onTap: onPhoto),
            ],
          ),
        ],
      ),
    );
  }
}

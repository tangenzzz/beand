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
import '../live/tile_title.dart';
import 'coffee_desk_data.dart';
import 'desk_filter.dart';
import 'gear_dialogs.dart';
import 'gear_photo_preview.dart';
import 'my_setup_dialogs.dart';
import 'settings_widgets.dart';

// Settings → My Coffee Desk: all the user's gear as shelves, one per
// category — a row of round avatars standing on a 3 dp "shelf board" (a
// dashed "New" at the end adds one), no hairlines between the shelves,
// only one below the tabs. Two tabs: "Shelf" and "Brew chains" (one row per
// chain, swiped left: Copy and Delete; + adds one). Search and filter sit
// in the app bar like in the bean list and the history. Tapping an avatar
// folds its details out below that shelf, a long press edits it.
//
// Grinders and waters open their own dialogs (burr sets, minerals),
// everything else the generic gear form (gear_dialogs.dart).

class MyCoffeeDeskScreen extends StatefulWidget {
  const MyCoffeeDeskScreen({super.key});

  @override
  State<MyCoffeeDeskScreen> createState() => _MyCoffeeDeskScreenState();
}

// The two tabs on top: all gear on its shelves, or the brew chains.
enum _DeskTab { shelf, chains }

class _MyCoffeeDeskScreenState extends State<MyCoffeeDeskScreen> {
  _DeskTab _tab = _DeskTab.shelf;
  DeskFilter _filter = DeskFilter.empty;
  final _search = TextEditingController();
  bool _searching = false;
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
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectTab(_DeskTab tab) => setState(() {
    _tab = tab;
    _openId = null;
  });

  // Copy a chain to change one category in the copy — a chain holds one
  // piece per category; another basket means another chain.
  Future<void> _copyChain(BrewChain chain) async {
    final store = context.read<GearStore>();
    final copy = store.saveChain(
      BrewChain(id: '', name: '${chain.name} copy', gearIds: chain.gearIds),
    );
    await showChainDialog(context, chain: copy);
  }

  Future<void> _openFilter() async {
    final store = context.read<GearStore>();
    final result = await showDeskFilterSheet(
      context,
      gear: store.gear,
      inUse: store.activeIds,
      query: _search.text,
      initial: _filter,
    );
    if (result != null && mounted) {
      setState(() {
        _filter = result;
        _openId = null;
      });
    }
  }

  Future<void> _add(GearType type) => _openAddDialog(type);

  // The photo choice from a dialog's head; a new piece is already saved
  // by then (user 2026-10-22: photo while adding, not only afterwards).
  void _photoFor(String id) {
    final current = context.read<GearStore>().byId(id);
    if (current != null) _choosePhoto(current);
  }

  Future<void> _openAddDialog(GearType type) async {
    switch (type) {
      case GearType.grinder:
        await showGrinderDialog(context, onPhoto: _photoFor);
      case GearType.water:
        await showWaterDialog(context, onPhoto: _photoFor);
      default:
        await showGearDialog(context, type: type, onPhoto: _photoFor);
    }
  }

  // Long press on a piece: its dialog, with "Photo" at the top.
  Future<void> _edit(Gear g) async {
    switch (g.type) {
      case GearType.grinder:
        final grinder = context.read<GrinderStore>().byId(g.id);
        if (grinder != null) {
          await showGrinderDialog(
            context,
            grinder: grinder,
            onPhoto: _photoFor,
          );
        }
      case GearType.water:
        final water = context.read<WaterStore>().byId(g.id);
        if (water != null) {
          await showWaterDialog(context, water: water, onPhoto: _photoFor);
        }
      default:
        await showGearDialog(
          context,
          type: g.type,
          gear: g,
          onPhoto: _photoFor,
        );
    }
  }

  Future<void> _choosePhoto(Gear g) async {
    final colors = context.colors;
    final store = context.read<GearStore>();
    Widget item(
      IconData icon,
      String label,
      String value, {
      bool danger = false,
    }) => ListTile(
      leading: Icon(icon, color: danger ? colors.danger : colors.textSecondary),
      title: Text(
        label,
        style: TextStyle(color: danger ? colors.danger : colors.textPrimary),
      ),
      onTap: () => Navigator.pop(context, value),
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(Icons.photo_camera_outlined, 'Take photo', 'camera'),
            item(
              Icons.photo_library_outlined,
              'Choose from gallery',
              'gallery',
            ),
            if (g.isCutout)
              item(Icons.crop_original, 'Use original photo', 'original')
            else if (store.photoFile(g) != null)
              item(Icons.auto_fix_high_outlined, 'Cut out', 'cutout'),
            if (g.photoPath != null)
              item(
                Icons.delete_outline,
                'Remove photo',
                'remove',
                danger: true,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'remove':
        store.removePhoto(g.id);
      case 'original':
        store.useOriginalPhoto(g.id);
      case 'cutout':
        final photo = store.photoFile(g);
        if (photo == null) return;
        final choice = await showCutoutPreview(
          context,
          photo.path,
          allowRetake: false,
        );
        if (choice?.$1 == PhotoChoice.cutout && choice!.$2 != null) {
          await store.applyCutout(g.id, choice.$2!);
        }
      default:
        await _takePhoto(
          g,
          action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        );
    }
  }

  // Pick or take a photo, cut it out right away, then the user picks: the
  // cut-out, the photo as it is, or another go.
  Future<void> _takePhoto(Gear g, ImageSource source) async {
    final store = context.read<GearStore>();
    try {
      while (mounted) {
        final picked = await ImagePicker().pickImage(
          source: source,
          // Large enough for a clean edge; the cut-out ends up smaller.
          maxWidth: 1600,
          imageQuality: 90,
        );
        if (picked == null || !mounted) return;
        final choice = await showCutoutPreview(context, picked.path);
        if (choice == null) return;
        switch (choice.$1) {
          case PhotoChoice.retake:
            continue;
          case PhotoChoice.cutout:
            await store.setPhoto(g.id, picked.path, cutout: choice.$2);
          case PhotoChoice.original:
            await store.setPhoto(g.id, picked.path);
        }
        return;
      }
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

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  Widget _filterButton() {
    final colors = context.colors;
    final count = _filter.activeCount;
    return IconButton(
      tooltip: 'Filter',
      onPressed: _openFilter,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: colors.textPrimary,
        textColor: colors.bg,
        child: Icon(
          Icons.tune,
          color: count > 0 ? colors.accent : colors.textSecondary,
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final colors = context.colors;
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Close search',
          icon: Icon(Icons.arrow_back, color: colors.textSecondary),
          onPressed: _closeSearch,
        ),
        title: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          cursorColor: colors.accent,
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'Search gear',
            hintStyle: TextStyle(color: colors.textTertiary),
          ),
        ),
        actions: [
          if (_search.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: Icon(Icons.close, color: colors.textSecondary),
              onPressed: _search.clear,
            ),
          if (_tab == _DeskTab.shelf) _filterButton(),
        ],
      );
    }
    return AppBar(
      title: const Text('My Coffee Desk'),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: Icon(Icons.search, color: colors.textSecondary),
          onPressed: () => setState(() => _searching = true),
        ),
        // The filter is about gear; the chains have the search alone.
        if (_tab == _DeskTab.shelf) _filterButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GearStore>();
    final active = store.activeIds;
    final query = _search.text.trim();
    final visible = filterDesk(
      store.gear,
      inUse: active,
      query: query,
      filter: _filter,
    );
    // The shelf without search or filter shows every category, empty ones
    // with just "New"; anything narrower drops what it leaves empty.
    final showEmpty = !_filter.isActive && query.isEmpty;
    final shelves = [
      for (final type in GearType.values)
        (
          type,
          [
            for (final g in visible)
              if (g.type == type) g,
          ],
        ),
    ].where((s) => showEmpty || s.$2.isNotEmpty).toList();
    // The search goes over a chain's name and its pieces too.
    final chains = [
      for (final c in store.chains)
        if (query.isEmpty || matchesChainQuery(c.name, store.gearOf(c), query))
          c,
    ];

    return Scaffold(
      appBar: _appBar(),
      body: StreamBuilder<Map<String, int>>(
        stream: _shotCounts,
        builder: (context, counts) => ListView(
          padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
          children: [
            // One card: the tabs, then one block per category (or one row
            // per chain) — without hairlines, the shelf boards divide
            // enough.
            SettingsCard(
              dividers: false,
              children: [
                _DeskTabs(
                  tab: _tab,
                  onSelect: _selectTab,
                  onAddChain: _tab == _DeskTab.chains
                      ? () => showChainDialog(context)
                      : null,
                ),
                // The one hairline left: tabs above, content below.
                const SettingsDivider(),
                if (_tab == _DeskTab.chains) ...[
                  if (chains.isEmpty)
                    SettingsSection(
                      child: SettingsText(
                        store.chains.isEmpty
                            ? 'Group the gear you brew with — one piece per category. Tap + to add a chain.'
                            : 'Nothing here.',
                      ),
                    ),
                  for (final c in chains)
                    _ChainRow(
                      key: ValueKey('chain-${c.id}'),
                      chain: c,
                      pieces: store.gearOf(c),
                      photoOf: store.photoFile,
                      onTap: () => showChainDialog(
                        context,
                        chain: c,
                        onCopy: () => _copyChain(c),
                      ),
                      onEditGear: _edit,
                    ),
                  const SizedBox(height: 8),
                ] else ...[
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
                      onTap: (g) => setState(
                        () => _openId = _openId == g.id ? null : g.id,
                      ),
                      onAdd: () => _add(type),
                      onEdit: _edit,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// "Shelf" and "Brew chains" on top; on the chains tab "+" at the right adds
// one.
class _DeskTabs extends StatelessWidget {
  const _DeskTabs({
    required this.tab,
    required this.onSelect,
    required this.onAddChain,
  });

  final _DeskTab tab;
  final ValueChanged<_DeskTab> onSelect;
  final VoidCallback? onAddChain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.dividerInset, 4, 4, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: UnderlineSelect<_DeskTab>(
                options: const [
                  UnderlineOption(_DeskTab.shelf, 'Shelf'),
                  UnderlineOption(_DeskTab.chains, 'Brew chains'),
                ],
                value: tab,
                onChanged: (t) => onSelect(t!),
              ),
            ),
            if (onAddChain != null)
              IconButton(
                tooltip: 'Add brew chain',
                icon: Icon(Icons.add, color: context.colors.textSecondary),
                onPressed: onAddChain,
              ),
          ],
        ),
      ),
    );
  }
}

// One brew chain as a shelf of its own: the pieces with their photos on a
// board, the chain's name on the plate below it. Tapping the plate or a
// piece edits the chain (copy and delete are in there), a long press edits
// the piece.
class _ChainRow extends StatelessWidget {
  const _ChainRow({
    super.key,
    required this.chain,
    required this.pieces,
    required this.photoOf,
    required this.onTap,
    required this.onEditGear,
  });

  final BrewChain chain;
  final List<Gear> pieces;
  final File? Function(Gear) photoOf;
  final VoidCallback onTap;
  final ValueChanged<Gear> onEditGear;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        const SizedBox(height: 10),
        _ShelfBoard(
          label: chain.name,
          onLabelTap: onTap,
          count: pieces.isEmpty ? 1 : pieces.length,
          builder: (context, i) => pieces.isEmpty
              ? _NewAvatar(
                  type: GearType.machine,
                  label: 'Add gear',
                  onTap: onTap,
                )
              : GearAvatar(
                  gear: pieces[i],
                  photo: photoOf(pieces[i]),
                  // Everything here is in use — it is in this chain.
                  active: true,
                  selected: false,
                  onTap: onTap,
                  onLongPress: () => onEditGear(pieces[i]),
                ),
        ),
        const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final open = items.where((g) => g.id == openId).firstOrNull;
    return SettingsGroup(
      children: [
        const SizedBox(height: 10),
        _ShelfBoard(
          label: type.label,
          count: items.length + 1,
          builder: (context, i) => i == items.length
              ? _NewAvatar(type: type, onTap: onAdd)
              : GearAvatar(
                  gear: items[i],
                  photo: photoOf(items[i]),
                  active: active.contains(items[i].id),
                  selected: items[i].id == openId,
                  onTap: () => onTap(items[i]),
                  onLongPress: () => onEdit(items[i]),
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
                ),
        ),
      ],
    );
  }
}

// The shelf board runs right under the avatars (cut-outs stand on it); the
// pieces scroll over a fixed board. Below the board on the right a small
// plate names the shelf — the category or the chain — instead of a heading
// above it (user choice 2026-10-21: calmer, the shelves sit closer).
// Shared by the category shelves and the brew chains.
class _ShelfBoard extends StatelessWidget {
  const _ShelfBoard({
    required this.count,
    required this.builder,
    required this.label,
    this.onLabelTap,
  });

  final int count;
  final IndexedWidgetBuilder builder;
  final String label;

  /// Tapping the plate (a chain: edit it).
  final VoidCallback? onLabelTap;

  static const _plateHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plate = Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
      ),
    );
    return SizedBox(
      height: GearAvatar.slotHeight + _plateHeight,
      child: Stack(
        children: [
          Positioned(
            top: GearAvatar.boardTop,
            left: AppSpacing.dividerInset,
            right: AppSpacing.dividerInset,
            child: Container(
              height: GearAvatar.boardHeight,
              decoration: BoxDecoration(
                color: colors.textTertiary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          Positioned(
            top: GearAvatar.boardTop + GearAvatar.boardHeight,
            right: AppSpacing.dividerInset - 8,
            child: onLabelTap == null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    child: plate,
                  )
                : InkWell(
                    key: ValueKey('plate-$label'),
                    onTap: onLabelTap,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                      child: plate,
                    ),
                  ),
          ),
          SizedBox(
            height: GearAvatar.slotHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.dividerInset - GearAvatar.ringGap,
              ),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: builder,
            ),
          ),
        ],
      ),
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
/// were far too loud): a thin, muted accent hairline when a chain uses it,
/// a faint hairline when stored; the selected one only gets a faint outer
/// hairline and a brighter name. A cut-out photo has no circle: the piece
/// stands freely on the board with a soft shadow, without an in-use mark. No brew-mode badge (removed on user request
/// 2026-10-20).
class GearAvatar extends StatelessWidget {
  const GearAvatar({
    super.key,
    required this.gear,
    required this.active,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.photo,
  });

  final Gear gear;
  final File? photo;
  final VoidCallback? onLongPress;
  final bool active;
  final bool selected;
  final VoidCallback onTap;

  static const size = 56.0;
  static const ringGap = 4.0;
  static const _slot = size + 2 * ringGap;

  /// Where the shelf board runs: right under the avatar.
  static const boardTop = _slot;
  static const boardHeight = 3.0;
  // Nothing below the board: the slot ends right under it.
  static const slotHeight = _slot + boardHeight + 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photo = this.photo;
    final iconColor = active
        ? colors.textPrimary
        : colors.textPrimary.withValues(alpha: 0.4);
    return Semantics(
      button: true,
      selected: selected,
      label: gear.label,
      child: GestureDetector(
        // The shelf shows no names: tests find a piece by this key.
        key: ValueKey('avatar-${gear.displayName}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Long press: straight to the edit dialog.
        onLongPress: onLongPress,
        child: SizedBox(
          width: _slot,
          child: Column(
            children: [
              SizedBox.square(
                dimension: _slot,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (gear.isCutout && photo != null)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: StandingImage(
                            image: Image.file(
                              photo,
                              width: _slot,
                              height: _slot,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              cacheWidth: 200,
                            ),
                          ),
                        ),
                      )
                    else ...[
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
                    ],
                  ],
                ),
              ),
              // Nothing under the board (user request 2026-10-20): no name,
              // no in-use dot — the photo or icon says it, tapping shows
              // brand and name.
            ],
          ),
        ),
      ),
    );
  }
}

// The "+" at the end of a shelf: dashed circle, nothing below.
class _NewAvatar extends StatelessWidget {
  const _NewAvatar({required this.type, required this.onTap, this.label});

  final GearType type;

  /// Instead of "Add machine" and the like, e.g. on an empty brew chain.
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label ?? 'Add ${type.single.toLowerCase()}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('new-${type.name}'),
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
// large, then key-value lines on hairlines. Editing is a long press.
class _GearDetail extends StatelessWidget {
  const _GearDetail({
    super.key,
    required this.gear,
    this.shots,
    this.chains = const [],
  });

  final Gear gear;
  final int? shots;
  final List<String> chains;

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
        if (b == null) return;
        final store = context.read<GrinderStore>();
        store.setActiveBurr(gear.id, b);
        // Other burrs touch at another point: offer to set theirs, unless
        // they have one already or none was ever set.
        final g = store.byId(gear.id);
        if (g == null || g.zeros.isEmpty || g.zeros.containsKey(b)) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('$b fitted — set its zero point?'),
              action: SnackBarAction(
                label: 'Set',
                onPressed: () => showGrinderDialog(context, grinder: g),
              ),
            ),
          );
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
          // Brand and model in the look of the card titles ("PREShot").
          PrefixedTitle(
            key: const ValueKey('gear-title'),
            prefix: gear.brand,
            title: gear.displayName,
            active: true,
            maxLines: 2,
            stacked: true,
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
          // Editing (and the photo) is a long press on the piece.
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../services/grinder_store.dart';
import '../../services/shot_setup.dart';
import '../../theme/app_theme.dart';
import '../settings/my_setup_dialogs.dart';
import 'inline_picker.dart';

// Screens built without a grinder store (tests, previews) simply show no
// grinder — the same as having none.
GrinderStore? _watchStore(BuildContext context) {
  try {
    return context.watch<GrinderStore>();
  } on ProviderNotFoundException {
    return null;
  }
}

// Grinder choice at the right end of the grind row (Pre-Shot and
// Pre-Brew): the chosen grinder's name, styled like the other values in
// the card; tapping it opens the list below the row. With exactly one
// grinder it just names it — nothing to choose.
class GrinderPill extends StatelessWidget {
  const GrinderPill({super.key, required this.open, required this.onTap});

  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final grinders = _watchStore(context)?.grinders ?? const [];
    if (grinders.isEmpty) return const SizedBox.shrink();
    final chosen = context.select<ShotSetup, Grinder?>((s) => s.grinder);
    final choosable = grinders.length > 1 && onTap != null;
    final colors = context.colors;
    return InkWell(
      key: const ValueKey('grinder-pill'),
      onTap: choosable ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              chosen?.name ?? 'Grinder',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: chosen == null
                    ? colors.textTertiary
                    : colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 19,
            child: choosable
                ? Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 19,
                    color: colors.textTertiary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The open grinder list; [onChosen] closes it.
class GrinderPickerList extends StatelessWidget {
  const GrinderPickerList({super.key, required this.onChosen});

  final VoidCallback onChosen;

  static double heightFor(BuildContext context) =>
      InlinePicker.heightFor(context.read<GrinderStore>().grinders.length);

  @override
  Widget build(BuildContext context) {
    final grinders = context.watch<GrinderStore>().grinders;
    final chosen = context.select<ShotSetup, Grinder?>((s) => s.grinder);
    final colors = context.colors;
    return InlinePicker<Grinder>(
      items: grinders,
      leading: (_) =>
          Icon(Icons.blender_outlined, size: 20, color: colors.textSecondary),
      title: (g) => g.name,
      detail: (g) => g.activeBurrs,
      searchText: (g) => '${g.name} ${g.burrs.join(' ')}',
      isSelected: (g) => g.id == chosen?.id,
      onSelected: (g) {
        context.read<ShotSetup>().setGrinder(g.id);
        onChosen();
      },
      onAdd: () async {
        final setup = context.read<ShotSetup>();
        final added = await showGrinderDialog(context);
        if (added != null) {
          setup.setGrinder(added.id);
          onChosen();
        }
      },
      addTooltip: 'Add grinder',
      emptyText: 'No grinders yet. Tap + to add one.',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/gear.dart';
import '../../services/gear_store.dart';
import '../../services/shot_setup.dart';
import '../../widgets/value_select_row.dart';
import '../settings/gear_dialogs.dart';

// The brew chain row below the grind row (Pre-Shot and Pre-Brew): which
// gear this brew is made with. Replaces the grinder choice — the chain's
// grinder goes on the shot, together with all its pieces ("Brewed with").
// Screens built without a gear store (tests, previews) show no row.

GearStore? _watchStore(BuildContext context) {
  try {
    return context.watch<GearStore>();
  } on ProviderNotFoundException {
    return null;
  }
}

List<ValueOption<String>> _options(GearStore store) => [
  for (final c in store.chains)
    ValueOption(
      value: c.id,
      title: c.name,
      subtitle: [for (final g in store.gearOf(c)) g.displayName].join(', '),
    ),
];

/// Height of the open list, for the card's extra height.
double chainListHeight(BuildContext context) {
  try {
    return ValueSelectRow.listHeightFor(
      _options(context.read<GearStore>()),
      action: true,
    );
  } on ProviderNotFoundException {
    return 0;
  }
}

class ChainSelectRow extends StatelessWidget {
  const ChainSelectRow({
    super.key,
    required this.open,
    required this.onToggle,
    required this.onClose,
    this.isLast = false,
    this.enabled = true,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final bool isLast;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final store = _watchStore(context);
    if (store == null) return const SizedBox.shrink();
    final chosen = context.select<ShotSetup, BrewChain?>((s) => s.chain);
    return ValueSelectRow<String>(
      key: const ValueKey('chain-row'),
      // Nearly the full card width, like the bean and profile lists.
      listIndent: 0,
      icon: Icons.link,
      label: 'Chain',
      valueText: chosen?.name,
      placeholder: 'Select brew chain',
      isLast: isLast,
      enabled: enabled,
      dimValue: !enabled,
      open: open,
      onToggle: onToggle,
      onClose: onClose,
      value: chosen?.id,
      options: _options(store),
      onChanged: (id) {
        HapticFeedback.selectionClick();
        context.read<ShotSetup>().setChain(id);
        onClose();
      },
      action: ValueSelectAction('New brew chain', () async {
        // Dialog first: closing the list would unmount this context.
        final setup = context.read<ShotSetup>();
        final added = await showChainDialog(context);
        if (added != null) setup.setChain(added.id);
        onClose();
      }),
      emptyText: 'No brew chains yet.',
    );
  }
}

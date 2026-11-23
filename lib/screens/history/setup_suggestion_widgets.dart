import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/gear.dart';
import '../../services/gear_store.dart';
import '../../services/setup_suggestion.dart';
import '../../theme/app_theme.dart';
import '../live/grind_from_zero.dart';

/// "Fazenda Matão · 14 g · 3.8 · Niche Zero" — what a suggestion would
/// write, in one line (the grind read as on its grinder).
class SetupSummary extends StatefulWidget {
  const SetupSummary({
    super.key,
    required this.suggestion,
    this.style,
    this.maxLines = 1,
  });

  final SetupSuggestion suggestion;
  final TextStyle? style;
  final int maxLines;

  @override
  State<SetupSummary> createState() => _SetupSummaryState();
}

class _SetupSummaryState extends State<SetupSummary> {
  // Asked once per bean, not on every rebuild.
  late Future<Bean?> _bean = _load();

  Future<Bean?> _load() {
    final id = widget.suggestion.beanId;
    return id == null
        ? Future<Bean?>.value()
        : context.read<AppDatabase>().beanById(id);
  }

  @override
  void didUpdateWidget(SetupSummary old) {
    super.didUpdateWidget(old);
    if (old.suggestion.beanId != widget.suggestion.beanId) _bean = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Bean?>(
      future: _bean,
      builder: (context, snap) => Text(
        setupSummaryText(context, widget.suggestion, bean: snap.data),
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        style:
            widget.style ??
            TextStyle(color: context.colors.textSecondary, fontSize: 12),
      ),
    );
  }
}

String setupSummaryText(BuildContext context, SetupSuggestion s, {Bean? bean}) {
  GearStore? store;
  try {
    store = context.read<GearStore>();
  } on ProviderNotFoundException {
    store = null;
  }
  final gear = s.grinder == null || store == null
      ? null
      : store
            .ofType(GearType.grinder)
            .where((g) => g.model == s.grinder)
            .firstOrNull;
  final grinder = gear == null ? null : grinderFromGear(gear);
  final dose = s.doseGrams;
  return [
    bean?.name,
    if (dose != null)
      '${dose % 1 == 0 ? dose.toStringAsFixed(0) : dose.toStringAsFixed(1)} g',
    grindDisplayText(s.grindSize, grinder),
    s.grinder,
  ].whereType<String>().where((t) => t.isNotEmpty).join(' · ');
}

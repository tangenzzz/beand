import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'bean_stock.dart';
import 'freshness.dart';

class BeanGroup {
  BeanGroup(this.roaster, this.beans);

  // null = beans without a roaster, listed last.
  final String? roaster;
  final List<Bean> beans;
}

int _compareText(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

// Grouped by roaster (A–Z, case-insensitive), then by name (A–Z). Roasters
// that differ only in spelling end up in one group.
List<BeanGroup> groupBeansByRoaster(Iterable<Bean> beans) {
  final byKey = <String, BeanGroup>{};
  final noRoaster = <Bean>[];
  for (final bean in beans) {
    final roaster = _clean(bean.roaster);
    if (roaster == null) {
      noRoaster.add(bean);
      continue;
    }
    byKey
        .putIfAbsent(roaster.toLowerCase(), () => BeanGroup(roaster, []))
        .beans
        .add(bean);
  }
  final groups = byKey.values.toList()
    ..sort((a, b) => _compareText(a.roaster!, b.roaster!));
  if (noRoaster.isNotEmpty) groups.add(BeanGroup(null, noRoaster));
  for (final g in groups) {
    g.beans.sort((a, b) => _compareText(a.name, b.name));
  }
  return groups;
}

// What the bean was roasted for — the lowercase value is stored
// (Beans.roastedFor), the label is displayed.
const roastedForOptions = [
  (value: 'filter', label: 'Filter'),
  (value: 'espresso', label: 'Espresso'),
  (value: 'omni', label: 'Omni'),
];

String? roastedForLabel(String? value) {
  for (final option in roastedForOptions) {
    if (option.value == value) return option.label;
  }
  return null;
}

// "Kenya · Washed" (without type and without "Roasted for" — both are
// deliberately left out of the list; empty if both are missing).
String beanSubtitle(Bean bean) => [
  _clean(bean.country),
  _clean(bean.processing),
].whereType<String>().join(' · ');

// Days since the roast date (by calendar day), null without a roast date.
int? daysSinceRoast(Bean bean, [DateTime? now]) {
  final roast = bean.roastDate;
  if (roast == null) return null;
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(roast.year, roast.month, roast.day)).inDays;
  return days < 0 ? 0 : days;
}

// Days for the freshness ring: from the thaw date if the bean was thawed,
// otherwise from the roast date. null without a start date. (Frozen beans
// show the ice ring instead, see BeanRow.)
int? daysSinceFreshnessStart(Bean bean, [DateTime? now]) {
  final start = bean.thawedDate ?? bean.roastDate;
  if (start == null) return null;
  final today = now ?? DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(start.year, start.month, start.day)).inDays;
  return days < 0 ? 0 : days;
}

class BeanGroupHeader extends StatelessWidget {
  const BeanGroupHeader(this.roaster, {super.key});

  final String? roaster;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        14,
        AppSpacing.dividerInset,
        4,
      ),
      child: Text(
        (roaster ?? 'No roastery').toUpperCase(),
        style: TextStyle(
          color: context.colors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// Row in the bean list and picker sheet: photo (with remaining-amount ring,
// see bean_stock.dart), name, subtitle, days since roasting.
class BeanRow extends StatelessWidget {
  const BeanRow({
    super.key,
    required this.bean,
    required this.onTap,
    this.selected = false,
    this.usage = const {},
    this.onPhotoLongPress,
    this.onFrozenLongPress,
    this.onFreshLongPress,
  });

  final Bean bean;
  final VoidCallback onTap;
  // Only in the bean list: long-press on the photo = empty/full again, on
  // the snowflake = thaw, on the freshness ring = freeze.
  final VoidCallback? onPhotoLongPress;
  final VoidCallback? onFrozenLongPress;
  final VoidCallback? onFreshLongPress;
  final bool selected;
  // Grams used per bean (AppDatabase.watchBeanUsage).
  final Map<int, double> usage;

  @override
  Widget build(BuildContext context) {
    final days = daysSinceFreshnessStart(bean);
    final subtitle = beanSubtitle(bean);
    final settings = context.watch<AppSettings>();
    final showRing = settings.showFreshnessRing;
    final showStock = settings.showBeanStock;
    final emptied = bean.emptiedAt != null;
    // Marked empty by hand: like used up (remaining 0 → photo only).
    final remaining = showStock
        ? (emptied ? 0.0 : beanRemaining(bean, usage))
        : null;
    // Used up: ring empty, freshness display disappears.
    final empty = emptied || (remaining != null && remaining < 0.5);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dividerInset,
          vertical: 10,
        ),
        child: Row(
          children: [
            _LongPress(
              onLongPress: onPhotoLongPress,
              child: Opacity(
                // Make the empty mark visible, even without a remaining amount.
                opacity: emptied ? 0.4 : 1,
                child: showStock
                    ? BeanStockAvatar(
                        photoPath: bean.photoPath,
                        remaining: remaining,
                        total: bean.weightGrams,
                      )
                    : BeanThumbnail(
                        path: bean.photoPath,
                        size: 52,
                        circle: true,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bean.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, color: context.colors.accent, size: 18),
            ],
            if (empty)
              const SizedBox.shrink()
            else if (bean.isFrozen) ...[
              const SizedBox(width: 10),
              _LongPress(
                onLongPress: onFrozenLongPress,
                child: showRing
                    ? const FrozenRing()
                    : Icon(Icons.ac_unit, color: context.colors.ice, size: 18),
              ),
            ] else if (days != null) ...[
              const SizedBox(width: 10),
              _LongPress(
                onLongPress: onFreshLongPress,
                child: showRing
                    ? FreshnessRing(days: days)
                    : Text(
                        '$days d',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Long-press on part of the row; without a handler just the child (then
// the whole row gets the tap).
class _LongPress extends StatelessWidget {
  const _LongPress({required this.onLongPress, required this.child});

  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final action = onLongPress;
    if (action == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        action();
      },
      child: child,
    );
  }
}

class BeanThumbnail extends StatelessWidget {
  const BeanThumbnail({
    super.key,
    required this.path,
    required this.size,
    this.circle = false,
    this.radius,
  });

  final String? path;
  final double size;
  // Circle instead of rounded square; [radius] overrides the rounding.
  final bool circle;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        circle ? size / 2 : radius ?? size / 4.5,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => const _ThumbnailPlaceholder(),
              )
            : const _ThumbnailPlaceholder(),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.bg,
      child: Center(
        child: Icon(
          Icons.eco_outlined,
          color: context.colors.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}

// Selection pill (type in the form, filter options).

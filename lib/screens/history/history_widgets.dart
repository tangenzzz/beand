import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../widgets/machine_badge.dart';

import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/app_settings.dart';
import '../../services/profile_images.dart';
import '../../theme/app_theme.dart';
import '../live/grind_from_zero.dart';
import 'history_logic.dart';

// [fallback] applies when the machine does not provide a profile color —
// callers pass a token for it.
Color parseHexColor(String? hex, {required Color fallback}) {
  if (hex == null || hex.isEmpty) return fallback;
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

// First photo in the list that actually still exists. Paths point into the
// app folder, but the file may have been deleted or (after a restore)
// redirected.
File? _firstExistingPhoto(List<String?> paths) {
  for (final path in paths) {
    if (path == null || path.isEmpty) continue;
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

// Round photo (local copy, profile color as fallback) with a machine marker
// bottom right. Whether it shows the profile or the bean is decided by
// Settings → History. The marker icons are provisional.
class ShotAvatar extends StatelessWidget {
  const ShotAvatar({
    super.key,
    required this.shot,
    this.bean,
    this.size = 48,
    this.badge = 17,
    this.ringColor,
  });

  final Shot shot;

  /// The shot's bean, if one is set — only for its photo. Without it the
  /// profile photo is used, even if bean is selected.
  final Bean? bean;
  final double size;
  final double badge;

  /// Color of the ring around the machine badge — defaults to the color of
  /// the card the circle sits on.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final machine = ShotMachine.fromKey(shot.machine);
    // The image that came with the import — and if the shot has none, the
    // current profile image (see ProfileImages). Without this fallback
    // GaggiMate shots would never have a photo, and a photo chosen later
    // would be missing on old shots.
    final profilePath =
        shot.profileImagePath ??
        context.watch<ProfileImages?>()?.pathFor(
          machine: shot.machine,
          profileName: shot.profileName,
        );
    // Which of the two photos is wanted is in the settings; if the wanted
    // one is missing, the other is used — an empty circle helps nobody.
    // Without AppSettings in the tree (widgets tested in isolation) the
    // default "profile" applies.
    final wantsBean =
        context.watch<AppSettings?>()?.historyAvatar == HistoryAvatar.bean;
    final file = _firstExistingPhoto(
      wantsBean
          ? [bean?.photoPath, profilePath]
          : [profilePath, bean?.photoPath],
    );
    // Fallback letter matching the chosen source.
    final letter = ((wantsBean ? bean?.name : null) ?? shot.profileName ?? '?')
        .trim();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Container(
              width: size,
              height: size,
              color: parseHexColor(shot.profileColor, fallback: colors.divider),
              alignment: Alignment.center,
              child: file != null
                  ? Image.file(
                      file,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : Text(
                      letter.isEmpty
                          ? '?'
                          : letter.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.32),
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: MachineBadge(
              glyph: machine.glyph,
              color: machine.color,
              size: badge,
              ringColor: ringColor ?? context.colors.card,
            ),
          ),
        ],
      ),
    );
  }
}

// Five stars. Tappable with [onChanged] (tapping the current rating again
// resets it to 0).
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.size = 12,
    this.gap = 1,
    this.tapPadding = 10,
    this.onChanged,
  });

  final int rating;
  final double size;
  final double gap;

  /// Space above and below the stars that also counts as tap target.
  /// Smaller in tight cards so the row does not get needlessly tall.
  final double tapPadding;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final editable = onChanged != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          if (editable)
            Semantics(
              button: true,
              label: '$i star${i == 1 ? '' : 's'}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged!(i == rating ? 0 : i),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: gap / 2 + 3,
                    vertical: tapPadding,
                  ),
                  child: _star(context, i <= rating),
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.only(left: i == 1 ? 0 : gap),
              child: _star(context, i <= rating),
            ),
      ],
    );
  }

  Widget _star(BuildContext context, bool filled) => Icon(
    Icons.star_rounded,
    size: size,
    // Empty stars in the hint color, not the line color: on a light
    // background lines (1.4:1) would be practically invisible.
    color: filled ? context.colors.star : context.colors.textTertiary,
  );
}

// Grind/dose/yield as icon + value for the second line of the history row.
// Grind and dose icons are the same as in the pre-shot card
// (Icons.blur_on / Icons.balance).
// With [fromZero] the grind also says how far it was from the zero point
// of its day: "3.2 (+2.7)" (Settings → History).
List<InlineSpan> _metricSpans(
  BuildContext context,
  Shot shot, {
  bool fromZero = false,
}) {
  final valueStyle = TextStyle(
    color: context.colors.textSecondary,
    fontSize: 11.5,
  );
  final iconColor = context.colors.textTertiary;
  var first = true;
  Iterable<InlineSpan> item(IconData icon, String value) sync* {
    if (!first) yield const TextSpan(text: '   ');
    first = false;
    yield WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(icon, size: 11, color: iconColor),
    );
    yield TextSpan(text: ' $value', style: valueStyle);
  }

  return [
    if (shot.grindSize != null)
      ...item(Icons.blur_on, switch (fromZero
          ? shotGrindFromZero(shot)
          : null) {
        final v? => '${shot.grindSize!} (${fromZeroText(v)})',
        null => shot.grindSize!,
      }),
    if (shot.doseGrams != null)
      ...item(Icons.balance, '${grams(shot.doseGrams!)} g'),
    if (shot.finalWeight != null)
      ...item(Icons.water_drop_outlined, '${grams(shot.finalWeight!)} g'),
  ];
}

// Row of the history and the comparison picker: profile photo, bean +
// roaster on top, below profile · grind/dose/yield; on the right time +
// stars (or a check mark in the picker).
class ShotRow extends StatelessWidget {
  const ShotRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showCheckColumn = false,
    this.selectionMode = false,
  });

  final ShotEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // Only in the comparison picker: a check mark on the selected row instead
  // of time/stars.
  final bool selected;
  final bool showCheckColumn;
  // Multi-select (delete): every row shows a selection circle.
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final shot = entry.shot;
    final bean = entry.bean;
    final profile = (shot.profileName ?? '').trim();
    // Without a bean (e.g. shots backfilled from the machine history) the
    // profile is shown in the first line.
    final first = bean?.name ?? (profile.isEmpty ? 'Shot' : profile);
    final roaster = bean?.roaster?.trim();
    final metricSpans = _metricSpans(
      context,
      shot,
      fromZero: _showGrindFromZero(context),
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selectionMode && selected
            ? context.colors.textPrimary.withValues(alpha: 0.06)
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dividerInset,
          vertical: 10,
        ),
        child: Row(
          children: [
            ShotAvatar(shot: shot, bean: bean),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // Bean and roaster split the row in half
                      // (previously 1:3 — only 8-9 characters of the bean
                      // name were left).
                      Flexible(
                        flex: 1,
                        child: Text(
                          first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (bean != null &&
                          roaster != null &&
                          roaster.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 1,
                          child: Text(
                            roaster,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (bean != null && profile.isNotEmpty)
                        Flexible(
                          child: Text(
                            profile,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      if (metricSpans.isNotEmpty)
                        Text.rich(
                          TextSpan(
                            text: bean != null && profile.isNotEmpty
                                ? '   '
                                : '',
                            children: metricSpans,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selectionMode)
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: selected
                    ? context.colors.accent
                    : context.colors.textTertiary,
              )
            else if (showCheckColumn)
              SizedBox(
                width: 20,
                child: selected
                    ? Icon(Icons.check, color: context.colors.accent, size: 20)
                    : null,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeLabel(shot.timestamp),
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  StarRating(rating: shot.rating ?? 0, size: 10),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DayGroupHeader extends StatelessWidget {
  const DayGroupHeader(this.label, {super.key});

  final String label;

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
        label,
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

// Flat, lazily built list "day header, rows, day header, ..." in the look
// of the bean list (one card), but as slivers: the history grows with
// every shot.
class ShotListSliver extends StatelessWidget {
  const ShotListSliver({
    super.key,
    required this.groups,
    required this.onTap,
    this.onLongPress,
    this.selectedId,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.showCheckColumn = false,
    this.tileColor,
    this.rounded = true,
  });

  final List<ShotDayGroup> groups;
  final ValueChanged<ShotEntry> onTap;
  final ValueChanged<ShotEntry>? onLongPress;
  // Single select (comparison sheet) or multi-select (delete).
  final int? selectedId;
  final Set<int> selectedIds;
  final bool selectionMode;
  final bool showCheckColumn;
  final Color? tileColor;
  // Card with rounded corners (history) or borderless (picker sheet).
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      // Divider before every day header except the very first — not
      // between individual brews of the same day.
      items.add((g.label, gi > 0));
      items.addAll(g.entries);
    }
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isFirst = index == 0;
        final isLast = index == items.length - 1;
        final Widget child;
        if (item is (String, bool)) {
          final (label, showDivider) = item;
          child = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDivider)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Divider(
                    height: 1,
                    indent: AppSpacing.dividerInset,
                    endIndent: AppSpacing.dividerInset,
                    color: context.colors.divider,
                  ),
                ),
              DayGroupHeader(label),
            ],
          );
        } else {
          final entry = item as ShotEntry;
          child = ShotRow(
            entry: entry,
            onTap: () => onTap(entry),
            onLongPress: onLongPress == null ? null : () => onLongPress!(entry),
            selected:
                entry.shot.id == selectedId ||
                selectedIds.contains(entry.shot.id),
            selectionMode: selectionMode,
            showCheckColumn: showCheckColumn,
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: tileColor ?? context.colors.card,
            borderRadius: rounded
                ? BorderRadius.vertical(
                    top: isFirst
                        ? const Radius.circular(AppRadii.tile)
                        : Radius.zero,
                    bottom: isLast
                        ? const Radius.circular(AppRadii.tile)
                        : Radius.zero,
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 6 : 0),
            child: child,
          ),
        );
      },
    );
  }
}

// Notes field of a shot: saves debounced while typing and immediately on
// leaving the field/screen. [initial] only applies on first build, so a
// stream update does not overwrite the text under the cursor.
class ShotNotesField extends StatefulWidget {
  const ShotNotesField({
    super.key,
    required this.shotId,
    required this.initial,
    this.expands = false,
  });

  final int shotId;
  final String? initial;
  // Fills the available height (post-shot card) instead of growing.
  final bool expands;

  @override
  State<ShotNotesField> createState() => _ShotNotesFieldState();
}

class _ShotNotesFieldState extends State<ShotNotesField> {
  // Fetch in initState already: context.read is no longer allowed in
  // dispose(), but the note still has to be saved there.
  late final AppDatabase _db;
  late final _controller = TextEditingController(text: widget.initial ?? '');
  final _focus = FocusNode();
  Timer? _timer;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _db = context.read<AppDatabase>();
    _focus.addListener(() {
      if (!_focus.hasFocus) _flush();
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _flush();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _flush() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _db.setShotNotes(widget.shotId, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: _changed,
      minLines: widget.expands ? null : 1,
      maxLines: widget.expands ? null : 8,
      expands: widget.expands,
      textAlignVertical: TextAlignVertical.top,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 13,
        height: 1.45,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.only(top: 6),
        hintText: 'Add a note…',
        hintStyle: TextStyle(color: context.colors.textTertiary, fontSize: 13),
      ),
    );
    // In the growing variant (post-shot card) the surrounding screen closes
    // the keyboard; only here an explicit exit is needed, because otherwise
    // the field stays open inside the scroll content.
    if (widget.expands) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_focused)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _focus.unfocus,
              icon: const Icon(Icons.check, size: 15),
              label: const Text('Done'),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Confirmation before deleting. Deleted shots do not come back from the
// machine.
Future<bool> confirmDeleteShots(BuildContext context, int count) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.colors.card,
      title: Text(count == 1 ? 'Delete this shot?' : 'Delete $count shots?'),
      content: Text(
        'They are removed from the app for good and will not be imported from the machine again.',
        style: TextStyle(color: context.colors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: context.colors.danger),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

bool _showGrindFromZero(BuildContext context) {
  try {
    return context.select<AppSettings, bool>((s) => s.showGrindFromZero);
  } on ProviderNotFoundException {
    return false;
  }
}

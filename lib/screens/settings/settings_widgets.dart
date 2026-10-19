import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SettingsEntry {
  const SettingsEntry({
    this.icon,
    this.iconWidget,
    required this.title,
    required this.builder,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;

  /// A custom icon instead of [icon], e.g. the bean from the tab bar.
  final Widget? iconWidget;
  final String title;
  final WidgetBuilder builder;
}

// The same three text levels on every settings page:
//   1. [SettingsGroupLabel] — small uppercase heading of a block, the same
//      style as the "PRE" of the shot cards.
//   2. [SettingsTitle] — 15 px, the name of a row or section ("Provider",
//      "API key", a switch). Dropdown rows use [settingsValueLabelSize] and
//      [SettingsTitle]'s color so they read the same.
//   3. [SettingsText] — 13 px secondary: explanations and status lines.
//
// A settings page is ONE card. Its children are blocks, and only between
// blocks sits a divider ([SettingsCard] puts it there); inside a block
// ([SettingsGroup]) only spacing separates the rows. Multiple cards per page
// only when explicitly wanted.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.dividers = true});

  final List<Widget> children;

  /// False for a page whose blocks carry their own separation (the shelf
  /// boards of My Coffee Desk).
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadii.tile),
      clipBehavior: Clip.antiAlias,
      child: Column(
        // Without this the column centers narrow children, and two sections
        // of the same card would be indented differently.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (dividers && i < children.length - 1) const SettingsDivider(),
          ],
        ],
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: AppSpacing.dividerInset,
    endIndent: AppSpacing.dividerInset,
    color: context.colors.divider,
  );
}

// One block of a settings card: optional heading, then the rows without
// lines between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.label,
    this.icon,
    this.trailing,
    required this.children,
  });

  final String? label;
  final IconData? icon;

  /// At the far right of the heading, e.g. a "+" or "Scan".
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        SettingsGroupLabel(label!, icon: icon, trailing: trailing),
      ...children,
    ],
  );
}

// Level 1: small uppercase heading of a block.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(
    this.text, {
    super.key,
    this.icon,
    this.leading,
    this.count,
    this.trailing,
  });

  final String text;
  final IconData? icon;

  /// A custom icon instead of [icon] (e.g. an SVG line icon), 17 px.
  final Widget? leading;

  /// Right after the label in a lighter tone, e.g. how many entries.
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = settingsGroupLabelStyle(context);
    final label = Text.rich(
      TextSpan(
        text: text.toUpperCase(),
        children: [
          if (count != null)
            TextSpan(
              text: '  $count',
              style: TextStyle(color: colors.textTertiary),
            ),
        ],
      ),
      style: style,
    );
    // With an action at the right the row is as tall as its tap target;
    // the padding shrinks so the label sits at the same height either way.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        trailing == null ? 16 : 4,
        trailing == null ? AppSpacing.dividerInset : 4,
        trailing == null ? 4 : 0,
      ),
      child: Row(
        children: [
          if (leading != null || icon != null) ...[
            SizedBox.square(
              dimension: 17,
              child:
                  leading ?? Icon(icon, size: 17, color: colors.textSecondary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: label),
          ?trailing,
        ],
      ),
    );
  }
}

/// Level 1 for places that lay out their own padding (the connection
/// cards).
TextStyle settingsGroupLabelStyle(BuildContext context) => TextStyle(
  color: context.colors.textSecondary,
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.1,
);

// Level 2 with content below it: "API key" + field, "Theme" + choice.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    this.info,
    required this.child,
  });

  /// Null where the child already says it (e.g. a labelled button).
  final String? title;
  final String? info;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.dividerInset,
      12,
      AppSpacing.dividerInset,
      12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          SettingsTitle(title!, info: info),
          const SizedBox(height: 8),
        ],
        child,
      ],
    ),
  );
}

// Level 3: explanations and status lines.
class SettingsText extends StatelessWidget {
  const SettingsText(this.text, {super.key, this.color, this.maxLines});

  final String text;
  final Color? color;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(
      color: color ?? context.colors.textSecondary,
      fontSize: 13,
      height: 1.4,
    ),
  );
}

/// Label size of a [ValueSelectRow] on a settings page — level 2, like
/// every other row title there.
const settingsValueLabelSize = 15.0;

// A switch row: optional icon, title with ⓘ, switch on the right. Only the
// switch toggles (as with AppSwitchTile), and the title starts at the same
// x as in [SettingsRow], so both can share a block.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.info,
    this.infoExtra,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String title;
  final String? info;
  final Widget? infoExtra;
  final bool value;

  /// Null grays the row out.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.dividerInset, 4, 8, 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: context.colors.textSecondary),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: SettingsTitle(
              title,
              info: info,
              infoExtra: infoExtra,
              color: enabled ? null : context.colors.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// A tappable row in a card: icon, title, optional second line.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.iconWidget,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    this.danger = false,
    this.info,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;

  /// A custom icon instead of [icon]; color and size come from the
  /// surrounding [IconTheme], as with [icon].
  final Widget? iconWidget;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;

  /// Highlights the row in red — for actions that overwrite data.
  final bool danger;

  /// Explanation behind the ⓘ at the title (see [SettingsInfo]).
  final String? info;

  @override
  Widget build(BuildContext context) {
    final titleColor = danger
        ? context.colors.danger
        : context.colors.textPrimary;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dividerInset,
            vertical: 16,
          ),
          child: Row(
            children: [
              IconTheme.merge(
                data: IconThemeData(
                  color: danger ? titleColor : context.colors.textSecondary,
                  size: 20,
                ),
                child: iconWidget ?? Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsTitle(title, info: info, color: titleColor),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: context.colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.colors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A row from a choice where exactly one applies: check mark on the right
// instead of an arrow. The selected row is NOT highlighted — the same rule
// as in the app's dropdown lists.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.info,
    this.compact = false,
  });

  /// Either [icon] or [leading] — [leading] for custom icons that are not
  /// [IconData] (e.g. the bean from the wordmark).
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Explanation behind the ⓘ at the title (see [SettingsInfo]).
  final String? info;

  /// Smaller and tighter: options below a dropdown row that should stand
  /// apart from it (e.g. thumbnail in the history settings).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 20.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.dividerInset,
          vertical: compact ? 9 : 16,
        ),
        child: Row(
          children: [
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: Center(
                child:
                    leading ??
                    Icon(
                      icon,
                      color: context.colors.textSecondary,
                      size: iconSize,
                    ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsTitle(title, info: info, fontSize: compact ? 13 : 15),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The space stays even when empty, so the rows do not wrap at
            // different widths.
            SizedBox(
              width: iconSize,
              child: selected
                  ? Icon(
                      Icons.check,
                      color: context.colors.accent,
                      size: iconSize,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// Card with entries that each open a subpage — one block: icon and arrow
// already set the rows apart, lines would only add noise.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.entries});

  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        SettingsGroup(
          children: [
            for (final entry in entries)
              SettingsRow(
                icon: entry.icon,
                iconWidget: entry.iconWidget,
                title: entry.title,
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: entry.builder)),
              ),
          ],
        ),
      ],
    );
  }
}

// Explanation text as the first row of a card.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.dividerInset,
      vertical: 16,
    ),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );
}

// Page of a settings entry that has no options yet.
class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'Nothing to configure yet.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ),
    );
  }
}

// Small ⓘ after a title: tapping (or long-pressing) shows the explanation
// as a bubble — this keeps the settings cards tidy. Status messages do NOT
// belong here, they stay visible. The tap is intercepted so the row
// underneath (switch, action) does not trigger as well.
//
// Custom bubble instead of a Tooltip: a second tap on the ⓘ closes it
// again, as does tapping elsewhere. The Tooltip closed on tapping the ⓘ and
// immediately reopened. Applies to all ⓘ in the app.
class SettingsInfo extends StatefulWidget {
  const SettingsInfo(this.text, {super.key, this.extra, this.heading});

  final String text;

  /// Bold first line above the text (e.g. Nostr ⓘ in Settings → Sync).
  final String? heading;

  /// Additionally below the text, e.g. the color legend of the freshness ring.
  final Widget? extra;

  @override
  State<SettingsInfo> createState() => _SettingsInfoState();
}

class _SettingsInfoState extends State<SettingsInfo> {
  final _portal = OverlayPortalController();

  // ⓘ and bubble belong together: tapping either of them is not
  // "elsewhere".
  late final Object _group = Object();

  void _toggle() {
    if (!_portal.isShowing) Feedback.forTap(context);
    setState(_portal.toggle);
  }

  void _close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  Widget _bubble(BuildContext overlayContext) {
    final colors = context.colors;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(overlayContext);
    final origin = box.localToGlobal(Offset.zero);
    final below = origin.dy + box.size.height + 4;
    // Not enough space below: above the ⓘ.
    final above = screen.height - below < 220;
    final style = TextStyle(
      color: colors.textSecondary,
      fontSize: 12,
      height: 1.45,
    );
    return Positioned(
      left: 24,
      right: 24,
      top: above ? null : below,
      bottom: above ? screen.height - origin.dy + 4 : null,
      child: TapRegion(
        groupId: _group,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.nav,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.divider),
            ),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (widget.heading != null)
                    TextSpan(
                      text: '${widget.heading}\n',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  TextSpan(text: widget.text),
                  if (widget.extra != null) ...[
                    const TextSpan(text: '\n\n'),
                    WidgetSpan(child: widget.extra!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TapRegion(
      groupId: _group,
      onTapOutside: (_) => _close(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _bubble,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onLongPress: () {
            if (!_portal.isShowing) _toggle();
          },
          // Kept flat so the ⓘ does not make the row taller.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// Title of a settings row with an optional ⓘ right after it.
class SettingsTitle extends StatelessWidget {
  const SettingsTitle(
    this.title, {
    super.key,
    this.info,
    this.infoExtra,
    this.infoHeading,
    this.color,
    this.fontSize = 15,
  });

  final String title;
  final String? info;
  final Widget? infoExtra;
  final String? infoHeading;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      style: TextStyle(
        color: color ?? context.colors.textPrimary,
        fontSize: fontSize,
      ),
    );
    if (info == null) return text;
    return Row(
      children: [
        Flexible(child: text),
        // The ⓘ has a larger tap area; pull it back a bit on the left so it
        // visually sits close to the title.
        Transform.translate(
          offset: const Offset(-2, 0),
          child: SettingsInfo(info!, extra: infoExtra, heading: infoHeading),
        ),
      ],
    );
  }
}

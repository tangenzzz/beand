import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

// The one selection pattern of the app: a value row ("Bean  Superfreak ⌄")
// whose choices fold out INLINE right below it — no overlay, sheet or
// dialog; the content below slides down. Used for every pick list (profile,
// bean, grinder, recipe, settings choices). Numeric values (dose, grind …)
// use the same closed row with their own panel (the ruler) via
// [ValueSelectRow.custom].
//
// Only one list is open at a time: rows either take [open]/[onToggle] from
// their screen (the shot cards, which also need the extra height), or share
// a [ValueSelectGroup]; without either, a row keeps its own state. A tap
// outside closes the open list; scrolling the screen keeps it open.

/// One choice in a [ValueSelectList].
class ValueOption<T> {
  const ValueOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.leading,
  });

  final T value;
  final String title;
  final String? subtitle;

  /// E.g. the photo circle of a bean or profile.
  final Widget? leading;
}

/// The optional last entry of a list, e.g. "+ New bean".
class ValueSelectAction {
  const ValueSelectAction(this.label, this.onTap, {this.icon = Icons.add});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// Keeps one open row per screen or card.
class ValueSelectController extends ChangeNotifier {
  Object? _open;

  bool isOpen(Object key) => _open == key;

  void toggle(Object key) {
    _open = _open == key ? null : key;
    notifyListeners();
  }

  void close([Object? key]) {
    if (_open == null || (key != null && _open != key)) return;
    _open = null;
    notifyListeners();
  }
}

/// Shares one [ValueSelectController] with the rows below it.
class ValueSelectGroup extends StatefulWidget {
  const ValueSelectGroup({super.key, required this.child});

  final Widget child;

  static ValueSelectController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ValueSelectScope>()?.notifier;

  @override
  State<ValueSelectGroup> createState() => _ValueSelectGroupState();
}

class _ValueSelectGroupState extends State<ValueSelectGroup> {
  final _controller = ValueSelectController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ValueSelectScope(notifier: _controller, child: widget.child);
}

class _ValueSelectScope extends InheritedNotifier<ValueSelectController> {
  const _ValueSelectScope({required super.notifier, required super.child});
}

class ValueSelectRow<T> extends StatefulWidget {
  /// A pick list: [options], the current [value], [onChanged].
  const ValueSelectRow({
    super.key,
    required this.label,
    required List<ValueOption<T>> this.options,
    required this.value,
    required ValueChanged<T> this.onChanged,
    this.icon,
    this.valueText,
    this.placeholder = '—',
    this.action,
    this.emptyText = 'Nothing here yet.',
    this.listPlaceholder,
    this.footer,
    this.trailing,
    this.isLast = false,
    this.enabled = true,
    this.dimValue = false,
    this.open,
    this.onToggle,
    this.onClose,
    this.labelWidth = defaultLabelWidth,
    this.horizontalPadding = 0,
    this.listIndent,
    this.labelColor,
    this.labelSize = 13,
  }) : panel = null;

  /// The same closed row with an own [panel] (e.g. the ruler for numbers).
  const ValueSelectRow.custom({
    super.key,
    required this.label,
    required this.valueText,
    required Widget this.panel,
    this.icon,
    this.placeholder = '—',
    this.trailing,
    this.isLast = false,
    this.enabled = true,
    this.dimValue = false,
    this.open,
    this.onToggle,
    this.onClose,
    this.labelWidth = defaultLabelWidth,
    this.horizontalPadding = 0,
    this.listIndent,
    this.labelColor,
    this.labelSize = 13,
  }) : options = null,
       value = null,
       onChanged = null,
       action = null,
       emptyText = '',
       listPlaceholder = null,
       footer = null;

  final String label;
  final IconData? icon;
  final List<ValueOption<T>>? options;
  final T? value;
  final ValueChanged<T>? onChanged;

  /// What the closed row shows; by default the selected option's title.
  final String? valueText;

  /// Shown dimmed when nothing is set (e.g. "Select bean").
  final String placeholder;
  final ValueSelectAction? action;
  final String emptyText;

  /// Replaces the options (e.g. "Loading…").
  final String? listPlaceholder;

  /// Extra content at the bottom of the open list (e.g. a free-text entry).
  final Widget? footer;

  /// Sits between value and chevron with its own tap (e.g. the grinder
  /// next to the grind size).
  final Widget? trailing;
  final Widget? panel;
  final bool isLast;
  final bool enabled;

  /// Show the value dimmed although one is set (e.g. a recipe's suggestion
  /// rather than an own setting).
  final bool dimValue;

  /// Controlled mode: the screen decides which row is open.
  final bool? open;
  final VoidCallback? onToggle;
  final VoidCallback? onClose;

  final double labelWidth;

  /// Inset of label and divider from the card edge.
  final double horizontalPadding;

  /// Left inset of the open list; by default aligned with the value
  /// column. The shot cards use 0: the list spans nearly the whole card.
  final double? listIndent;

  /// E.g. the accent for a value read from a bean's packaging but not yet
  /// confirmed (bean form).
  final Color? labelColor;
  final double labelSize;

  static const defaultLabelWidth = 64.0;
  static const minHeight = 50.0;
  static const _iconSize = 18.0;
  static const _gap = 12.0;
  static const _duration = Duration(milliseconds: 200);

  /// Extra height of the open list (for cards with a fixed height).
  static double listHeightFor<T>(
    List<ValueOption<T>> options, {
    bool action = false,
    bool footer = false,
  }) => ValueSelectList.heightFor(options, action: action) + _panelBottom;

  static const _panelBottom = 8.0;

  @override
  State<ValueSelectRow<T>> createState() => _ValueSelectRowState<T>();
}

class _ValueSelectRowState<T> extends State<ValueSelectRow<T>>
    with SingleTickerProviderStateMixin {
  bool _localOpen = false;

  // Fold in/out via SizeTransition rather than AnimatedSize: the shot cards
  // measure their content (IntrinsicHeight), and a SizeTransition reports
  // the same height there as it lays out — AnimatedSize did not, and the
  // card overflowed while the list opened.
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: ValueSelectRow._duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _expand,
    curve: Curves.easeOut,
  );
  bool? _animatedTo;
  // The last panel, kept while it folds away.
  Widget? _lastPanel;

  void _syncExpand(bool open) {
    if (_animatedTo == open) return;
    final first = _animatedTo == null;
    _animatedTo = open;
    if (first) {
      _expand.value = open ? 1 : 0;
    } else {
      // Starting here is safe: the value only changes on the next tick.
      open ? _expand.forward() : _expand.reverse();
    }
  }

  ValueSelectController? get _group => ValueSelectGroup.maybeOf(context);

  bool get _isOpen {
    if (widget.open != null) return widget.open!;
    final group = _group;
    return group != null ? group.isOpen(this) : _localOpen;
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (widget.open != null) {
      widget.onToggle?.call();
    } else if (_group != null) {
      _group!.toggle(this);
    } else {
      setState(() => _localOpen = !_localOpen);
    }
  }

  void _close() {
    if (!_isOpen) return;
    if (widget.open != null) {
      widget.onClose?.call();
    } else if (_group != null) {
      _group!.close(this);
    } else {
      setState(() => _localOpen = false);
    }
  }

  void _select(T value) {
    HapticFeedback.selectionClick();
    widget.onChanged?.call(value);
    _close();
  }

  // A real tap somewhere else closes the list; scrolling the page does not
  // (the list stays open and scrolls along). So the decision waits for the
  // finger to lift: down and up close together = tap, otherwise a drag.
  Offset? _outsideDown;

  void _onOutsideDown(PointerDownEvent event) => _outsideDown = event.position;

  void _onOutsideUp(PointerUpEvent event) {
    final down = _outsideDown;
    _outsideDown = null;
    if (down == null) return;
    if ((event.position - down).distance <= kTouchSlop) _close();
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  String? get _selectedTitle {
    for (final o in widget.options ?? <ValueOption<T>>[]) {
      if (o.value == widget.value) return o.title;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final open = _isOpen;
    final shown = widget.valueText ?? _selectedTitle;
    final hasIcon = widget.icon != null;
    final indent =
        widget.listIndent ??
        widget.horizontalPadding +
            (hasIcon ? ValueSelectRow._iconSize + ValueSelectRow._gap : 0) +
            widget.labelWidth +
            ValueSelectRow._gap;

    final valueText = Text(
      shown ?? widget.placeholder,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: shown == null || !widget.enabled || widget.dimValue
            ? colors.textTertiary
            : colors.textPrimary,
        fontSize: 15,
      ),
    );
    final chevron = SizedBox(
      width: 22,
      child: widget.enabled
          ? AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: ValueSelectRow._duration,
              curve: Curves.easeOut,
              child: Icon(
                Icons.expand_more,
                size: 22,
                color: colors.textSecondary,
              ),
            )
          : null,
    );

    // One node for screen readers: label, value and whether it is open —
    // the texts below would otherwise be read as a merged label.
    final header = Semantics(
      button: true,
      expanded: open,
      enabled: widget.enabled,
      label: widget.label,
      value: shown ?? widget.placeholder,
      onTap: widget.enabled ? _toggle : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.enabled ? _toggle : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ValueSelectRow.minHeight,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
            child: Row(
              children: [
                if (hasIcon) ...[
                  Icon(
                    widget.icon,
                    size: ValueSelectRow._iconSize,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: ValueSelectRow._gap),
                ],
                SizedBox(
                  width: widget.labelWidth,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.labelColor ?? colors.textSecondary,
                      fontSize: widget.labelSize,
                    ),
                  ),
                ),
                const SizedBox(width: ValueSelectRow._gap),
                // With a trailing widget (the grinder next to the grind
                // size) the chevron stays right at the value it opens, and
                // the trailing widget takes the right end.
                if (widget.trailing == null)
                  Expanded(child: valueText)
                else
                  Flexible(child: valueText),
                const SizedBox(width: 4),
                chevron,
                if (widget.trailing != null) ...[
                  const Spacer(),
                  const SizedBox(width: 8),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    Widget? panel;
    if (open) {
      if (widget.panel != null) {
        panel = widget.panel;
      } else {
        panel = Padding(
          padding: EdgeInsets.only(
            left: indent,
            right: widget.horizontalPadding,
            bottom: ValueSelectRow._panelBottom,
          ),
          child: ValueSelectList<T>(
            options: widget.options!,
            selected: widget.value,
            onSelected: _select,
            action: widget.action == null
                ? null
                : ValueSelectAction(widget.action!.label, () {
                    _close();
                    widget.action!.onTap();
                  }, icon: widget.action!.icon),
            emptyText: widget.emptyText,
            placeholder: widget.listPlaceholder,
            footer: widget.footer,
          ),
        );
      }
    }

    _syncExpand(open);
    if (panel != null) _lastPanel = panel;

    return TapRegion(
      onTapOutside: open ? _onOutsideDown : null,
      onTapUpOutside: open ? _onOutsideUp : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          AnimatedBuilder(
            animation: _expand,
            builder: (context, _) {
              final shown = panel ?? (_expand.value > 0 ? _lastPanel : null);
              if (shown == null) return const SizedBox(width: double.infinity);
              return SizeTransition(
                sizeFactor: _curve,
                alignment: Alignment.topCenter,
                child: shown,
              );
            },
          ),
          if (!widget.isLast)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding,
              ),
              child: Container(height: 0.5, color: colors.divider),
            ),
        ],
      ),
    );
  }
}

/// The open list on its own — for screens whose trigger is not a value row
/// (e.g. the bean header in the shot detail).
class ValueSelectList<T> extends StatefulWidget {
  const ValueSelectList({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.action,
    this.emptyText = 'Nothing here yet.',
    this.placeholder,
    this.footer,
  });

  final List<ValueOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final ValueSelectAction? action;
  final String emptyText;
  final String? placeholder;
  final Widget? footer;

  /// Above this many options a search field sits at the top.
  static const searchThreshold = 8;

  /// At most this many rows are visible; the rest scrolls.
  static const visibleRows = 5.5;

  static const _plainRow = 44.0;
  static const _richRow = 54.0;
  static const _searchHeight = 44.0;
  static const _actionHeight = 44.5;

  static double rowHeightFor<T>(List<ValueOption<T>> options) =>
      options.any((o) => o.subtitle != null || o.leading != null)
      ? _richRow
      : _plainRow;

  /// Total height of the list container (border included). Depends only on
  /// the options, not the search text, so it doesn't jump while typing.
  static double heightFor<T>(
    List<ValueOption<T>> options, {
    bool action = false,
  }) {
    final rows = options.isEmpty
        ? 1.0
        : options.length.toDouble().clamp(1.0, visibleRows);
    return 1 +
        (options.length > searchThreshold ? _searchHeight : 0) +
        rowHeightFor(options) * rows +
        (action ? _actionHeight : 0);
  }

  @override
  State<ValueSelectList<T>> createState() => _ValueSelectListState<T>();
}

class _ValueSelectListState<T> extends State<ValueSelectList<T>> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // The selected entry is visible on opening.
    final index = widget.options.indexWhere((o) => o.value == widget.selected);
    final row = ValueSelectList.rowHeightFor(widget.options);
    _scroll = ScrollController(
      initialScrollOffset: index <= 2 ? 0 : (index - 2) * row,
    );
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ValueOption<T>> _visible() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if ('${o.title} ${o.subtitle ?? ''}'.toLowerCase().contains(q)) o,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final options = widget.options;
    final searchable = options.length > ValueSelectList.searchThreshold;
    final row = ValueSelectList.rowHeightFor(options);
    final rows = options.isEmpty
        ? 1.0
        : options.length.toDouble().clamp(1.0, ValueSelectList.visibleRows);
    final visible = _visible();
    final message =
        widget.placeholder ??
        (options.isEmpty
            ? widget.emptyText
            : (visible.isEmpty ? 'No matches.' : null));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (searchable)
              SizedBox(
                height: ValueSelectList._searchHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _search,
                    focusNode: _focus,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    cursorColor: colors.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 28),
                      hintText: 'Search',
                      hintStyle: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: colors.divider,
                          width: 0.5,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.textSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: row * rows,
              child: message != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          message,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      itemExtent: row,
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _OptionRow<T>(
                        option: visible[i],
                        selected: visible[i].value == widget.selected,
                        onTap: () => widget.onSelected(visible[i].value),
                      ),
                    ),
            ),
            if (widget.action != null) ...[
              Container(height: 0.5, color: colors.divider),
              InkWell(
                onTap: widget.action!.onTap,
                child: SizedBox(
                  height: ValueSelectList._actionHeight - 0.5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          widget.action!.icon,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.action!.label,
                          style: TextStyle(color: colors.accent, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            ?widget.footer,
          ],
        ),
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ValueOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (option.leading != null) ...[
                option.leading!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    if (option.subtitle != null)
                      Text(
                        option.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 18, color: colors.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// Drop-down list of a Pre-Shot selection (bean, profile) directly in the
// card: the scrollable list on top, at the very bottom the row with a
// magnifier (left, turns into the search field) and optionally "+" (right).
// Design rules for all dropdowns: search/add row at the bottom, no
// highlighting of the triggering row, photos in the entries where available.
class InlinePicker<T> extends StatefulWidget {
  const InlinePicker({
    super.key,
    required this.items,
    required this.leading,
    required this.title,
    required this.isSelected,
    required this.onSelected,
    this.detail,
    this.searchText,
    this.onAdd,
    this.addTooltip = 'Add',
    this.placeholder,
    this.emptyText = 'Nothing here yet.',
  });

  // Already in display order.
  final List<T> items;
  final Widget Function(T item) leading;
  final String Function(T item) title;
  // Muted extra text after the title (e.g. roaster).
  final String? Function(T item)? detail;
  // Text the search looks in; the title if not given.
  final String Function(T item)? searchText;
  final bool Function(T item) isSelected;
  final ValueChanged<T> onSelected;
  // Without onAdd there is no "+".
  final VoidCallback? onAdd;
  final String addTooltip;
  // Replaces the list (e.g. "Loading…").
  final String? placeholder;
  final String emptyText;

  static const _footerHeight = 48.0;
  static const _rowHeight = 48.0;
  static const _maxRows = 4;
  static const _marginTop = 2.0;
  static const _marginBottom = 8.0;

  // Total height including outer padding. Depends only on the total number
  // of entries (not the search result), so it does not jump while typing;
  // from [_maxRows] entries on, the list scrolls.
  static double heightFor(int itemCount) =>
      _marginTop +
      _footerHeight +
      1 +
      _rowHeight * itemCount.clamp(1, _maxRows) +
      _marginBottom;

  @override
  State<InlinePicker<T>> createState() => _InlinePickerState<T>();
}

class _InlinePickerState<T> extends State<InlinePicker<T>> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  List<T> _visible() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return [
      for (final item in widget.items)
        if ((widget.searchText ?? widget.title)(item).toLowerCase().contains(q))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final listHeight =
        InlinePicker._rowHeight *
        widget.items.length.clamp(1, InlinePicker._maxRows);
    final message =
        widget.placeholder ??
        (visible.isEmpty
            ? (widget.items.isEmpty ? widget.emptyText : 'No matches.')
            : null);
    return Padding(
      padding: const EdgeInsets.only(
        top: InlinePicker._marginTop,
        bottom: InlinePicker._marginBottom,
      ),
      // Material, so the rows' tap animation is not hidden by the card's
      // background.
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: listHeight,
              child: message != null
                  ? Center(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemExtent: InlinePicker._rowHeight,
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final item = visible[i];
                        return _Row(
                          leading: widget.leading(item),
                          title: widget.title(item),
                          detail: widget.detail?.call(item),
                          selected: widget.isSelected(item),
                          onTap: () => widget.onSelected(item),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: context.colors.divider),
            SizedBox(
              height: InlinePicker._footerHeight,
              child: Row(
                children: [
                  if (_searching) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.search,
                      color: context.colors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            color: context.colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close search',
                      icon: Icon(
                        Icons.close,
                        color: context.colors.textSecondary,
                        size: 20,
                      ),
                      onPressed: _closeSearch,
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Search',
                      icon: Icon(
                        Icons.search,
                        color: context.colors.textSecondary,
                      ),
                      onPressed: () => setState(() => _searching = true),
                    ),
                    const Spacer(),
                  ],
                  if (widget.onAdd != null)
                    IconButton(
                      tooltip: widget.addTooltip,
                      icon: Icon(Icons.add, color: context.colors.accent),
                      onPressed: widget.onAdd,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail?.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    if (detail != null && detail.isNotEmpty)
                      TextSpan(
                        text: '   $detail',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Icon(Icons.check, color: context.colors.accent, size: 18),
          ],
        ),
      ),
    );
  }
}

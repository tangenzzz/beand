import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Swipeable row of cards whose order can be changed by long press and drag
// (for the profile rows of ALL home pages — Meticulous, GaggiMate, Pour Over
// and future ones). Tapping stays with the card itself.
//
// The new order shows immediately; [onReorder] saves it. As soon as [items]
// brings a different order (saved, or reset because the machine rejected
// it), [items] applies again.
class ReorderableTileRow<T> extends StatefulWidget {
  const ReorderableTileRow({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onReorder,
    this.spacing = 10,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final ValueChanged<List<T>> onReorder;
  final double spacing;

  @override
  State<ReorderableTileRow<T>> createState() => _ReorderableTileRowState<T>();
}

class _ReorderableTileRowState<T> extends State<ReorderableTileRow<T>> {
  List<T>? _moved;

  @override
  void didUpdateWidget(ReorderableTileRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameOrder(oldWidget.items, widget.items)) _moved = null;
  }

  bool _sameOrder(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (widget.idOf(a[i]) != widget.idOf(b[i])) return false;
    }
    return true;
  }

  // onReorderItem already provides newIndex for the list without the dragged
  // element.
  void _reorder(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    final list = List.of(_moved ?? widget.items);
    list.insert(newIndex, list.removeAt(oldIndex));
    setState(() => _moved = list);
    widget.onReorder(list);
  }

  @override
  Widget build(BuildContext context) {
    final items = _moved ?? widget.items;
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      // Custom handles instead of the default ones: long press on all
      // platforms, the whole card is the handle.
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: _reorder,
      // The dragged card lifts slightly.
      proxyDecorator: (child, _, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.05 * Curves.easeOut.transform(animation.value),
          child: child,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
        key: ValueKey(widget.idOf(items[i])),
        index: i,
        child: Padding(
          padding: EdgeInsets.only(
            right: i == items.length - 1 ? 0 : widget.spacing,
          ),
          child: widget.itemBuilder(context, items[i]),
        ),
      ),
    );
  }
}

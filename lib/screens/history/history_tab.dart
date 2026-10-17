import 'dart:async';

import 'package:flutter/material.dart';

import '../root_scaffold.dart';

import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/shot_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/header_icon_button.dart';
import 'history_filter_sheet.dart';
import 'history_logic.dart';
import 'history_widgets.dart';
import 'shot_detail_screen.dart';

// List of all shots, grouped by day (design follows the bean list: search +
// filter on the left, gear on the right). Reads only the local DB — so the
// history is complete even without a connection to the machine.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, this.scrollToTop});

  /// Reports a tap on the History button in the tab bar; the list then jumps
  /// back to the top. Null outside the root scaffold.
  final Listenable? scrollToTop;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  late final StreamSubscription<List<ShotEntry>> _sub;
  List<ShotEntry>? _entries;
  HistoryFilter _filter = HistoryFilter.empty;
  // Free-text search over bean, roastery, profile, notes and machine (same
  // pattern as the bean list: magnifier opens a text field in the header).
  final _search = TextEditingController();
  bool _searching = false;
  // Multi-select for deleting (long press starts it).
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.scrollToTop?.addListener(_scrollToTop);
    _sub = context.read<AppDatabase>().watchShotEntries().listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToTop != widget.scrollToTop) {
      oldWidget.scrollToTop?.removeListener(_scrollToTop);
      widget.scrollToTop?.addListener(_scrollToTop);
    }
  }

  @override
  void dispose() {
    widget.scrollToTop?.removeListener(_scrollToTop);
    _scroll.dispose();
    _sub.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openFilter() async {
    final entries = _entries;
    if (entries == null) return;
    final result = await showHistoryFilterSheet(
      context,
      entries: entries,
      initial: _filter,
      query: _search.text,
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  void _toggleSelected(ShotEntry entry) => setState(() {
    if (!_selected.remove(entry.shot.id)) _selected.add(entry.shot.id);
  });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final confirmed = await confirmDeleteShots(context, ids.length);
    if (!confirmed || !mounted) return;
    await context.read<AppDatabase>().deleteShots(ids);
    if (mounted) setState(_selected.clear);
  }

  void _openShot(ShotEntry entry) {
    if (_selecting) return _toggleSelected(entry);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShotDetailScreen(shotId: entry.shot.id),
      ),
    );
  }

  Widget _filterButton() {
    final count = _filter.activeCount;
    return HeaderIconButton(
      tooltip: 'Filter',
      onPressed: _openFilter,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: context.colors.textPrimary,
        textColor: context.colors.bg,
        child: Icon(
          Icons.tune,
          color: count > 0
              ? context.colors.accent
              : context.colors.textSecondary,
        ),
      ),
    );
  }

  Widget _header() {
    if (_selecting) {
      return Row(
        children: [
          HeaderIconButton(
            tooltip: 'Cancel selection',
            icon: Icon(Icons.close, color: context.colors.textSecondary),
            onPressed: () => setState(_selected.clear),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_selected.length} selected',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          HeaderIconButton(
            tooltip: 'Delete selected shots',
            icon: Icon(
              Icons.delete_outline,
              color: context.colors.textSecondary,
            ),
            onPressed: _deleteSelected,
          ),
        ],
      );
    }
    if (_searching) {
      return Row(
        children: [
          HeaderIconButton(
            tooltip: 'Close search',
            icon: Icon(Icons.arrow_back, color: context.colors.textSecondary),
            onPressed: _closeSearch,
          ),
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search shots',
                hintStyle: TextStyle(color: context.colors.textTertiary),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            HeaderIconButton(
              tooltip: 'Clear',
              icon: Icon(Icons.close, color: context.colors.textSecondary),
              onPressed: _search.clear,
            ),
          _filterButton(),
        ],
      );
    }
    return Row(
      children: [
        HeaderIconButton(
          tooltip: 'Search',
          icon: Icon(Icons.search, color: context.colors.textSecondary),
          onPressed: () => setState(() => _searching = true),
        ),
        _filterButton(),
        const Spacer(),
        HeaderIconButton(
          tooltip: 'Settings',
          icon: Icon(
            Icons.settings_outlined,
            color: context.colors.textSecondary,
          ),
          onPressed: () {
            RootNavigation.maybeOf(context)?.openSettings();
          },
        ),
      ],
    );
  }

  Widget _message(String text, {Widget? action}) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary),
          ),
          ?action,
        ],
      ),
    ),
  );

  List<Widget> _body() {
    final entries = _entries;
    if (entries == null) return const [];
    if (entries.isEmpty) {
      return [
        _message(
          'No shots recorded yet.\nShots from the machine are saved here automatically.',
        ),
      ];
    }
    final visible = filterShots(entries, query: _search.text, filter: _filter);
    if (visible.isEmpty) {
      return [
        _message(
          'No matching shots.',
          action: _filter.isActive
              ? TextButton(
                  onPressed: () =>
                      setState(() => _filter = HistoryFilter.empty),
                  child: const Text('Clear filters'),
                )
              : null,
        ),
      ];
    }
    return [
      ShotListSliver(
        groups: groupShotsByDay(visible),
        onTap: _openShot,
        onLongPress: _toggleSelected,
        selectedIds: _selected,
        selectionMode: _selecting,
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Back ends the selection first instead of leaving the app.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return SafeArea(
      // Pull to refresh fetches missing shots from the machine (if
      // reachable) — normally this already happens automatically.
      child: RefreshIndicator(
        color: context.colors.accent,
        backgroundColor: context.colors.card,
        onRefresh: () => context.read<ShotSyncService>().sync(),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  ..._body(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

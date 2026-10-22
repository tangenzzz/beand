import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../root_scaffold.dart';

import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/header_icon_button.dart';
import '../../widgets/underline_select.dart';
import 'bean_filter.dart';
import 'bean_filter_sheet.dart';
import 'bean_form_screen.dart';
import 'bean_stock.dart';
import 'bean_widgets.dart';

class BeansTab extends StatefulWidget {
  const BeansTab({super.key, this.scrollToTop});

  /// Reports a tap on the Beans button in the tab bar; the list then jumps
  /// back to the top. Null outside the root scaffold.
  final Listenable? scrollToTop;

  @override
  State<BeansTab> createState() => _BeansTabState();
}

class _BeansTabState extends State<BeansTab> {
  final _search = TextEditingController();
  late final StreamSubscription<List<Bean>> _sub;
  late final StreamSubscription<Map<int, double>> _usageSub;
  List<Bean>? _beans;
  Map<int, double> _usage = const {};
  bool _searching = false;
  BeanFilter _filter = BeanFilter.empty;
  BeanStatus _status = BeanStatus.all;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.scrollToTop?.addListener(_scrollToTop);
    _sub = context.read<AppDatabase>().watchBeans().listen((beans) {
      if (mounted) setState(() => _beans = beans);
    });
    _usageSub = context.read<AppDatabase>().watchBeanUsage().listen((usage) {
      if (mounted) setState(() => _usage = usage);
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(BeansTab oldWidget) {
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
    _usageSub.cancel();
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

  void _openForm([Bean? bean]) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BeanFormScreen(bean: bean)));
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  Future<void> _openFilter() async {
    final beans = _beans;
    if (beans == null) return;
    final result = await showBeanFilterSheet(
      context,
      beans: beans,
      initial: _filter,
      query: _search.text,
    );
    if (result != null && mounted) setState(() => _filter = result);
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
                hintText: 'Search beans',
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
          tooltip: 'Add bean',
          icon: Icon(Icons.add, color: context.colors.textSecondary),
          onPressed: _openForm,
        ),
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

  Widget _body() {
    final beans = _beans;
    if (beans == null) return const SizedBox.shrink();
    if (beans.isEmpty) {
      return const _EmptyMessage('No beans added yet.\nTap + to add one.');
    }
    final stock = context.watch<AppSettings>().showBeanStock;
    final matching = filterBeans(beans, query: _search.text, filter: _filter);
    final visible = [
      for (final b in matching)
        if (beanHasStatus(b, _status, _usage, stock: stock)) b,
    ];
    if (matching.isEmpty) {
      return _EmptyMessage(
        'No matching beans.',
        action: _filter.isActive
            ? TextButton(
                onPressed: () => setState(() => _filter = BeanFilter.empty),
                child: const Text('Clear filters'),
              )
            : null,
      );
    }
    return _BeanListTile(
      status: _status,
      onStatus: (s) => setState(() => _status = s),
      beans: visible,
      usage: _usage,
      onTap: _openForm,
      onToggleEmpty: _toggleEmpty,
      onThaw: _thaw,
      onFreeze: _freeze,
    );
  }

  // Long press on the photo: mark as empty or release again. Empty beans are
  // missing from the pre-shot selection.
  Future<void> _toggleEmpty(Bean bean) async {
    final db = context.read<AppDatabase>();
    final before = bean.emptiedAt;
    final emptying = before == null;
    await db.updateBean(
      bean.id,
      BeansCompanion(emptiedAt: Value(emptying ? DateTime.now() : null)),
    );
    _undoable(
      emptying ? '${bean.name} is used up' : '${bean.name} is back in stock',
      () => db.updateBean(bean.id, BeansCompanion(emptiedAt: Value(before))),
    );
  }

  // Long press on the snowflake: thaw, the freshness ring starts today (like
  // switching off "Frozen" in the bean form).
  Future<void> _thaw(Bean bean) async {
    final db = context.read<AppDatabase>();
    await db.updateBean(
      bean.id,
      BeansCompanion(
        isFrozen: const Value(false),
        thawedDate: Value(DateTime.now()),
      ),
    );
    _undoable(
      'Thawed – freshness ring starts today',
      () => db.updateBean(
        bean.id,
        BeansCompanion(
          isFrozen: const Value(true),
          thawedDate: Value(bean.thawedDate),
        ),
      ),
    );
  }

  // Long press on the freshness ring: freeze, the ring pauses (counterpart
  // to thawing; the thaw date stays as in the form).
  Future<void> _freeze(Bean bean) async {
    final db = context.read<AppDatabase>();
    await db.updateBean(bean.id, const BeansCompanion(isFrozen: Value(true)));
    _undoable(
      'Frozen – freshness ring paused',
      () =>
          db.updateBean(bean.id, const BeansCompanion(isFrozen: Value(false))),
    );
  }

  void _undoable(String message, Future<void> Function() undo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          // Otherwise Flutter keeps snackbars with an action visible until
          // they are tapped away (the undo line did not go away).
          persist: false,
          action: SnackBarAction(label: 'Undo', onPressed: () => undo()),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_header(), _body()],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

class _BeanListTile extends StatelessWidget {
  const _BeanListTile({
    required this.status,
    required this.onStatus,
    required this.beans,
    required this.usage,
    required this.onTap,
    required this.onToggleEmpty,
    required this.onThaw,
    required this.onFreeze,
  });

  final BeanStatus status;
  final ValueChanged<BeanStatus> onStatus;
  final List<Bean> beans;
  final Map<int, double> usage;
  final ValueChanged<Bean> onTap;
  final ValueChanged<Bean> onToggleEmpty;
  final ValueChanged<Bean> onThaw;
  final ValueChanged<Bean> onFreeze;

  @override
  Widget build(BuildContext context) {
    final groups = groupBeansByRoaster(beans);
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // All · Open · Frozen · Finished — like the tabs of My Coffee Desk.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.dividerInset,
              4,
              AppSpacing.dividerInset,
              0,
            ),
            child: SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerLeft,
                child: UnderlineSelect<BeanStatus>(
                  key: const ValueKey('bean-status'),
                  options: [
                    for (final s in BeanStatus.values)
                      UnderlineOption(s, s.label),
                  ],
                  value: status,
                  onChanged: (s) => onStatus(s!),
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: AppSpacing.dividerInset,
            endIndent: AppSpacing.dividerInset,
            color: context.colors.divider,
          ),
          if (beans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.dividerInset,
                vertical: 20,
              ),
              child: Text(
                'No ${status.label.toLowerCase()} beans.',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          // A divider only where the roaster changes — within one roaster
          // the beans stand together without dividers.
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0)
              Divider(
                height: 1,
                indent: AppSpacing.dividerInset,
                endIndent: AppSpacing.dividerInset,
                color: context.colors.divider,
              ),
            BeanGroupHeader(groups[g].roaster),
            for (final bean in groups[g].beans)
              BeanRow(
                bean: bean,
                usage: usage,
                onTap: () => onTap(bean),
                onPhotoLongPress: () => onToggleEmpty(bean),
                onFrozenLongPress: () => onThaw(bean),
                onFreshLongPress: () => onFreeze(bean),
              ),
          ],
        ],
      ),
    );
  }
}

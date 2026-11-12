import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/value_select_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Bean bag(
  int id,
  String name, {
  String? roaster,
  DateTime? openedAt,
  DateTime? emptiedAt,
  bool frozen = false,
}) => Bean(
  frozenDays: 0,
  syncId: 'test-$id',
  updatedAt: 0,
  syncState: SyncState.pending,
  deleted: false,
  id: id,
  name: name,
  roaster: roaster,
  isBlend: false,
  isFrozen: frozen,
  openedAt: openedAt,
  emptiedAt: emptiedAt,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  final now = DateTime(2026, 11, 12);
  final opened = DateTime(2026, 11, 1);

  group('beanPickerOrder', () {
    final beans = [
      bag(1, 'Sealed', roaster: 'A'),
      bag(2, 'Open B', roaster: 'B', openedAt: opened),
      bag(3, 'Open A', roaster: 'A', openedAt: opened),
      bag(4, 'Frozen', roaster: 'A', openedAt: opened, frozen: true),
      bag(
        5,
        'Empty recently',
        openedAt: opened,
        emptiedAt: DateTime(2026, 11, 1),
      ),
      bag(
        6,
        'Empty long ago',
        openedAt: opened,
        emptiedAt: DateTime(2026, 9, 1),
      ),
    ];

    test('open bags first, old empty ones only via search', () {
      final order = beanPickerOrder(beans, now: now);
      expect(order.map((e) => e.bean.id), [3, 2, 4, 1, 5, 6]);
      expect(
        [
          for (final e in order)
            if (e.searchOnly) e.bean.id,
        ],
        [6],
      );
    });

    test('the selected bag stays listed even if long empty', () {
      final order = beanPickerOrder(beans, now: now, selectedId: 6);
      expect([
        for (final e in order)
          if (e.searchOnly) e.bean.id,
      ], isEmpty);
      expect(order.map((e) => e.bean.id).skip(4), [6, 5]);
    });
  });

  testWidgets('searchOnly options appear only when the search matches', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ValueSelectList<int>(
            options: const [
              ValueOption(value: 1, title: 'Kenya'),
              ValueOption(value: 2, title: 'Old Ethiopia', searchOnly: true),
            ],
            selected: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Kenya'), findsOneWidget);
    expect(find.text('Old Ethiopia'), findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ethi');
    await tester.pump();
    expect(find.text('Old Ethiopia'), findsOneWidget);
    expect(find.text('Kenya'), findsNothing);
  });
}

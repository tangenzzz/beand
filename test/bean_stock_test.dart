import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_stock.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/screens/beans/freshness.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Bean _bean({int id = 1, double? weight, bool frozen = false}) => Bean(
  syncId: 'test',
  updatedAt: 0,
  syncState: SyncState.pending,
  deleted: false,
  id: id,
  name: 'Guji',
  weightGrams: weight,
  roastDate: DateTime.now().subtract(const Duration(days: 12)),
  isFrozen: frozen,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  test(
    'usage per bean: sum of doses, shots without a dose do not count',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final guji = await db.insertBean(
        BeansCompanion.insert(name: 'Guji', weightGrams: const Value(250)),
      );
      final other = await db.insertBean(BeansCompanion.insert(name: 'Other'));
      for (final dose in [18.0, 18.5, null]) {
        await db
            .into(db.shots)
            .insert(
              ShotsCompanion.insert(
                timestamp: DateTime(2026, 10, 8),
                beanId: Value(guji.id),
                doseGrams: Value(dose),
              ),
            );
      }
      await db
          .into(db.shots)
          .insert(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 10, 8),
              doseGrams: const Value(20),
            ),
          );

      final usage = await db.watchBeanUsage().first;
      expect(usage, {guji.id: 36.5});
      expect(beanRemaining(guji, usage), 213.5);
      expect(beanRemaining(other, usage), isNull, reason: 'no bag weight');
    },
  );

  test('remaining never negative; empty only below half a gram', () {
    final bean = _bean(weight: 36);
    expect(beanRemaining(bean, {1: 40}), 0);
    expect(beanIsEmpty(bean, {1: 40}), isTrue);
    expect(beanIsEmpty(bean, {1: 35}), isFalse);
    expect(beanIsEmpty(_bean(), {1: 400}), isFalse);
  });

  Future<void> pumpRow(
    WidgetTester tester,
    Bean bean,
    Map<int, double> usage, {
    bool stock = true,
  }) => tester.pumpWidget(
    ChangeNotifierProvider<AppSettings>.value(
      value: AppSettings(showBeanStock: stock),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: BeanRow(bean: bean, usage: usage, onTap: () {}),
        ),
      ),
    ),
  );

  testWidgets('row: remaining grams on the photo, freshness ring stays', (
    tester,
  ) async {
    await pumpRow(tester, _bean(weight: 250), {1: 70});
    expect(find.text('180g'), findsOneWidget);
    expect(find.byType(FreshnessRing), findsOneWidget);
  });

  testWidgets('finished: neither remaining amount nor freshness ring', (
    tester,
  ) async {
    await pumpRow(tester, _bean(weight: 250), {1: 252});
    expect(find.text('0g'), findsNothing);
    expect(find.byType(FreshnessRing), findsNothing);
  });

  testWidgets('no bag weight or switched off: no number', (tester) async {
    await pumpRow(tester, _bean(), {1: 70});
    expect(find.textContaining(RegExp(r'^\d+g$')), findsNothing);
    await pumpRow(tester, _bean(weight: 250), {1: 252}, stock: false);
    expect(find.text('0g'), findsNothing);
    expect(find.byType(FreshnessRing), findsOneWidget);
  });
}

import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_form_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget app(AppDatabase db, Widget home) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

void main() {
  testWidgets('New bag: the coffee is taken over, the bag starts empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final old = (await tester.runAsync(
      () => db.insertBean(
        BeansCompanion.insert(
          name: 'Kiambu',
          roaster: const Value('Bonanza'),
          country: const Value('Kenya'),
          processing: const Value('Washed'),
          taste: const Value('blackcurrant, grapefruit'),
          roastedFor: const Value('filter'),
          roastDate: Value(DateTime(2026, 10, 1)),
          weightGrams: const Value(250),
          cost: const Value(17.5),
          isFrozen: const Value(true),
        ),
      ),
    ))!;

    await tester.pumpWidget(
      app(
        db,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BeanFormScreen(bean: old),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit bean'), findsOneWidget);

    await tester.tap(find.text('New bag'));
    await tester.pumpAndSettle();
    expect(find.text('New bag'), findsOneWidget); // the title
    expect(find.text('Edit bean'), findsNothing);
    expect(find.text('Delete bean'), findsNothing);
    expect(find.widgetWithText(TextField, 'Kiambu'), findsOneWidget);
    expect(find.widgetWithText(TextField, '250'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final beans = (await tester.runAsync(() => db.select(db.beans).get()))!;
    expect(beans, hasLength(2));
    final bag = beans.singleWhere((b) => b.id != old.id);
    expect(bag.name, 'Kiambu');
    expect(bag.roaster, 'Bonanza');
    expect(bag.country, 'Kenya');
    expect(bag.processing, 'Washed');
    expect(bag.taste, 'blackcurrant, grapefruit');
    expect(bag.roastedFor, 'filter');
    // What belongs to one bag starts empty, whatever the old bag's size.
    expect(bag.roastDate, isNull);
    expect(bag.weightGrams, isNull);
    expect(bag.cost, isNull);
    expect(bag.isFrozen, isFalse);
    expect(bag.emptiedAt, isNull);
    // The old bag is untouched.
    final before = beans.singleWhere((b) => b.id == old.id);
    expect(before.weightGrams, 250);
    expect(before.roastDate, DateTime(2026, 10, 1));
  });
}

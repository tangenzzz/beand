import 'package:beand/models/gear.dart';
import 'package:beand/screens/onboarding/onboarding_art.dart';
import 'package:beand/screens/onboarding/onboarding_screen.dart';
import 'package:beand/screens/settings/my_coffee_desk_screen.dart';
import 'package:beand/services/first_run.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/grinder_store.dart';
import 'package:beand/services/water_store.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/theme/bean_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('screens', () {
    late List<String> opened;
    late bool saved;
    late int finished;

    Future<bool> action(String name) async {
      opened.add(name);
      return saved;
    }

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: OnboardingScreen(
            onFinished: () => finished++,
            actions: OnboardingActions(
              connectMachine: (_) => action('machine'),
              addBean: (_) => action('bean'),
              addGear: (_) => action('gear'),
              addChain: (_) => action('chain'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Future<void> tapPulsing(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() {
      opened = [];
      saved = true;
      finished = 0;
    });

    testWidgets('walks through all five, each Add opens its screen', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Connect your machine'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);

      await tapText(tester, 'Add machine');
      expect(find.text('Add a bean'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tapText(tester, 'Add bean');
      expect(find.text('Add your gear'), findsOneWidget);
      expect(find.textContaining('coffee desk at home'), findsOneWidget);

      await tapText(tester, 'Add gear');
      expect(find.text('Create brew chains'), findsOneWidget);

      // The last page pulses forever, pumpAndSettle would never return.
      await tapPulsing(tester, 'Create brew chain');
      expect(find.text('Ready for brewing'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(opened, ['machine', 'bean', 'gear', 'chain']);

      double glow() => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(CupArt),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      final before = glow();
      await tester.pump(const Duration(milliseconds: 400));
      expect(glow(), isNot(before));

      expect(finished, 0);
      await tapPulsing(tester, "Let's go");
      expect(finished, 1);
    });

    testWidgets('nothing saved: stays on the page', (tester) async {
      saved = false;
      await pump(tester);
      await tapText(tester, 'Add machine');
      expect(find.text('Connect your machine'), findsOneWidget);
    });

    testWidgets('Skip moves on without opening anything, Back returns', (
      tester,
    ) async {
      await pump(tester);
      await tapText(tester, 'Skip');
      expect(find.text('Add a bean'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Connect your machine'), findsOneWidget);
    });

    testWidgets('fits a small phone', (tester) async {
      await pump(tester);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add machine'), findsOneWidget);
    });
  });

  testWidgets('the bean on the cup stays teal with any accent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(accent: AppAccent.oat),
        home: const Scaffold(body: CupArt()),
      ),
    );
    final beans = tester.widgetList<BeanIcon>(find.byType(BeanIcon));
    expect(beans, isNotEmpty);
    for (final bean in beans) {
      expect(bean.color, AppAccent.teal.dark);
    }
  });

  group('desk opened from the introduction', () {
    late GearStore gear;
    bool? result;

    Future<void> openDesk(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      gear = GearStore.inMemory();
      result = null;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GearStore>.value(value: gear),
            ChangeNotifierProvider<GrinderStore>(
              create: (_) => GrinderStore(gear),
            ),
            ChangeNotifierProvider<WaterStore>(create: (_) => WaterStore(gear)),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const MyCoffeeDeskScreen(closeAfterAdding: true),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to desk'));
      await tester.pumpAndSettle();
    }

    void closeSheet(WidgetTester tester) =>
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();

    testWidgets('after saving something, back to the introduction', (
      tester,
    ) async {
      await openDesk(tester);
      gear.save(const Gear(id: 'b1', type: GearType.brewer, model: 'V60'));
      closeSheet(tester);
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(MyCoffeeDeskScreen), findsNothing);
    });

    testWidgets('nothing saved: the desk stays open', (tester) async {
      await openDesk(tester);
      closeSheet(tester);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(MyCoffeeDeskScreen), findsOneWidget);
    });
  });

  group('FirstRun', () {
    Future<FirstRun> firstRun([Map<String, Object> values = const {}]) async {
      SharedPreferences.setMockInitialValues(values);
      return FirstRun(await SharedPreferences.getInstance());
    }

    test('new install: introduction until it is finished', () async {
      final run = await firstRun();
      expect(await run.needsOnboarding(() async => false), isTrue);
      await run.finishOnboarding();
      expect(await run.needsOnboarding(() async => false), isFalse);
    });

    test('existing data: no introduction, and no more queries', () async {
      final run = await firstRun();
      expect(await run.needsOnboarding(() async => true), isFalse);
      var asked = false;
      expect(
        await run.needsOnboarding(() async {
          asked = true;
          return false;
        }),
        isFalse,
      );
      expect(asked, isFalse);
    });

    test('backup reminder: once, after a week, only while off', () async {
      final run = await firstRun();
      final start = DateTime(2026, 11, 9);
      Future<bool> due(Duration after, {bool on = false}) =>
          run.takeBackupReminder(autoBackupOn: on, now: start.add(after));

      expect(await due(Duration.zero), isFalse);
      expect(await due(const Duration(days: 6)), isFalse);
      expect(await due(const Duration(days: 8), on: true), isFalse);
      expect(await due(const Duration(days: 8)), isTrue);
      expect(await due(const Duration(days: 9)), isFalse);
    });
  });
}

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_form_screen.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/screens/beans/beans_tab.dart';
import 'package:beand/screens/beans/freshness.dart';
import 'package:beand/screens/settings/settings_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:beand/screens/settings/settings_widgets.dart';

Widget app(
  AppDatabase db,
  Widget home, {
  AppSettings? settings,
}) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<AppSettings>.value(value: settings ?? AppSettings()),
    // The bean form asks the AI settings (row "Fill from packaging or
    // link").
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
    ChangeNotifierProvider<MeticulousSocketService>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    // The same machine again under the shared interface: the Pre-Shot card
    // talks to it through that.
    ChangeNotifierProvider<EspressoMachine>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

// Explanations sit behind an ⓘ (SettingsInfo), not as visible text.
Finder findInfo(String part) =>
    find.byWidgetPredicate((w) => w is SettingsInfo && w.text.contains(part));

void main() {
  // The version line at the bottom of the settings takes its number from
  // the package (PackageInfo), not from a string in the code — so the test
  // injects package values and expects exactly those (anyone hardcoding
  // the number fails).
  testWidgets('Settings: version line at the bottom shows version and build', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: "bean'd",
      packageName: 'app.beand',
      version: '9.9.9',
      buildNumber: '42',
      buildSignature: '',
    );
    // Tall enough for all entries; the list is lazy and would not build a
    // line below the fold.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    await tester.pumpWidget(app(db, const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text("bean'd 9.9.9 (42)"), findsOneWidget);
    // It sits below the last menu entry.
    expect(
      tester.getCenter(find.text("bean'd 9.9.9 (42)")).dy,
      greaterThan(tester.getCenter(find.text('Backup')).dy),
    );
  });

  testWidgets('Settings: Connections > Meticulous / Scale, Beans', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(app(db, const SettingsScreen()));

    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Beans'), findsOneWidget);

    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    expect(find.text('Meticulous'), findsOneWidget);
    expect(find.text('Scales'), findsOneWidget);

    await tester.tap(find.text('Meticulous'));
    await tester.pumpAndSettle();
    // The page leads with state and search; the field for typing sits
    // collapsed below.
    expect(find.text('MACHINES ON YOUR NETWORK'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'collapsed');

    await tester.tap(find.text('Enter address manually'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save & reconnect'), findsOneWidget);
    await db.close();
  });

  testWidgets('Settings > History: expand and choose Thumbnail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings();
    await tester.pumpWidget(
      app(db, const SettingsScreen(), settings: settings),
    );

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    // Collapsed: title Thumbnail, below it the current choice (default:
    // profile), no options.
    expect(find.text('Thumbnail'), findsOneWidget);
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Bean photo'), findsNothing);
    expect(settings.historyAvatar, HistoryAvatar.profile);

    await tester.tap(find.text('Thumbnail'));
    await tester.pumpAndSettle();
    expect(find.text('Bean photo'), findsOneWidget);
    // Exactly one check mark, at profile.
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Bean photo'));
    await tester.pumpAndSettle();
    expect(settings.historyAvatar, HistoryAvatar.bean);
    // The selection collapses, the row shows the new choice.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('Bean photo'), findsOneWidget);
    expect(find.text('Profile photo'), findsNothing);
    expect(
      SharedPreferences.getInstance().then(
        (p) => p.getString(AppSettings.historyAvatarPrefKey),
      ),
      completion('bean'),
    );
    await db.close();
  });
}

void freshnessTests() {
  testWidgets(
    'Freshness: ring in list on/off via Settings, legend in Settings',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});

      final settings = AppSettings();
      final db = AppDatabase(NativeDatabase.memory());
      // Twelve calendar days back (not 12 × 24 h: across a clock change
      // that lands on the neighbouring day late in the evening).
      final now = DateTime.now();
      final roast = DateTime(now.year, now.month, now.day - 12, 12);
      await tester.runAsync(
        () => db.insertBean(
          BeansCompanion.insert(
            openedAt: Value(DateTime(2026)),
            name: 'Kiambu',
            roastDate: Value(roast),
          ),
        ),
      );

      // List with ring: FreshnessRing shows the days, no "12 d" text.
      await tester.pumpWidget(
        app(db, const Scaffold(body: BeansTab()), settings: settings),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.byType(FreshnessRing), findsOneWidget);
      expect(find.text('12 d'), findsNothing);

      // The legend is not in the form.
      await tester.pumpWidget(
        app(db, const BeanFormScreen(), settings: settings),
      );
      await tester.pump();
      expect(find.byType(FreshnessLegend), findsNothing);

      // Switch under Settings > Beans.
      await tester.pumpWidget(
        app(db, const SettingsScreen(), settings: settings),
      );
      await tester.tap(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('Freshness ring'), findsOneWidget);
      // The legend sits behind the ⓘ: press and hold first, then it is there.
      expect(find.byType(FreshnessLegend), findsNothing);
      await tester.longPress(findInfo('Days since roast'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FreshnessLegend), findsOneWidget);
      // One band per roast, the days where the color changes.
      for (final days in ['7 d', '21 d', '10 d', '70 d']) {
        expect(find.text(days), findsOneWidget);
      }
      expect(
        find.text('28 d'),
        findsNWidgets(2),
      ); // medium's end, light's start
      expect(find.text('Still resting'), findsOneWidget);
      expect(find.textContaining('Ultra light'), findsNothing);
      expect(
        find.textContaining('your taste has the final say'),
        findsOneWidget,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(settings.showFreshnessRing, false);

      // Off: text instead of ring. Tear down first so drift closes the old
      // stream cleanly before the list subscribes again.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.pumpWidget(
        app(db, const Scaffold(body: BeansTab()), settings: settings),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.byType(FreshnessRing), findsNothing);
      expect(find.text('12 d'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await db.close();
    },
  );

  // Since the theme rework the levels come from the tokens, no longer from
  // fixed values — the thresholds (7 / 28 days) stayed the same.
  testWidgets('Freshness: windows by roast level, ring fills over 12 weeks', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final colors = AppColors.of(ctx);
    // Dark 1–3 wk, Medium 10 d–4 wk, Light (and ultra light) 4–10 wk.
    expect(freshnessColor(ctx, 6, 'dark'), colors.heroRingHeating);
    expect(freshnessColor(ctx, 7, 'dark'), colors.success);
    expect(freshnessColor(ctx, 21, 'dark'), colors.success);
    expect(freshnessColor(ctx, 22, 'dark'), colors.textSecondary);
    expect(freshnessColor(ctx, 9, 'medium'), colors.heroRingHeating);
    expect(freshnessColor(ctx, 10, 'medium'), colors.success);
    expect(freshnessColor(ctx, 28, 'medium'), colors.success);
    expect(freshnessColor(ctx, 29, 'medium'), colors.textSecondary);
    // 16 days: medium is in its window, light still rests.
    expect(freshnessColor(ctx, 16, 'light'), colors.heroRingHeating);
    expect(freshnessColor(ctx, 28, 'light'), colors.success);
    expect(freshnessColor(ctx, 70, 'light'), colors.success);
    expect(freshnessColor(ctx, 71, 'light'), colors.textSecondary);
    expect(freshnessColor(ctx, 16, 'ultra-light'), colors.heroRingHeating);
    expect(freshnessColor(ctx, 40, 'ultra-light'), colors.success);
    // No roast level: like medium.
    expect(freshnessColor(ctx, 9), colors.heroRingHeating);
    expect(freshnessColor(ctx, 28), colors.success);
    expect(freshnessColor(ctx, 29), colors.textSecondary);
    expect(freshnessProgress(42), 0.5);
    expect(freshnessProgress(84), 1.0);
    expect(freshnessProgress(200), 1.0);
  });

  test('days since roast count calendar days across clock changes', () {
    // Spring forward (29 Mar 2026): local midnights only 23 h apart.
    expect(calendarDaysSince(DateTime(2026, 3, 20), DateTime(2026, 3, 30)), 10);
    // Fall back (25 Oct 2026), late in the evening.
    expect(
      calendarDaysSince(DateTime(2026, 10, 20), DateTime(2026, 11, 1, 23, 30)),
      12,
    );
    expect(calendarDaysSince(DateTime(2026, 11, 2), DateTime(2026, 11, 1)), 0);
  });
}

import 'package:beand/screens/settings/ai_settings_screen.dart';
import 'package:beand/screens/settings/settings_screen.dart';
import 'package:beand/screens/settings/settings_widgets.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings → AI, the UI. What is checked is what is an app rule and so must
// not get lost by accident: one card per page, the delete button at the
// bottom, and no state left over from the previous provider.

// Explanations sit behind an ⓘ (SettingsInfo), not as visible text.
Finder findInfo(String part) =>
    find.byWidgetPredicate((w) => w is SettingsInfo && w.text.contains(part));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(AiSettings settings) => ChangeNotifierProvider<AiSettings>.value(
    value: settings,
    child: MaterialApp(theme: buildAppTheme(), home: const AiSettingsScreen()),
  );

  testWidgets(
    'the main switch sits at the very top and clears everything below',
    (tester) async {
      final settings = AiSettings(
        keyStore: InMemoryAiKeyStore(),
        enabled: true,
      );
      await settings.setKey(AiProvider.gemini, 'AIza-test');
      await tester.pumpWidget(wrap(settings));

      // At the very top of the card and NEXT to the explanation — at the same
      // height, not above or below it.
      final master = find.byType(Switch).first;
      final note = find.text('Use your own AI key');
      expect(findInfo('no AI server of its own'), findsOneWidget);
      expect(
        (tester.getCenter(master).dy - tester.getCenter(note).dy).abs(),
        lessThan(40),
      );
      expect(
        tester.getCenter(master).dy,
        lessThan(tester.getTopLeft(find.text('Provider')).dy),
      );

      await tester.tap(master);
      await tester.pumpAndSettle();

      // Off means off: no settings visible any more.
      expect(settings.enabled, isFalse);
      for (final gone in [
        'Provider',
        'API key',
        'Model',
        'Test connection',
        'Remove Gemini key',
        ...AiFeature.values.map((f) => f.label),
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // Switch and explanation stay — otherwise there would be no way back.
      expect(find.byType(Switch), findsOneWidget);
      expect(note, findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Provider'), findsOneWidget);
      // The key survived switching off.
      expect(find.text('Stored in the device keystore'), findsOneWidget);
    },
  );

  testWidgets('when switched off no feature counts as enabled', (tester) async {
    final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await settings.setKey(AiProvider.gemini, 'AIza-test');
    expect(settings.isEnabled(AiFeature.beanForm), isTrue);

    await settings.setEnabled(false);
    // The provider is still set up — the app just does not use it.
    expect(settings.isConfigured, isTrue);
    for (final feature in AiFeature.values) {
      expect(settings.isEnabled(feature), isFalse);
    }
  });

  testWidgets('one card, all four providers, all three switches', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true)),
    );

    expect(find.byType(SettingsCard), findsOneWidget);
    for (final provider in AiProvider.values) {
      expect(find.text(provider.label), findsOneWidget);
    }
    for (final feature in AiFeature.values) {
      expect(find.text(feature.label), findsOneWidget);
    }
  });

  testWidgets('no delete button without a key, one at the bottom with a key', (
    tester,
  ) async {
    final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await tester.pumpWidget(wrap(settings));

    expect(find.text('No key for Gemini yet'), findsOneWidget);
    expect(find.textContaining('Remove'), findsNothing);

    await settings.setKey(AiProvider.gemini, 'AIza-test');
    await tester.pump();

    expect(find.text('Stored in the device keystore'), findsOneWidget);
    final remove = find.widgetWithText(AppButton, 'Remove Gemini key');
    expect(remove, findsOneWidget);
    // Destructive actions belong at the end of the page, not in the title bar.
    final removeBottom = tester.getBottomLeft(remove).dy;
    for (final feature in AiFeature.values) {
      expect(
        tester.getBottomLeft(find.text(feature.label)).dy,
        lessThan(removeBottom),
      );
    }
  });

  testWidgets('switching provider shows its notice and its model', (
    tester,
  ) async {
    final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await tester.pumpWidget(wrap(settings));

    expect(findInfo('free tier'), findsOneWidget);
    expect(find.text(AiProvider.gemini.defaultModel), findsOneWidget);

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();

    expect(findInfo('Anthropic'), findsOneWidget);
    expect(find.text('claude-sonnet-5-5'), findsOneWidget);
    // The free-tier notice belonged to Gemini and went with it.
    expect(findInfo('free tier'), findsNothing);
  });

  testWidgets('the model picker expands in the sheet', (tester) async {
    final settings = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await settings.setProvider(AiProvider.claude);
    await tester.pumpWidget(wrap(settings));

    // The card is taller than the test window — scroll there first.
    await tester.ensureVisible(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    // As long as nothing has been loaded, the built-in fallback list is
    // shown — with a notice saying so.
    expect(find.textContaining('Not fetched yet'), findsOneWidget);
    expect(find.text('Claude Haiku 4.5'), findsOneWidget);

    // The list sits further down in the card than the test window is tall —
    // scroll there first, otherwise the test taps into nothing.
    await tester.ensureVisible(find.text('Claude Haiku 4.5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Haiku 4.5'));
    await tester.pumpAndSettle();

    expect(settings.model, 'claude-haiku-4-5');
    expect(find.text('Claude Haiku 4.5'), findsNothing);
  });

  testWidgets('the AI is in the settings menu', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<AiSettings>.value(
            value: AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('AI'), findsOneWidget);
  });
}

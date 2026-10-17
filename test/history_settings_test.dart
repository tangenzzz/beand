import 'package:beand/screens/settings/history_settings_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/app_switch_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beand/screens/settings/settings_widgets.dart';

// History Settings: local analysis and AI analysis can be switched off
// here. The AI switch is the same as in Settings → AI.

// Explanations sit behind an ⓘ (SettingsInfo), not as visible text.
Finder findInfo(String part) =>
    find.byWidgetPredicate((w) => w is SettingsInfo && w.text.contains(part));

// Only the switch toggles (AppSwitchTile), not the label.
Finder switchOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  matching: find.byType(Switch),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('switches for local analysis and AI analysis', (tester) async {
    final app = AppSettings();
    final ai = AiSettings(keyStore: InMemoryAiKeyStore(), enabled: true);
    await ai.setProvider(AiProvider.claude);
    await ai.setKey(AiProvider.claude, 'sk-ant');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettings>.value(value: app),
          ChangeNotifierProvider<AiSettings>.value(value: ai),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const HistorySettingsScreen(),
        ),
      ),
    );

    expect(app.showShotFacts, isTrue);
    expect(ai.isFeatureOn(AiFeature.shotAnalysis), isTrue);
    expect(findInfo('Needs an AI API key'), findsOneWidget);

    await tester.tap(switchOf('Local analysis'));
    await tester.pump();
    expect(app.showShotFacts, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        AppSettings.showShotFactsPrefKey,
      ),
      isFalse,
    );

    await tester.tap(switchOf('AI analysis'));
    await tester.pump();
    expect(ai.isFeatureOn(AiFeature.shotAnalysis), isFalse);
    expect(ai.isEnabled(AiFeature.shotAnalysis), isFalse);

    // Without AI set up: grayed out and off, tapping changes nothing.
    await tester.tap(switchOf('AI analysis'));
    await tester.pump();
    expect(ai.isFeatureOn(AiFeature.shotAnalysis), isTrue);
    await ai.setEnabled(false);
    await tester.pump();
    final aiSwitch = tester.widget<AppSwitchTile>(
      find.ancestor(
        of: find.text('AI analysis'),
        matching: find.byType(AppSwitchTile),
      ),
    );
    expect(aiSwitch.onChanged, isNull);
    expect(aiSwitch.value, isFalse);
    await tester.tap(switchOf('AI analysis'));
    await tester.pump();
    expect(ai.isFeatureOn(AiFeature.shotAnalysis), isTrue);
  });
}

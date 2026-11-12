import 'package:beand/screens/settings/bag_level_settings_screen.dart';
import 'package:beand/screens/settings/beans_settings_screen.dart';
import 'package:beand/screens/settings/settings_widgets.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Beans → Bag level opens a page with switch and Empty below', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettings>.value(value: settings),
          ChangeNotifierProvider<AiSettings>(
            create: (_) => AiSettings(keyStore: InMemoryAiKeyStore()),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const BeansSettingsScreen(),
        ),
      ),
    );
    // Freshness ring and AI fill; Bag level is a row now.
    expect(find.byType(Switch), findsNWidgets(2));
    await tester.tap(find.text('Bag level'));
    await tester.pumpAndSettle();
    expect(find.byType(BagLevelSettingsScreen), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    // The whole label is readable, not cut with an ellipsis.
    final label = tester.renderObject<RenderParagraph>(
      find.text('Empty below'),
    );
    expect(label.didExceedMaxLines, isFalse);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SettingsInfo &&
            w.text ==
                'A bag below this is automatically marked as empty. 0 = off.',
      ),
      findsOneWidget,
    );
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/machine_profile.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/inline_picker.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/screens/live/ruler_picker.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// The tests check the default appearance: dark with teal.
final _theme = AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal);

class FakeService extends MeticulousSocketService {
  FakeService() : super(hostname: 'unreachable.local');

  final hovered = <String>[];

  void setActive(String id, String name) {
    latestStatus = MachineStatus.fromJson({
      'id': id,
      'loaded_profile': name,
      'name': 'idle',
    });
    notifyListeners();
  }

  @override
  Future<List<MachineProfile>> fetchProfiles() async => const [
    MachineProfile(
      id: 'p1',
      name: 'Soup',
      temperature: 82,
      finalWeight: 36,
      accentColor: Colors.orange,
    ),
    MachineProfile(
      id: 'p2',
      name: 'Classic',
      temperature: 93,
      finalWeight: 40,
      accentColor: Colors.blue,
    ),
  ];

  @override
  void hoverProfile(String id, String name) => hovered.add(id);
}

void main() {
  testWidgets('Pre Shot: bean and profile dropdown lists', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    // A real (tiny) image on disk: the avatar only shows a file if it
    // really exists.
    final picDir = Directory.systemTemp.createTempSync('beand_profile_pics');
    final photo = File(p.join(picDir.path, 'soup.png'))
      ..writeAsBytesSync(_onePixelPng);
    addTearDown(() => picDir.deleteSync(recursive: true));
    await tester.runAsync(() async {
      for (final name in ['Kiambu', 'Guji']) {
        await db.insertBean(
          BeansCompanion.insert(name: name, roaster: const Value('Bonanza')),
        );
      }
      // The machine doesn't deliver images — they are in the local copy
      // (they used to be missing from the list).
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'p1',
          name: 'Soup',
          json: '{"id":"p1","name":"Soup"}',
          fetchedAt: DateTime(2026, 9, 30),
          customImagePath: Value(photo.path),
        ),
      );
    });
    final service = FakeService();
    final extra = <double>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<ShotSetup>.value(value: ShotSetup.inMemory()),
          ChangeNotifierProvider<MeticulousSocketService>.value(value: service),
          // The same machine again under the shared interface: the
          // Pre-Shot card talks to it through that.
          ChangeNotifierProvider<EspressoMachine>.value(value: service),
          ChangeNotifierProvider<GaggiMateService>.value(
            value: offlineGaggiMate(),
          ),
          ChangeNotifierProvider<LiveShotService>.value(
            value: MeticulousLiveShotService(service)..start(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreShotCard(onExtraHeight: extra.add),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    // Expand bean: sorted by roaster, then name; "+" present.
    await tester.tap(find.text('Select bean'));
    await tester.pump();
    expect(extra.last, InlinePicker.heightFor(2));
    // The search/plus row is at the very bottom, below the list.
    expect(
      tester.getTopLeft(find.byTooltip('Search')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('Kiambu')).dy),
    );
    // The triggering row is not highlighted.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                _theme.accent.withValues(alpha: 0.08),
      ),
      findsNothing,
    );
    expect(find.textContaining('Guji'), findsOneWidget);
    expect(find.textContaining('Kiambu'), findsOneWidget);
    expect(find.byTooltip('Add bean'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);

    // Search filters.
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'guj');
    await tester.pump();
    expect(find.textContaining('Kiambu'), findsNothing);
    await tester.tap(find.textContaining('Guji'));
    await tester.pump();
    expect(extra.last, 0, reason: 'selection collapses the list');
    expect(find.text('Guji'), findsOneWidget);
    expect(find.text('Select bean'), findsNothing);

    // Without a selection the row shows the profile loaded on the machine.
    expect(find.text('Select profile'), findsOneWidget);
    service.setActive('p1', 'Soup');
    await tester.pump();
    expect(find.text('Soup'), findsOneWidget);
    service.setActive('', '');
    await tester.pump();

    // Expand profile (without "+"), selection only calls hoverProfile.
    await tester.tap(find.text('Select profile'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Soup'), findsWidgets);
    expect(find.textContaining('Classic'), findsOneWidget);
    // Exactly the one profile with a local image shows it; the other keeps
    // its color.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    // cacheWidth wraps the provider in a ResizeImage — the file is inside
    // it.
    final files = [
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        ?_fileOf(image.image),
    ];
    expect(files, [photo.path], reason: 'only the profile with its own photo');
    expect(find.byTooltip('Add bean'), findsNothing);
    expect(extra.last, InlinePicker.heightFor(2));
    await tester.tap(find.textContaining('Classic'));
    await tester.pump();
    expect(service.hovered, ['p2']);
    expect(find.text('Classic'), findsOneWidget);
    expect(extra.last, 0);

    // Only one list is ever open.
    await tester.tap(find.text('Guji'));
    await tester.pump();
    await tester.tap(find.text('Classic'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Add bean'), findsNothing);

    // Dose: as long as nothing has been brewed with the profile, the row
    // shows a dash; the ruler still opens at the suggested value so you
    // don't start at 5 g.
    expect(find.text('—'), findsNWidgets(2), reason: 'Dose and Grind empty');
    await tester.tap(find.text('—').first);
    await tester.pump();
    expect(find.byType(RulerPicker), findsOneWidget);
    expect(extra.last, RulerPicker.height);
    expect(find.text('18.0  g'), findsOneWidget);
    await tester.drag(
      find.descendant(
        of: find.byType(RulerPicker),
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(-100, 0), // left = value rises (10 px per 0.1, minus slop)
    );
    await tester.pumpAndSettle();
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan?.toPlainText() ?? '')
        .firstWhere((t) => RegExp(r'^\d+\.\d  g$').hasMatch(t));
    final value = double.parse(shown.split(' ').first);
    expect(value, inInclusiveRange(18.5, 19.0), reason: 'snaps to 0.1 steps');
    final rowText = '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} g';
    expect(find.text(rowText), findsOneWidget, reason: 'row updates live');

    // Direct input via the keyboard icon.
    await tester.tap(find.byTooltip('Type value'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '17,3');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('17.3  g'), findsOneWidget);
    expect(find.text('17.3 g'), findsOneWidget);

    // Grind opens its own ruler (without unit) and closes Dose.
    // Still empty here too: the row shows the dash.
    await tester.tap(find.text('—'));
    await tester.pump();
    expect(find.byType(RulerPicker), findsOneWidget);
    // The ruler starts at the suggested value, the row stays empty until
    // something is actually set.
    expect(find.text('3.2'), findsWidgets);
    expect(find.text('—'), findsOneWidget, reason: 'only the Grind row left');
    // Tapping the row again collapses the ruler.
    await tester.tap(find.text('—'));
    await tester.pump();
    expect(extra.last, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  test('dropdown list height: constant from 4 entries on (scrolls)', () {
    expect(InlinePicker.heightFor(0), InlinePicker.heightFor(1));
    expect(InlinePicker.heightFor(6), InlinePicker.heightFor(4));
    expect(InlinePicker.heightFor(4) > InlinePicker.heightFor(3), true);
  });
}

// 1×1 transparent PNG.
const _onePixelPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

// Gets the file path from an image provider, even if it is wrapped in a
// ResizeImage (because of cacheWidth).
String? _fileOf(ImageProvider provider) => switch (provider) {
  FileImage(:final file) => file.path,
  ResizeImage(:final imageProvider) => _fileOf(imageProvider),
  _ => null,
};

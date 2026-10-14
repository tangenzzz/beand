import 'dart:async';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/screens/history/history_widgets.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/profile_images.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

// Regression: profile images were missing in the history. A shot only
// carries the image copy created on import — GaggiMate shots get none (the
// machine has no images), and a photo chosen later would be missing on all
// shots already imported. So the history falls back to the profile's
// current image.
void main() {
  late Directory dir;
  late File photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('beand_shot_avatar');
    photo = File(p.join(dir.path, 'profil.png'))
      ..writeAsBytesSync(_onePixelPng);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Shot shot({
    String machine = 'gaggimate',
    String? profileName = 'Default',
    String? imagePath,
  }) => Shot(
    syncId: 'test',
    updatedAt: 0,
    syncState: SyncState.pending,
    id: 1,
    timestamp: DateTime(2026, 9, 30),
    machine: machine,
    profileName: profileName,
    profileImagePath: imagePath,
    createdAt: DateTime(2026, 9, 30),
  );

  Bean bean({String name = 'Ethiopia', String? photoPath}) => Bean(
    syncId: 'test',
    updatedAt: 0,
    syncState: SyncState.pending,
    deleted: false,
    id: 7,
    name: name,
    photoPath: photoPath,
    isBlend: false,
    isFrozen: false,
    createdAt: DateTime(2026, 9, 30),
  );

  Future<void> pumpAvatar(
    WidgetTester tester,
    Shot value, {
    ProfileImages? images,
    Bean? shotBean,
    HistoryAvatar? avatarSource,
  }) async {
    Widget avatar = ShotAvatar(shot: value, bean: shotBean);
    if (images != null) {
      avatar = ChangeNotifierProvider<ProfileImages>.value(
        value: images,
        child: avatar,
      );
    }
    // Without settings in the tree the circle must use the default — the
    // older tests here check that too.
    if (avatarSource != null) {
      avatar = ChangeNotifierProvider<AppSettings>.value(
        value: AppSettings(historyAvatar: avatarSource),
        child: avatar,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: avatar),
      ),
    );
    await tester.pump();
  }

  List<String> filesIn(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      ?_fileOf(image.image),
  ];

  // A stored profile, as the sync stores it.
  StoredProfile stored(String imagePath) => StoredProfile(
    syncId: 'test',
    updatedAt: 0,
    syncState: SyncState.pending,
    deleted: false,
    id: 'g1',
    machine: 'gaggimate',
    name: 'Default',
    json: '{"id":"g1","label":"Default"}',
    position: 0,
    fetchedAt: DateTime(2026, 9, 30),
    customImagePath: imagePath,
  );

  // Returns an index that already knows the given profiles.
  Future<ProfileImages> indexWith(
    WidgetTester tester,
    List<StoredProfile> profiles,
  ) async {
    final controller = StreamController<List<StoredProfile>>();
    final images = ProfileImages(controller.stream);
    controller.add(profiles);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    addTearDown(() {
      images.dispose();
      controller.close();
    });
    return images;
  }

  testWidgets('without its own image the profile image is used', (
    tester,
  ) async {
    final images = await indexWith(tester, [stored(photo.path)]);

    await pumpAvatar(tester, shot(), images: images);
    expect(filesIn(tester), [photo.path]);
  });

  testWidgets('the image on the shot itself takes precedence', (tester) async {
    final own = File(p.join(dir.path, 'am_shot.png'))
      ..writeAsBytesSync(_onePixelPng);
    final images = await indexWith(tester, [stored(photo.path)]);

    await pumpAvatar(tester, shot(imagePath: own.path), images: images);
    expect(filesIn(tester), [own.path]);
  });

  testWidgets('a profile of another machine does not count', (tester) async {
    final images = await indexWith(tester, [stored(photo.path)]);

    // Same profile name, different machine.
    await pumpAvatar(tester, shot(machine: 'meticulous'), images: images);
    expect(filesIn(tester), isEmpty);
  });

  // Settings → History: profile photo or photo of the bean used.
  testWidgets('bean chosen: its photo is in the circle, not the profile one', (
    tester,
  ) async {
    final beanPhoto = File(p.join(dir.path, 'bohne.png'))
      ..writeAsBytesSync(_onePixelPng);

    await pumpAvatar(
      tester,
      shot(imagePath: photo.path),
      shotBean: bean(photoPath: beanPhoto.path),
      avatarSource: HistoryAvatar.bean,
    );
    expect(filesIn(tester), [beanPhoto.path]);
  });

  testWidgets('bean chosen, but without photo: profile photo as fallback', (
    tester,
  ) async {
    await pumpAvatar(
      tester,
      shot(imagePath: photo.path),
      shotBean: bean(),
      avatarSource: HistoryAvatar.bean,
    );
    expect(filesIn(tester), [photo.path]);
  });

  testWidgets('profile chosen, but without photo: bean photo as fallback', (
    tester,
  ) async {
    final beanPhoto = File(p.join(dir.path, 'bohne.png'))
      ..writeAsBytesSync(_onePixelPng);

    await pumpAvatar(
      tester,
      shot(),
      shotBean: bean(photoPath: beanPhoto.path),
      avatarSource: HistoryAvatar.profile,
    );
    expect(filesIn(tester), [beanPhoto.path]);
  });

  testWidgets('bean chosen, no photo: initial of the BEAN', (tester) async {
    await pumpAvatar(
      tester,
      shot(),
      shotBean: bean(name: 'Ethiopia'),
      avatarSource: HistoryAvatar.bean,
    );
    expect(filesIn(tester), isEmpty);
    expect(find.text('E'), findsOneWidget, reason: 'not "D" from "Default"');
  });

  testWidgets('without an index it stays with the initial', (tester) async {
    await pumpAvatar(tester, shot());
    expect(filesIn(tester), isEmpty);
    expect(find.text('D'), findsOneWidget);
  });
}

String? _fileOf(ImageProvider provider) => switch (provider) {
  FileImage(:final file) => file.path,
  ResizeImage(:final imageProvider) => _fileOf(imageProvider),
  _ => null,
};

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

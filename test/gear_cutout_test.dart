import 'dart:io';
import 'dart:typed_data';

import 'package:beand/models/gear.dart';
import 'package:beand/screens/settings/gear_photo_preview.dart';
import 'package:beand/services/gear_cutout.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Gear photo cutout (My Coffee Desk): the platform delivers only a mask;
// cropping, edge and grading happen in Dart and are tested here.
void main() {
  // 400×300 photo: gray wall, a dark "machine" from x 150..249, y 100..279.
  Uint8List photo() {
    final im = img.Image(width: 400, height: 300);
    img.fill(im, color: img.ColorRgb8(200, 200, 190));
    img.fillRect(
      im,
      x1: 150,
      y1: 100,
      x2: 249,
      y2: 279,
      color: img.ColorRgb8(60, 50, 40),
    );
    return img.encodeJpg(im, quality: 95);
  }

  // Mask at 320×320 as from U²-Net: the same region, scaled.
  Uint8List mask({bool empty = false}) {
    final m = Uint8List(320 * 320);
    if (empty) return m;
    for (var y = 0; y < 320; y++) {
      for (var x = 0; x < 320; x++) {
        final px = x * 400 / 320, py = y * 300 / 320;
        if (px >= 150 && px < 250 && py >= 100 && py < 280) {
          m[y * 320 + x] = 255;
        }
      }
    }
    return m;
  }

  group('composeCutout', () {
    test('crops to the piece, background transparent, piece solid', () {
      final png = composeCutout(photo(), mask(), 320, 320)!;
      final out = img.decodePng(png)!;
      expect(out.numChannels, 4);
      // About the subject plus 8 px room on each side.
      expect(out.width, inInclusiveRange(110, 122));
      expect(out.height, inInclusiveRange(190, 202));
      expect(out.getPixel(0, 0).a, 0, reason: 'corner is background');
      final middle = out.getPixel(out.width ~/ 2, out.height ~/ 2);
      expect(middle.a, 255);
    });

    test('no clear subject: null, the caller keeps the photo', () {
      expect(composeCutout(photo(), mask(empty: true), 320, 320), isNull);
      final full = Uint8List(320 * 320)..fillRange(0, 320 * 320, 255);
      expect(composeCutout(photo(), full, 320, 320), isNull);
      expect(composeCutout(photo(), Uint8List(10), 320, 320), isNull);
    });
  });

  test('grade stretches the subject range and stays in 0..1', () {
    const grade = SubjectGrade(0.2, 0.6);
    final (r0, g0, b0) = grade.apply(0.2, 0.2, 0.2);
    final (r1, g1, b1) = grade.apply(0.6, 0.6, 0.6);
    expect(r0 + g0 + b0, lessThan(0.05));
    expect(g1, closeTo(1, 0.01));
    expect(r1, lessThanOrEqualTo(1));
    // Slightly warm: a gray gets a touch more red than blue.
    final (r, _, b) = grade.apply(0.4, 0.4, 0.4);
    expect(r, greaterThan(b));
  });

  group('GearStore photos', () {
    late Directory docs;
    late GearStore store;
    late String picked;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('gear_photos');
      store = GearStore.inMemory(
        gear: const [Gear(id: 'm', type: GearType.machine, model: 'M')],
        docsPath: docs.path,
      );
      picked = p.join(docs.path, 'picked.jpg');
      File(picked).writeAsBytesSync(photo());
    });
    tearDown(() => docs.deleteSync(recursive: true));

    test('cut-out shown, original kept; back to the original', () async {
      final cut = composeCutout(photo(), mask(), 320, 320)!;
      await store.setPhoto('m', picked, cutout: cut);
      final g = store.byId('m')!;
      expect(g.isCutout, isTrue);
      expect(g.photoPath, endsWith('_cut.png'));
      expect(p.isRelative(g.photoPath!), isTrue, reason: 'backup-proof');
      expect(store.photoFile(g), isNotNull);
      expect(store.originalPhotoFile(g), isNotNull);
      expect(Gear.fromJson(g.toJson()), g);

      final cutFile = store.photoFile(g)!;
      store.useOriginalPhoto('m');
      final back = store.byId('m')!;
      expect(back.isCutout, isFalse);
      expect(back.photoPath, g.photoOriginalPath);
      expect(cutFile.existsSync(), isFalse, reason: 'cut-out file removed');

      // Cut out again later from the photo that is there.
      await store.applyCutout('m', cut);
      expect(store.byId('m')!.isCutout, isTrue);
      expect(store.byId('m')!.photoOriginalPath, back.photoPath);
    });

    test('remove photo deletes both files', () async {
      await store.setPhoto(
        'm',
        picked,
        cutout: composeCutout(photo(), mask(), 320, 320),
      );
      final g = store.byId('m')!;
      final files = [store.photoFile(g)!, store.originalPhotoFile(g)!];
      store.removePhoto('m');
      expect(store.byId('m')!.photoPath, isNull);
      expect(store.byId('m')!.photoOriginalPath, isNull);
      expect(files.any((f) => f.existsSync()), isFalse);
    });
  });

  testWidgets('preview: Use returns the cut-out, Original keeps the photo', (
    tester,
  ) async {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 4, height: 4, numChannels: 4)),
    );
    (PhotoChoice, Uint8List?)? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showCutoutPreview(
              context,
              'unused.jpg',
              cutout: (_) async => png,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ShelfPreview), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(choice?.$1, PhotoChoice.cutout);
    expect(choice?.$2, png);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    expect(choice?.$1, PhotoChoice.original);
  });
}

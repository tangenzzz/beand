import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/database/path_repair.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// iOS moves the app folder on updates (new container UUID): stored photo
// paths must follow it, or photos vanish and never sync again.
void main() {
  late Directory root;
  late AppDatabase db;

  setUp(() {
    root = Directory.systemTemp.createTempSync('path_repair');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  String oldDocs() => p.join(root.path, 'OLD-UUID', 'Documents');

  Directory newDocs() =>
      Directory(p.join(root.path, 'NEW-UUID', 'Documents'))
        ..createSync(recursive: true);

  Future<Bean> bean(int id) =>
      (db.select(db.beans)..where((b) => b.id.equals(id))).getSingle();

  test('moves paths from the old app folder onto the new one', () async {
    final docs = newDocs();
    File(p.join(docs.path, 'bean_photos', 'a.jpg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final id = await db
        .into(db.beans)
        .insert(
          BeansCompanion.insert(
            name: 'Guji',
            photoPath: Value(p.join(oldDocs(), 'bean_photos', 'a.jpg')),
          ),
        );

    expect(await repairFilePaths(db, docs.path), 1);
    expect(
      (await bean(id)).photoPath,
      p.join(docs.path, 'bean_photos', 'a.jpg'),
    );
    // A second launch changes nothing.
    expect(await repairFilePaths(db, docs.path), 0);
  });

  test('a lost photo that is on a photo server gets fetched again', () async {
    final docs = newDocs();
    final id = await db
        .into(db.beans)
        .insert(
          BeansCompanion.insert(
            name: 'Guji',
            photoPath: Value(p.join(oldDocs(), 'bean_photos', 'gone.jpg')),
            photoBlob: const Value('{"sha256":"ab"}'),
          ),
        );

    await repairFilePaths(db, docs.path);
    final b = await bean(id);
    expect(b.photoPath, isNull);
    expect(b.photoBlob, isNotNull);
    expect((await db.syncDao.beansMissingPhoto()).map((b) => b.id), [id]);
  });

  test('a lost photo without a server copy keeps its path', () async {
    final docs = newDocs();
    final old = p.join(oldDocs(), 'bean_photos', 'gone.jpg');
    final id = await db
        .into(db.beans)
        .insert(BeansCompanion.insert(name: 'Guji', photoPath: Value(old)));

    expect(await repairFilePaths(db, docs.path), 0);
    expect((await bean(id)).photoPath, old);
  });
}

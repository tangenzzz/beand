import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/backup_settings_screen.dart';
import 'package:beand/services/backup_service.dart';
import 'package:beand/sync/crypto/backup_cipher.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// Settings → Backup: "Encrypt whole backup" when creating, password prompt
// when restoring.

void main() {
  testWidgets('create encrypted, restore with password', (tester) async {
    late Directory root;
    late Directory docs;
    late AppDatabase db;
    late BackupService service;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync('beand_backup_screen');
      docs = Directory(p.join(root.path, 'docs'))..createSync();
      db = AppDatabase(
        NativeDatabase(File(p.join(docs.path, backupDbFileName))),
      );
      await db.insertBean(BeansCompanion.insert(name: 'Guji'));
      service = BackupService(
        db: db,
        docsDir: docs,
        prefs: await SharedPreferences.getInstance(),
        openRestoredDb: (file) => AppDatabase(NativeDatabase(file)),
      );
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final cache = p.join(root.path, 'cache');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache,
    );

    Uint8List? saved;
    String? savedName;
    final picked = p.join(root.path, 'picked.beandbak');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BackupSettingsScreen(
          service: service,
          saveBackupFile: (name, bytes) async {
            savedName = name;
            saved = bytes;
            return Uri.file(name);
          },
          pickBackupFile: () async => picked,
        ),
      ),
    );

    // Create: dialog, encryption on, password twice.
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('encrypt-backup')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Without it the backup is lost.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret12',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat password'),
      'secret12',
    );
    await tester.tap(find.text('Create'));
    for (var i = 0; i < 100 && saved == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(savedName, endsWith('.beandbak'));
    await tester.runAsync(() async {
      File(picked).writeAsBytesSync(saved!);
    });
    expect(isEncryptedBackup(File(picked)), isTrue);

    // Restore: first a wrong, then the right password.
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.tap(find.text('Restore from backup'));
    await settle();
    expect(find.text('Encrypted backup'), findsOneWidget);
    expect(find.text('Create'), findsNothing);
    await tester.enterText(find.byType(TextField), 'wrong123');
    await tester.tap(find.text('OK'));
    await settle();
    expect(find.text('Wrong password.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'secret12');
    await tester.tap(find.text('OK'));
    await settle();
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('1 beans'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await settle();
    expect(find.text('Restored'), findsOneWidget);

    // The decrypted copy in the cache is gone again.
    await tester.runAsync(() async {
      expect(Directory(p.join(cache, 'restore')).existsSync(), isFalse);
      final restored = AppDatabase(
        NativeDatabase(File(p.join(docs.path, backupDbFileName))),
      );
      expect((await restored.select(restored.beans).get()).single.name, 'Guji');
      await restored.close();
    });
  });
}

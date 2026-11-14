import 'package:beand/screens/settings/backup_dialogs.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The two password fields of a new backup: "Next" moves to the second
// field and keeps the keyboard open (the dialog no longer slides down
// between the two), "Done" in the second creates the backup.
void main() {
  testWidgets('Next goes to the repeat field, Done submits', (tester) async {
    BackupOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showBackupOptionsDialog(
              context,
              hasSyncKey: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('backup-password'));
    final second = find.byKey(const ValueKey('backup-password-repeat'));
    await tester.tap(first);
    await tester.enterText(first, 'secret123');
    expect(
      tester.widget<TextField>(first).textInputAction,
      TextInputAction.next,
    );
    expect(tester.widget<TextField>(first).autofillHints, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final secondField = tester.widget<TextField>(second);
    expect(secondField.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'keyboard stays');

    await tester.enterText(second, 'secret123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result?.password, 'secret123');
  });
}

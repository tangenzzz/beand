import 'package:shared_preferences/shared_preferences.dart';

// What the app remembers about its first days: whether the introduction was
// finished, when it was first opened, and whether the backup reminder has
// been shown.

const _onboardingDoneKey = 'onboarding_done';
const _firstOpenKey = 'first_open_at';
const _backupReminderShownKey = 'backup_reminder_shown';

class FirstRun {
  const FirstRun(this.prefs);

  final SharedPreferences prefs;

  /// How long the app is used before it mentions backups.
  static const backupReminderAfter = Duration(days: 7);

  /// Show the introduction? Not to someone who already has data, like an
  /// update from an older version or a restored backup. [hasData] is only
  /// called when the answer is still open, so later starts skip the query.
  Future<bool> needsOnboarding(Future<bool> Function() hasData) async {
    if (prefs.getBool(_onboardingDoneKey) ?? false) return false;
    if (await hasData()) {
      await finishOnboarding();
      return false;
    }
    return true;
  }

  Future<void> finishOnboarding() => prefs.setBool(_onboardingDoneKey, true);

  /// Due once, a week after the first start, and only while auto backup is
  /// off. Counts as shown from here on.
  Future<bool> takeBackupReminder({
    required bool autoBackupOn,
    required DateTime now,
  }) async {
    final stored = prefs.getInt(_firstOpenKey);
    if (stored == null) {
      await prefs.setInt(_firstOpenKey, now.millisecondsSinceEpoch);
      return false;
    }
    if (prefs.getBool(_backupReminderShownKey) ?? false) return false;
    final firstOpen = DateTime.fromMillisecondsSinceEpoch(stored);
    if (autoBackupOn || now.difference(firstOpen) < backupReminderAfter) {
      return false;
    }
    await prefs.setBool(_backupReminderShownKey, true);
    return true;
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;

// Replacing the contents of the app folder during a restore. The new contents
// are unpacked and checked in a staging folder first; only then do the two
// sets of files change places, by renaming within one volume. These folders
// live inside the app folder because iOS allows no siblings of Documents.

const _stagingName = '.restore-new';
const _previousName = '.restore-old';

/// Inside the previous folder: all old files have been moved out of the app
/// folder, so whatever is there now comes from the backup.
const _oldFilesMovedName = '.moved';

Directory restoreStagingDir(Directory docs) =>
    Directory(p.join(docs.path, _stagingName));

/// Whether [relativePath] (from the app folder) is restore work in progress.
bool isRestoreWorkPath(String relativePath) {
  final first = p.split(relativePath).first;
  return first == _stagingName || first == _previousName;
}

Directory _previous(Directory docs) =>
    Directory(p.join(docs.path, _previousName));

Iterable<FileSystemEntity> _appFiles(Directory docs) => docs.listSync().where(
  (e) => !isRestoreWorkPath(p.relative(e.path, from: docs.path)),
);

/// Puts the staged files in place of the current ones. The current files stay
/// complete until the staging folder is gone, so an interruption before that
/// can be undone by [recoverInterruptedRestore].
void swapInRestoredFiles(Directory docs) {
  final staging = restoreStagingDir(docs);
  final previous = _previous(docs)..createSync();
  for (final entity in _appFiles(docs)) {
    entity.renameSync(p.join(previous.path, p.basename(entity.path)));
  }
  File(p.join(previous.path, _oldFilesMovedName)).createSync();
  for (final entity in staging.listSync()) {
    entity.renameSync(p.join(docs.path, p.basename(entity.path)));
  }
  staging.deleteSync();
  previous.deleteSync(recursive: true);
}

/// Cleans up after a restore that did not finish: before the swap the staging
/// folder is dropped, during it the old files go back, after it only the old
/// copy is left to delete. Call before the database is opened.
void recoverInterruptedRestore(Directory docs) {
  final staging = restoreStagingDir(docs);
  final previous = _previous(docs);
  if (!previous.existsSync()) {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    return;
  }
  if (!staging.existsSync()) {
    previous.deleteSync(recursive: true);
    return;
  }
  final marker = File(p.join(previous.path, _oldFilesMovedName));
  if (marker.existsSync()) {
    for (final entity in _appFiles(docs)) {
      entity.deleteSync(recursive: true);
    }
    marker.deleteSync();
  }
  for (final entity in previous.listSync()) {
    entity.renameSync(p.join(docs.path, p.basename(entity.path)));
  }
  previous.deleteSync();
  staging.deleteSync(recursive: true);
}

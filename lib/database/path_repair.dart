import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'database.dart';

/// Columns that hold absolute file paths inside the app's documents folder.
const filePathColumns = <String, List<String>>{
  'beans': ['photo_path'],
  'shots': ['shot_photo_path', 'profile_image_path'],
  'stored_profiles': ['image_path', 'custom_image_path'],
};

/// Photo columns whose file can be fetched again from the photo servers:
/// when the file is gone, the path is cleared so the sync downloads it.
const _refetchable = <String, (String path, String blob)>{
  'beans': ('photo_path', 'photo_blob'),
  'stored_profiles': ('custom_image_path', 'custom_image_blob'),
};

/// iOS moves the app's data container to a new folder (new UUID) on app
/// updates, so absolute paths stored by an older install point nowhere.
/// Rewrites every stored path that lies outside the current [docs] folder
/// onto it, when the file exists there under the same relative name. Paths
/// to photos that are gone anyway, but still on a photo server, are cleared
/// so the next sync fetches them again. Returns how many paths changed.
Future<int> repairFilePaths(AppDatabase db, String docs) async {
  final docsDir = p.normalize(docs);
  final marker = '${p.separator}${p.basename(docsDir)}${p.separator}';
  var changed = 0;
  for (final MapEntry(key: table, value: columns) in filePathColumns.entries) {
    for (final column in columns) {
      final rows = await db
          .customSelect(
            'SELECT rowid AS rid, $column AS path FROM $table '
            "WHERE $column IS NOT NULL AND $column != '' "
            "AND $column NOT LIKE ? || '%'",
            variables: [Variable.withString('$docsDir${p.separator}')],
          )
          .get();
      for (final row in rows) {
        final old = row.read<String>('path');
        if (File(old).existsSync()) continue;
        final at = old.lastIndexOf(marker);
        if (at < 0) continue;
        final moved = p.join(docsDir, old.substring(at + marker.length));
        if (!File(moved).existsSync()) continue;
        await db.customUpdate(
          'UPDATE $table SET $column = ? WHERE rowid = ?',
          variables: [
            Variable.withString(moved),
            Variable.withInt(row.read<int>('rid')),
          ],
          updates: {},
        );
        changed++;
      }
    }
  }
  for (final MapEntry(key: table, value: (path, blob))
      in _refetchable.entries) {
    final rows = await db
        .customSelect(
          'SELECT rowid AS rid, $path AS path FROM $table '
          'WHERE $path IS NOT NULL AND $blob IS NOT NULL',
        )
        .get();
    for (final row in rows) {
      if (File(row.read<String>('path')).existsSync()) continue;
      await db.customUpdate(
        'UPDATE $table SET $path = NULL WHERE rowid = ?',
        variables: [Variable.withInt(row.read<int>('rid'))],
        updates: {},
      );
      changed++;
    }
  }
  if (changed > 0) debugPrint('Repaired $changed stored file paths');
  return changed;
}

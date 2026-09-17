import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';

class PublicMirrorService {
  static const _folderName = 'PhoneBookApp/data';

  Future<Directory> _dir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> mirrorContacts(List<Map<String, dynamic>> rows) async {
    final dir = await _dir();
    await File(p.join(dir.path, 'contacts.json')).writeAsString(jsonEncode(rows));
  }

  Future<void> mirrorCalls(List<Map<String, dynamic>> rows) async {
    final dir = await _dir();
    await File(p.join(dir.path, 'calls.json')).writeAsString(jsonEncode(rows));
  }

  Future<void> mirrorActivityLogs(List<Map<String, dynamic>> rows) async {
    final dir = await _dir();
    await File(p.join(dir.path, 'activity_log.json')).writeAsString(jsonEncode(rows));
  }

  /// Reads whatever mirror files exist and inserts any rows not
  /// already present (matched by primary key) into the live
  /// database. `ConflictAlgorithm.ignore` makes this safe to run
  /// repeatedly and safe to run on a non-empty database — it only
  /// ever adds rows, never overwrites or deletes anything.
  Future<({int contacts, int calls, int logs})> restoreFromMirror() async {
    final dir = await _dir();
    final db = await DbHelper.instance.database;

    Future<int> restoreTable(String fileName, String table) async {
      final file = File(p.join(dir.path, fileName));
      if (!await file.exists()) return 0;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return 0;

      final list = jsonDecode(content) as List;
      int count = 0;
      for (final row in list) {
        final id = await db.insert(
          table,
          Map<String, dynamic>.from(row as Map),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id != 0) count++;
      }
      return count;
    }

    final contacts = await restoreTable('contacts.json', 'contacts');
    final calls = await restoreTable('calls.json', 'call_records');
    final logs = await restoreTable('activity_log.json', 'activity_logs');

    return (contacts: contacts, calls: calls, logs: logs);
  }

  Future<String> mirrorFolderPath() async => (await _dir()).path;
}

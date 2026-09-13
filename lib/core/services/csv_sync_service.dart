import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import '../models/contact_model.dart';

/// Writes the full contact list to a CSV file inside the public
/// Downloads folder so it is visible in any file manager app.
/// Called automatically after every contact insert/update/delete.
class CsvSyncService {
  static const String _fileName = 'phonebook_contacts.csv';
  static const String _folderName = 'PhoneBookApp';

  /// Returns the folder where the CSV lives, creating it if needed.
  Future<Directory> _targetDirectory() async {
    // getDownloadsDirectory() maps to the public Downloads folder on
    // Android (path_provider >= 2.1). Falls back to app documents
    // directory if unavailable (e.g. some older OEM ROMs).
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();

    final target = Directory(p.join(base.path, _folderName));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<File> get _csvFile async {
    final dir = await _targetDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Rebuilds the CSV file from the current contact list.
  /// Safe to call after any single contact change — it always
  /// writes the full, current snapshot so the file never drifts.
  Future<void> syncContacts(List<ContactModel> contacts) async {
    final rows = <List<dynamic>>[
      ['id', 'first_name', 'last_name', 'phones', 'emails', 'is_favorite', 'updated_at'],
    ];

    for (final c in contacts) {
      final phonesJoined = c.phones.map((ph) => '${ph.label}:${ph.number}').join('; ');
      final emailsJoined = c.emails.map((em) => '${em.label}:${em.email}').join('; ');
      rows.add([
        c.id,
        c.firstName,
        c.lastName,
        phonesJoined,
        emailsJoined,
        c.isFavorite ? 1 : 0,
        c.updatedAt.toIso8601String(),
      ]);
    }

    final csvString = const ListToCsvConverter().convert(rows);
    final file = await _csvFile;
    await file.writeAsString(csvString, flush: true);
  }

  Future<String> currentCsvPath() async => (await _csvFile).path;
}

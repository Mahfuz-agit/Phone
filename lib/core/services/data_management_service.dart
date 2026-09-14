import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/contact_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/contact_repository.dart';

/// Handles the two "move data in/out of the app" flows that don't
/// belong to a single feature: vCard (.vcf) import/export for
/// contacts, and full app Backup/Restore (SQLite DB + recordings
/// folder zipped together). Kept in one file per the "fewer files"
/// instruction.
class DataManagementService {
  final _contactRepo = ContactRepository();
  final _activityLog = ActivityLogRepository();

  // ===================================================================
  // vCard (.vcf) export/import
  // ===================================================================

  /// Builds a single .vcf file containing every contact and shares it.
  Future<String> exportVCard() async {
    final contacts = await _contactRepo.getAll();
    final buffer = StringBuffer();

    for (final c in contacts) {
      buffer.writeln('BEGIN:VCARD');
      buffer.writeln('VERSION:3.0');
      buffer.writeln('N:${c.lastName};${c.firstName};;;');
      buffer.writeln('FN:${c.fullName}');
      for (final phone in c.phones) {
        buffer.writeln('TEL;TYPE=${phone.label.toUpperCase()}:${phone.number}');
      }
      for (final email in c.emails) {
        buffer.writeln('EMAIL;TYPE=${email.label.toUpperCase()}:${email.email}');
      }
      if (c.note != null && c.note!.isNotEmpty) {
        buffer.writeln('NOTE:${c.note!.replaceAll('\n', '\\n')}');
      }
      buffer.writeln('END:VCARD');
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'contacts_export_${DateTime.now().millisecondsSinceEpoch}.vcf'));
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Contacts export'));
    return file.path;
  }

  /// Parses a minimal vCard 3.0/4.0 subset (N/FN, TEL, EMAIL, NOTE)
  /// good enough for round-tripping contacts exported by this app or
  /// by the stock iOS/Android Contacts apps. Multi-line folded values
  /// are not handled — most mobile exports don't fold lines.
  Future<int> importVCardFromFile() async {
    // file_picker 12.x: pickFile() is the single-selection
    // convenience method, returning PlatformFile? directly
    // (no more FilePickerResult wrapper).
    final picked = await FilePicker.platform.pickFile(
      type: FileType.custom,
      allowedExtensions: ['vcf'],
    );
    if (picked == null || picked.path == null) return 0;

    final content = await File(picked.path!).readAsString();
    final cards = content.split('BEGIN:VCARD').where((c) => c.trim().isNotEmpty);

    int imported = 0;
    for (final rawCard in cards) {
      final lines = rawCard.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

      String firstName = '';
      String lastName = '';
      final phones = <PhoneEntry>[];
      final emails = <EmailEntry>[];
      String? note;

      for (final line in lines) {
        if (line.startsWith('N:')) {
          final parts = line.substring(2).split(';');
          lastName = parts.isNotEmpty ? parts[0] : '';
          firstName = parts.length > 1 ? parts[1] : '';
        } else if (line.startsWith('FN:') && firstName.isEmpty && lastName.isEmpty) {
          firstName = line.substring(3);
        } else if (line.startsWith('TEL')) {
          final value = line.substring(line.indexOf(':') + 1);
          final label = line.contains('TYPE=') ? line.split('TYPE=')[1].split(':')[0].split(';')[0] : 'mobile';
          phones.add(PhoneEntry(label: label.toLowerCase(), number: value));
        } else if (line.startsWith('EMAIL')) {
          final value = line.substring(line.indexOf(':') + 1);
          final label = line.contains('TYPE=') ? line.split('TYPE=')[1].split(':')[0].split(';')[0] : 'home';
          emails.add(EmailEntry(label: label.toLowerCase(), email: value));
        } else if (line.startsWith('NOTE:')) {
          note = line.substring(5).replaceAll('\\n', '\n');
        }
      }

      if (firstName.isEmpty && lastName.isEmpty) continue;

      await _contactRepo.create(
        firstName: firstName,
        lastName: lastName,
        phones: phones,
        emails: emails,
        note: note,
      );
      imported++;
    }

    return imported;
  }

  // ===================================================================
  // Full app Backup/Restore (SQLite DB + recordings folder -> .zip)
  // ===================================================================

  Future<String> createBackup() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(await getDatabasesPath(), 'phonebook.db');
    final recordingsDir = Directory(p.join(docsDir.path, 'call_recordings'));

    final archive = Archive();

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      archive.addFile(ArchiveFile('phonebook.db', await dbFile.length(), await dbFile.readAsBytes()));
    }

    if (await recordingsDir.exists()) {
      await for (final entity in recordingsDir.list()) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile('call_recordings/${p.basename(entity.path)}', bytes.length, bytes));
        }
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    final backupFile = File(
      p.join(docsDir.path, 'phonebook_backup_${DateTime.now().millisecondsSinceEpoch}.zip'),
    );
    await backupFile.writeAsBytes(zipBytes!);

    await _activityLog.log(
      type: ActivityType.backup,
      description: 'Created backup ${p.basename(backupFile.path)}',
    );

    await SharePlus.instance.share(ShareParams(files: [XFile(backupFile.path)], text: 'Phonebook backup'));
    return backupFile.path;
  }

  /// Restores from a previously created backup zip. This overwrites
  /// the current database and recordings folder — callers should
  /// confirm with the user before invoking this.
  Future<bool> restoreBackup() async {
    final picked = await FilePicker.platform.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.path == null) return false;

    final pickedPath = picked.path!;
    final bytes = await File(pickedPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Close the current DB connection before overwriting the file.
    await DbHelper.instance.closeDb();

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(await getDatabasesPath(), 'phonebook.db');
    final recordingsDir = Directory(p.join(docsDir.path, 'call_recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    for (final file in archive) {
      if (!file.isFile) continue;
      final data = file.content as List<int>;

      if (file.name == 'phonebook.db') {
        await File(dbPath).writeAsBytes(data, flush: true);
      } else if (file.name.startsWith('call_recordings/')) {
        final outPath = p.join(docsDir.path, file.name);
        await File(outPath).writeAsBytes(data, flush: true);
      }
    }

    // Reopen with the restored data.
    await DbHelper.instance.database;

    await _activityLog.log(
      type: ActivityType.restore,
      description: 'Restored backup ${p.basename(pickedPath)}',
    );

    return true;
  }
}

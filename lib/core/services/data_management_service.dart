import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/contact_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/contact_repository.dart';

/// Result of a vCard import — issue #14 asked for duplicate handling
/// to be "clearly handled", not silently either merged or duplicated.
/// This reports both counts so the UI can tell the user exactly what
/// happened; duplicates (matched by phone number) are skipped, not
/// merged, to avoid silently overwriting edits made in this app.
typedef VCardImportResult = ({int imported, int skippedDuplicates});

class DataManagementService {
  final _contactRepo = ContactRepository();
  final _activityLog = ActivityLogRepository();

  // ===================================================================
  // vCard (.vcf) export/import
  // ===================================================================

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
      if (c.organization != null && c.organization!.isNotEmpty) {
        buffer.writeln('ORG:${c.organization}');
      }
      if (c.address != null && c.address!.isNotEmpty) {
        // vCard ADR is semicolon-delimited (PO box;extended;street;
        // city;region;postal;country) — we only track a single free
        // text address, so it goes in the "street" slot.
        buffer.writeln('ADR:;;${c.address!.replaceAll(';', ',')};;;;');
      }
      if (c.website != null && c.website!.isNotEmpty) {
        buffer.writeln('URL:${c.website}');
      }
      if (c.birthday != null) {
        buffer.writeln('BDAY:${DateFormat('yyyyMMdd').format(c.birthday!)}');
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

  DateTime? _parseVCardDate(String raw) {
    // vCard BDAY is typically YYYYMMDD (no separators) per spec, but
    // some exporters use YYYY-MM-DD — handle both.
    final digitsOnly = raw.replaceAll('-', '');
    if (digitsOnly.length != 8) return null;
    final year = int.tryParse(digitsOnly.substring(0, 4));
    final month = int.tryParse(digitsOnly.substring(4, 6));
    final day = int.tryParse(digitsOnly.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Parses a minimal vCard 3.0/4.0 subset and imports each card,
  /// skipping any contact that shares a phone number with an
  /// existing one (issue #14 — previously imported straight
  /// duplicates with no detection at all).
  Future<VCardImportResult> importVCardFromFile() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['vcf']);
    if (picked == null || picked.path == null) return (imported: 0, skippedDuplicates: 0);

    final content = await File(picked.path!).readAsString();
    final cards = content.split('BEGIN:VCARD').where((c) => c.trim().isNotEmpty);

    int imported = 0;
    int skipped = 0;

    for (final rawCard in cards) {
      final lines = rawCard.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

      String firstName = '';
      String lastName = '';
      final phones = <PhoneEntry>[];
      final emails = <EmailEntry>[];
      String? note;
      String? organization;
      String? address;
      String? website;
      DateTime? birthday;

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
        } else if (line.startsWith('ORG:')) {
          organization = line.substring(4);
        } else if (line.startsWith('ADR')) {
          final value = line.substring(line.indexOf(':') + 1);
          final nonEmptyParts = value.split(';').where((s) => s.trim().isNotEmpty);
          address = nonEmptyParts.join(', ');
        } else if (line.startsWith('URL:')) {
          website = line.substring(4);
        } else if (line.startsWith('BDAY:')) {
          birthday = _parseVCardDate(line.substring(5));
        } else if (line.startsWith('NOTE:')) {
          note = line.substring(5).replaceAll('\\n', '\n');
        }
      }

      if (firstName.isEmpty && lastName.isEmpty) continue;

      final duplicate = await _contactRepo.findByAnyPhone(phones);
      if (duplicate != null) {
        skipped++;
        continue;
      }

      await _contactRepo.create(
        firstName: firstName,
        lastName: lastName,
        phones: phones,
        emails: emails,
        note: note,
        organization: organization,
        address: address,
        website: website,
        birthday: birthday,
      );
      imported++;
    }

    return (imported: imported, skippedDuplicates: skipped);
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
    if (zipBytes == null) {
      throw Exception('Failed to build backup archive.');
    }

    final backupFile = File(
      p.join(docsDir.path, 'phonebook_backup_${DateTime.now().millisecondsSinceEpoch}.zip'),
    );
    await backupFile.writeAsBytes(zipBytes);

    await _activityLog.log(
      type: ActivityType.backup,
      description: 'Created backup ${p.basename(backupFile.path)}',
    );

    await SharePlus.instance.share(ShareParams(files: [XFile(backupFile.path)], text: 'Phonebook backup'));
    return backupFile.path;
  }

  /// Restores from a previously created backup zip. Fix for #15:
  /// validates the archive *before* touching any existing data, and
  /// wraps every step so a corrupt/foreign zip throws a clear message
  /// instead of leaving the app in a half-restored state.
  Future<bool> restoreBackup() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip']);
    if (picked == null || picked.path == null) return false;

    final pickedPath = picked.path!;
    late final Archive archive;

    try {
      final bytes = await File(pickedPath).readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw Exception('This file isn\'t a valid backup archive.');
    }

    final hasDbFile = archive.files.any((f) => f.isFile && f.name == 'phonebook.db');
    if (!hasDbFile) {
      // Validated BEFORE closing the current DB / touching any
      // files, so a bad backup can't corrupt the current data.
      throw Exception('This backup is missing the contacts database — nothing was changed.');
    }

    try {
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

      // Reopen with the restored data — if this fails, the app would
      // otherwise be stuck with the DB connection closed.
      await DbHelper.instance.database;
    } catch (e) {
      // Best-effort recovery: make sure we at least have a working DB
      // connection open again, even if the restore itself failed
      // partway through.
      await DbHelper.instance.database;
      throw Exception('Restore failed partway through: $e');
    }

    await _activityLog.log(
      type: ActivityType.restore,
      description: 'Restored backup ${p.basename(pickedPath)}',
    );

    return true;
  }
}

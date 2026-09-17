import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/contact_model.dart';
import '../services/csv_sync_service.dart';
import '../services/public_mirror_service.dart';
import 'activity_log_repository.dart';

class ContactRepository {
  final _uuid = const Uuid();
  final _csvSync = CsvSyncService();
  final _publicMirror = PublicMirrorService();
  final _activityLog = ActivityLogRepository();

  Future<List<ContactModel>> getAll() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('contacts', orderBy: 'first_name COLLATE NOCASE ASC');
    return rows.map((r) => ContactModel.fromDbMap(r)).toList();
  }

  Future<ContactModel?> getById(String id) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('contacts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ContactModel.fromDbMap(rows.first);
  }

  static String normalizeDigits(String input) => input.replaceAll(RegExp(r'\D'), '');

  Future<List<ContactModel>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getAll();

    final db = await DbHelper.instance.database;
    final like = '%$trimmed%';
    final rows = await db.query(
      'contacts',
      where: 'first_name LIKE ? OR last_name LIKE ? OR phones LIKE ? OR emails LIKE ? OR note LIKE ?',
      whereArgs: [like, like, like, like, like],
    );
    final results = rows.map((r) => ContactModel.fromDbMap(r)).toList();
    final matchedIds = results.map((c) => c.id).toSet();

    final queryDigits = normalizeDigits(trimmed);
    if (queryDigits.isNotEmpty) {
      final all = await getAll();
      for (final c in all) {
        if (matchedIds.contains(c.id)) continue;
        final hasDigitMatch = c.phones.any((p) => normalizeDigits(p.number).contains(queryDigits));
        if (hasDigitMatch) {
          results.add(c);
          matchedIds.add(c.id);
        }
      }
    }

    results.sort((a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
    return results;
  }

  Future<List<ContactModel>> getFavorites() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('contacts', where: 'is_favorite = 1', orderBy: 'first_name COLLATE NOCASE ASC');
    return rows.map((r) => ContactModel.fromDbMap(r)).toList();
  }

  Future<ContactModel?> findByAnyPhone(List<PhoneEntry> phones) async {
    if (phones.isEmpty) return null;
    final targetDigits = phones.map((p) => normalizeDigits(p.number)).where((d) => d.isNotEmpty).toSet();
    if (targetDigits.isEmpty) return null;

    final all = await getAll();
    for (final c in all) {
      final hasOverlap = c.phones.any((p) => targetDigits.contains(normalizeDigits(p.number)));
      if (hasOverlap) return c;
    }
    return null;
  }

  Future<ContactModel> create({
    required String firstName,
    required String lastName,
    String? photoPath,
    List<PhoneEntry> phones = const [],
    List<EmailEntry> emails = const [],
    String? note,
    String? organization,
    String? address,
    DateTime? birthday,
    String? website,
  }) async {
    final db = await DbHelper.instance.database;
    final contact = ContactModel(
      id: _uuid.v4(),
      firstName: firstName,
      lastName: lastName,
      photoPath: photoPath,
      phones: phones,
      emails: emails,
      note: note,
      updatedAt: DateTime.now(),
      organization: organization,
      address: address,
      birthday: birthday,
      website: website,
    );
    await db.insert('contacts', contact.toDbMap());

    await _activityLog.log(
      type: ActivityType.contactAdded,
      contactId: contact.id,
      description: 'Added contact ${contact.fullName}',
    );
    await _syncMirrors();
    return contact;
  }

  Future<void> update(ContactModel contact) async {
    final db = await DbHelper.instance.database;
    final updated = contact.copyWith();
    await db.update('contacts', updated.toDbMap(), where: 'id = ?', whereArgs: [contact.id]);

    await _activityLog.log(
      type: ActivityType.contactEdited,
      contactId: contact.id,
      description: 'Edited contact ${contact.fullName}',
    );
    await _syncMirrors();
  }

  Future<void> toggleFavorite(String id) async {
    final contact = await getById(id);
    if (contact == null) return;
    await update(contact.copyWith(isFavorite: !contact.isFavorite));
  }

  Future<void> delete(String id) async {
    final contact = await getById(id);
    final db = await DbHelper.instance.database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);

    await _activityLog.log(
      type: ActivityType.contactDeleted,
      contactId: id,
      description: 'Deleted contact ${contact?.fullName ?? id}',
    );
    await _syncMirrors();
  }

  /// Refreshes both mirrors: the human-readable CSV (unchanged from
  /// before) and the new public JSON backup (contacts + activity
  /// log). Piggybacking the activity-log mirror here — rather than on
  /// every single ActivityLogRepository.log() call — avoids writing
  /// that file on every noisy [DEBUG] entry during an active call.
  Future<void> _syncMirrors() async {
    final all = await getAll();
    await _csvSync.syncContacts(all);
    await _publicMirror.mirrorContacts(all.map((c) => c.toDbMap()).toList());

    final logs = await _activityLog.getAll();
    await _publicMirror.mirrorActivityLogs(logs.map((l) => l.toDbMap()).toList());
  }

  Future<void> forceSyncCsv() => _syncMirrors();
}

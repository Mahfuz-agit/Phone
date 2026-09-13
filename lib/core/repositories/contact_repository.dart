import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/contact_model.dart';
import '../services/csv_sync_service.dart';
import 'activity_log_repository.dart';

class ContactRepository {
  final _uuid = const Uuid();
  final _csvSync = CsvSyncService();
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

  Future<List<ContactModel>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final db = await DbHelper.instance.database;
    final like = '%${query.trim()}%';
    final rows = await db.query(
      'contacts',
      where: 'first_name LIKE ? OR last_name LIKE ? OR phones LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'first_name COLLATE NOCASE ASC',
    );
    return rows.map((r) => ContactModel.fromDbMap(r)).toList();
  }

  Future<List<ContactModel>> getFavorites() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'contacts',
      where: 'is_favorite = 1',
      orderBy: 'first_name COLLATE NOCASE ASC',
    );
    return rows.map((r) => ContactModel.fromDbMap(r)).toList();
  }

  Future<ContactModel> create({
    required String firstName,
    required String lastName,
    String? photoPath,
    List<PhoneEntry> phones = const [],
    List<EmailEntry> emails = const [],
    String? note,
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
    );
    await db.insert('contacts', contact.toDbMap());

    await _activityLog.log(
      type: ActivityType.contactAdded,
      contactId: contact.id,
      description: 'Added contact ${contact.fullName}',
    );
    await _syncCsv();
    return contact;
  }

  Future<void> update(ContactModel contact) async {
    final db = await DbHelper.instance.database;
    final updated = contact.copyWith(); // refreshes updatedAt
    await db.update('contacts', updated.toDbMap(), where: 'id = ?', whereArgs: [contact.id]);

    await _activityLog.log(
      type: ActivityType.contactEdited,
      contactId: contact.id,
      description: 'Edited contact ${contact.fullName}',
    );
    await _syncCsv();
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
    await _syncCsv();
  }

  Future<void> _syncCsv() async {
    final all = await getAll();
    await _csvSync.syncContacts(all);
  }

  /// Exposed so a manual "Sync now" button or Backup flow can force
  /// a rewrite without going through a contact mutation.
  Future<void> forceSyncCsv() => _syncCsv();
}

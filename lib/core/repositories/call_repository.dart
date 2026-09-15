import 'package:call_log/call_log.dart' as syslog;
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/call_record_model.dart';
import 'activity_log_repository.dart';
import 'contact_repository.dart';

class CallRepository {
  final _uuid = const Uuid();
  final _activityLog = ActivityLogRepository();

  Future<List<CallRecordModel>> getAll() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('call_records', orderBy: 'timestamp DESC');
    return rows.map((r) => CallRecordModel.fromDbMap(r)).toList();
  }

  Future<List<CallRecordModel>> getByContact(String contactId) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'call_records',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => CallRecordModel.fromDbMap(r)).toList();
  }

  Future<List<CallRecordModel>> searchRecordings(String query) async {
    final db = await DbHelper.instance.database;
    final like = '%${query.trim()}%';
    final rows = await db.query(
      'call_records',
      where: 'recording_path IS NOT NULL AND (display_name LIKE ? OR phone_number LIKE ? OR timestamp LIKE ?)',
      whereArgs: [like, like, like],
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => CallRecordModel.fromDbMap(r)).toList();
  }

  Future<List<CallRecordModel>> filter({
    String? contactId,
    CallType? type,
    DateTime? from,
    DateTime? to,
    bool onlyWithRecording = false,
  }) async {
    final db = await DbHelper.instance.database;
    final where = <String>[];
    final args = <dynamic>[];

    if (contactId != null) {
      where.add('contact_id = ?');
      args.add(contactId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    if (from != null) {
      where.add('timestamp >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('timestamp <= ?');
      args.add(to.toIso8601String());
    }
    if (onlyWithRecording) {
      where.add('recording_path IS NOT NULL');
    }

    final rows = await db.query(
      'call_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => CallRecordModel.fromDbMap(r)).toList();
  }

  Future<CallRecordModel> logCall({
    String? contactId,
    required String phoneNumber,
    required String displayName,
    required CallType type,
    required int durationSeconds,
    String? recordingPath,
  }) async {
    final db = await DbHelper.instance.database;
    final call = CallRecordModel(
      id: _uuid.v4(),
      contactId: contactId,
      phoneNumber: phoneNumber,
      displayName: displayName,
      type: type,
      timestamp: DateTime.now(),
      durationSeconds: durationSeconds,
      recordingPath: recordingPath,
    );
    await db.insert('call_records', call.toDbMap());

    await _activityLog.log(
      type: ActivityType.call,
      contactId: contactId,
      description: '${type.name[0].toUpperCase()}${type.name.substring(1)} call '
          'with $displayName (${durationSeconds}s)',
    );
    return call;
  }

  Future<void> attachRecording(String callId, String recordingPath) async {
    final db = await DbHelper.instance.database;
    await db.update('call_records', {'recording_path': recordingPath}, where: 'id = ?', whereArgs: [callId]);
  }

  Future<void> renameRecording(String callId, String newPath) async {
    final db = await DbHelper.instance.database;
    await db.update('call_records', {'recording_path': newPath}, where: 'id = ?', whereArgs: [callId]);
    await _activityLog.log(
      type: ActivityType.recordingRenamed,
      contactId: null,
      description: 'Renamed recording for call $callId',
    );
  }

  Future<void> markTrimmed(String callId, int newDurationSeconds) async {
    final db = await DbHelper.instance.database;
    await db.update('call_records', {'duration_seconds': newDurationSeconds}, where: 'id = ?', whereArgs: [callId]);
    await _activityLog.log(
      type: ActivityType.recordingTrimmed,
      contactId: null,
      description: 'Trimmed recording for call $callId',
    );
  }

  Future<void> delete(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('call_records', where: 'id = ?', whereArgs: [id]);
  }

  CallType _mapSystemType(syslog.CallType? type) {
    switch (type) {
      case syslog.CallType.incoming:
        return CallType.incoming;
      case syslog.CallType.outgoing:
        return CallType.outgoing;
      case syslog.CallType.missed:
      case syslog.CallType.rejected:
      case syslog.CallType.blocked:
        return CallType.missed;
      default:
        // voiceMail, answeredExternally, unknown, etc. — no exact
        // match in our 3-value model, default to incoming rather
        // than losing the entry entirely.
        return CallType.incoming;
    }
  }

  /// Imports the phone's existing system call history (issue raised
  /// by the user: "Calls tab is empty, I want all my call history").
  ///
  /// Important limitation, stated plainly: this can only import
  /// metadata — number, name, timestamp, duration, direction. It
  /// CANNOT import audio recordings of past calls, because no Android
  /// API grants any app access to another app's (or the system
  /// dialer's) recorded call audio, and a finished call cannot be
  /// recorded retroactively. Only calls made *after* this app's
  /// recording fix is installed and running will have audio.
  ///
  /// Safe to call repeatedly — every entry is deduplicated against
  /// what's already stored (same normalized phone number within the
  /// same minute), so re-running it just catches up on new calls.
  Future<int> importSystemCallLog() async {
    final systemEntries = await syslog.CallLog.get();
    final existing = await getAll();
    final contactRepo = ContactRepository();
    final allContacts = await contactRepo.getAll();

    // Dedup key: normalized phone digits + timestamp rounded to the
    // minute. Call duration can differ by a second or two between
    // sources, so we don't include it in the key.
    final existingKeys = existing.map((c) {
      final digits = ContactRepository.normalizeDigits(c.phoneNumber);
      final minuteBucket = (c.timestamp.millisecondsSinceEpoch / 60000).round();
      return '${digits}_$minuteBucket';
    }).toSet();

    final db = await DbHelper.instance.database;
    int imported = 0;

    for (final entry in systemEntries) {
      final number = entry.number;
      final tsMillis = entry.timestamp;
      if (number == null || number.isEmpty || tsMillis == null) continue;

      final digits = ContactRepository.normalizeDigits(number);
      final minuteBucket = (tsMillis / 60000).round();
      final key = '${digits}_$minuteBucket';
      if (existingKeys.contains(key)) continue;

      // Try to match against a saved contact for a friendlier name.
      String displayName = (entry.name != null && entry.name!.isNotEmpty) ? entry.name! : number;
      String? contactId;
      for (final c in allContacts) {
        final matches = c.phones.any((p) => ContactRepository.normalizeDigits(p.number) == digits);
        if (matches) {
          contactId = c.id;
          displayName = c.fullName;
          break;
        }
      }

      final call = CallRecordModel(
        id: _uuid.v4(),
        contactId: contactId,
        phoneNumber: number,
        displayName: displayName,
        type: _mapSystemType(entry.callType),
        timestamp: DateTime.fromMillisecondsSinceEpoch(tsMillis),
        durationSeconds: entry.duration ?? 0,
        recordingPath: null, // see method doc — never available for historical calls
      );

      await db.insert('call_records', call.toDbMap());
      existingKeys.add(key);
      imported++;
    }

    if (imported > 0) {
      await _activityLog.log(
        type: ActivityType.callLogImported,
        description: 'Imported $imported call(s) from system call history',
      );
    }

    return imported;
  }
}

import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/activity_log_model.dart';
import '../models/call_record_model.dart';
import 'activity_log_repository.dart';

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

  /// Search recordings by contact/display name or date (yyyy-MM-dd
  /// substring match against the ISO timestamp).
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
    await db.update(
      'call_records',
      {'recording_path': recordingPath},
      where: 'id = ?',
      whereArgs: [callId],
    );
  }

  Future<void> renameRecording(String callId, String newPath) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'call_records',
      {'recording_path': newPath},
      where: 'id = ?',
      whereArgs: [callId],
    );
    await _activityLog.log(
      type: ActivityType.recordingRenamed,
      contactId: null,
      description: 'Renamed recording for call $callId',
    );
  }

  Future<void> markTrimmed(String callId, int newDurationSeconds) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'call_records',
      {'duration_seconds': newDurationSeconds},
      where: 'id = ?',
      whereArgs: [callId],
    );
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
}

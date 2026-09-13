import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/activity_log_model.dart';

class ActivityLogRepository {
  final _uuid = const Uuid();

  Future<void> log({
    required ActivityType type,
    String? contactId,
    required String description,
  }) async {
    final db = await DbHelper.instance.database;
    final entry = ActivityLogModel(
      id: _uuid.v4(),
      type: type,
      contactId: contactId,
      description: description,
      timestamp: DateTime.now(),
    );
    await db.insert('activity_logs', entry.toDbMap());
  }

  Future<List<ActivityLogModel>> getAll() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('activity_logs', orderBy: 'timestamp DESC');
    return rows.map((r) => ActivityLogModel.fromDbMap(r)).toList();
  }

  /// Filters by any combination of contact id, type, and an inclusive
  /// date range. Pass null to skip a given filter.
  Future<List<ActivityLogModel>> filter({
    String? contactId,
    ActivityType? type,
    DateTime? from,
    DateTime? to,
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

    final rows = await db.query(
      'activity_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
    );
    return rows.map((r) => ActivityLogModel.fromDbMap(r)).toList();
  }

  Future<void> deleteAll() async {
    final db = await DbHelper.instance.database;
    await db.delete('activity_logs');
  }
}

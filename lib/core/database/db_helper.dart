import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._internal();
  DbHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'phonebook.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contacts (
            id TEXT PRIMARY KEY,
            first_name TEXT NOT NULL,
            last_name TEXT,
            photo_path TEXT,
            phones TEXT,
            emails TEXT,
            note TEXT,
            is_favorite INTEGER DEFAULT 0,
            updated_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE call_records (
            id TEXT PRIMARY KEY,
            contact_id TEXT,
            phone_number TEXT,
            display_name TEXT,
            type TEXT,
            timestamp TEXT,
            duration_seconds INTEGER,
            recording_path TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE activity_logs (
            id TEXT PRIMARY KEY,
            type TEXT,
            contact_id TEXT,
            description TEXT,
            timestamp TEXT
          )
        ''');

        await db.execute('CREATE INDEX idx_contacts_name ON contacts(first_name, last_name)');
        await db.execute('CREATE INDEX idx_calls_timestamp ON call_records(timestamp)');
        await db.execute('CREATE INDEX idx_logs_timestamp ON activity_logs(timestamp)');
      },
    );
  }

  Future<void> closeDb() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}

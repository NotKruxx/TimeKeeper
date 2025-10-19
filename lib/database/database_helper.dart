import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'app_database.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE azienda(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE hours_worked(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        azienda_id INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        lunch_break INTEGER NOT NULL,
        notes TEXT,
        FOREIGN KEY (azienda_id) REFERENCES azienda(id) ON DELETE CASCADE,
        CONSTRAINT unique_shift UNIQUE (azienda_id, start_time, end_time)
      )
    ''');

    await db.execute('''
      CREATE TABLE salaries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        azienda_id INTEGER NOT NULL,
        month TEXT NOT NULL,
        amount REAL NOT NULL,
        FOREIGN KEY (azienda_id) REFERENCES azienda(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE overtime_rates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        azienda_id INTEGER NOT NULL,
        rate REAL NOT NULL,
        description TEXT,
        FOREIGN KEY (azienda_id) REFERENCES azienda(id) ON DELETE CASCADE
      )
    ''');
  }
}

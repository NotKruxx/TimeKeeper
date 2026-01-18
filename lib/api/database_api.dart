// lib/api/database_api.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/azienda.dart';
import '../models/hours_worked.dart';

class DatabaseApi {
  static final DatabaseApi _instance = DatabaseApi._internal();
  factory DatabaseApi() => _instance;
  DatabaseApi._internal();

  static Database? _database;
  static bool isForTesting = false;

  static Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = isForTesting ? inMemoryDatabasePath : join(await getDatabasesPath(), 'work_hours_app.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE azienda ADD COLUMN hourly_rate REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE azienda ADD COLUMN overtime_rate REAL NOT NULL DEFAULT 0.0');
    }
    if (oldVersion < 3) {
      await db.execute('UPDATE hours_worked SET lunch_break = 60 WHERE lunch_break = 1');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE azienda ADD COLUMN schedule_config TEXT');
      await db.execute('''
        CREATE TABLE auto_gen_log(
          azienda_id INTEGER,
          date_processed TEXT,
          PRIMARY KEY (azienda_id, date_processed)
        )
      ''');
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE azienda(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        hourly_rate REAL NOT NULL DEFAULT 0.0,
        overtime_rate REAL NOT NULL DEFAULT 0.0,
        schedule_config TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE hours_worked(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        azienda_id INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        lunch_break INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        FOREIGN KEY (azienda_id) REFERENCES azienda(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE auto_gen_log(
        azienda_id INTEGER,
        date_processed TEXT,
        PRIMARY KEY (azienda_id, date_processed)
      )
    ''');
  }

  Future<void> addAzienda(Azienda azienda) async {
    final db = await database;
    await db.insert('azienda', azienda.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Azienda>> getAziende() async {
    final db = await database;
    final maps = await db.query('azienda', orderBy: 'name ASC');
    return List.generate(maps.length, (i) => Azienda.fromMap(maps[i]));
  }

  Future<void> updateAzienda(Azienda azienda) async {
    final db = await database;
    await db.update('azienda', azienda.toMap(), where: 'id = ?', whereArgs: [azienda.id]);
  }

  Future<void> deleteAzienda(int id) async {
    final db = await database;
    await db.delete('azienda', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addHoursWorked(HoursWorked hours) async {
    final db = await database;
    await db.insert('hours_worked', hours.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateHoursWorked(HoursWorked hours) async {
    final db = await database;
    await db.update('hours_worked', hours.toMap(), where: 'id = ?', whereArgs: [hours.id]);
  }

  Future<void> deleteHour(int id) async {
    final db = await database;
    await db.delete('hours_worked', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HoursWorked>> getHoursWorked() async {
    final db = await database;
    final maps = await db.query('hours_worked', orderBy: 'start_time DESC');
    return List.generate(maps.length, (i) => HoursWorked.fromMap(maps[i]));
  }

  Future<bool> checkOverlap(HoursWorked hours) async {
    final db = await database;
    var whereString = 'azienda_id = ? AND start_time < ? AND end_time > ?';
    var whereArgs = [hours.aziendaId, hours.endTime.toIso8601String(), hours.startTime.toIso8601String()];
    if (hours.id != null) {
      whereString += ' AND id != ?';
      whereArgs.add(hours.id!);
    }
    final result = await db.query('hours_worked', where: whereString, whereArgs: whereArgs, limit: 1);
    return result.isNotEmpty;
  }

  Future<void> runAutoShiftGeneration() async {
    final db = await database;
    final aziendeList = await getAziende();
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    for (var azienda in aziendeList) {
      final config = azienda.scheduleConfig;
      if (!config.enabled || config.automationStartDate == null || azienda.id == null) {
        continue;
      }

      final startDateParts = config.automationStartDate!.split('-');
      final startConfigDate = DateTime(int.parse(startDateParts[0]), int.parse(startDateParts[1]), int.parse(startDateParts[2]));

      int daysDiff = today.difference(startConfigDate).inDays;
      if (daysDiff < 0) continue;

      final daysToProcess = daysDiff > 365 ? 365 : daysDiff;

      for (int i = 0; i <= daysToProcess; i++) {
        final dateToCheck = startConfigDate.add(Duration(days: i));
        final dateKey = "${dateToCheck.year}-${dateToCheck.month.toString().padLeft(2, '0')}-${dateToCheck.day.toString().padLeft(2, '0')}";

        final logCheck = await db.query('auto_gen_log', where: 'azienda_id = ? AND date_processed = ?', whereArgs: [azienda.id, dateKey]);
        if (logCheck.isNotEmpty) continue;

        if (config.activeDays.contains(dateToCheck.weekday)) {
          final startDateTime = DateTime(dateToCheck.year, dateToCheck.month, dateToCheck.day, config.start.hour, config.start.minute);
          final endDateTime = DateTime(dateToCheck.year, dateToCheck.month, dateToCheck.day, config.end.hour, config.end.minute);
          final shift = HoursWorked(aziendaId: azienda.id!, startTime: startDateTime, endTime: endDateTime, lunchBreak: config.lunchBreakMinutes);
          
          if (!await checkOverlap(shift)) {
            await addHoursWorked(HoursWorked(
              aziendaId: azienda.id!,
              startTime: startDateTime,
              endTime: endDateTime,
              lunchBreak: config.lunchBreakMinutes,
              notes: 'Generato Automaticamente',
            ));
          }
        }
        await db.insert('auto_gen_log', {'azienda_id': azienda.id, 'date_processed': dateKey});
      }
    }
  }
}
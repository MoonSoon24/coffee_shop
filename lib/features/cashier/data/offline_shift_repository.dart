import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OfflineShiftRepository {
  static const String _dbName = 'offline_shifts.db';
  static const int _dbVersion = 1;
  static const String _cashierTable = 'cached_cashiers';
  static const String _pendingShiftTable = 'offline_pending_shifts';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_cashierTable (
            cashier_id INTEGER PRIMARY KEY,
            name TEXT,
            pin_code TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            synced_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_pendingShiftTable (
            local_shift_id TEXT PRIMARY KEY,
            cashier_id INTEGER NOT NULL,
            branch_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('OfflineShiftRepository not initialized');
    return db;
  }

  Future<void> cacheCashiers(List<Map<String, dynamic>> cashiers) async {
    await init();
    await _database.transaction((txn) async {
      for (final row in cashiers) {
        final cashierId = (row['id'] as num?)?.toInt();
        if (cashierId == null) continue;
        await txn.insert(_cashierTable, {
          'cashier_id': cashierId,
          'name': row['name']?.toString(),
          'pin_code': row['code']?.toString() ?? '',
          'payload_json': jsonEncode(row),
          'synced_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedCashiers() async {
    await init();
    final rows = await _database.query(_cashierTable, orderBy: 'name ASC');
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> validateCashierPin({
    required int cashierId,
    required String pin,
  }) async {
    await init();
    final rows = await _database.query(
      _cashierTable,
      columns: ['pin_code'],
      where: 'cashier_id = ?',
      whereArgs: [cashierId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final expected = (rows.first['pin_code'] ?? '').toString();
    return expected == pin;
  }

  Future<String> enqueueOfflineShift({
    required int cashierId,
    required String branchId,
  }) async {
    await init();
    final localShiftId = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = {
      'local_shift_id': localShiftId,
      'cashier_id': cashierId,
      'branch_id': branchId,
      'started_at': DateTime.now().toIso8601String(),
      'status': 'open',
    };

    await _database.insert(_pendingShiftTable, {
      'local_shift_id': localShiftId,
      'cashier_id': cashierId,
      'branch_id': branchId,
      'started_at': payload['started_at'],
      'payload_json': jsonEncode(payload),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return localShiftId;
  }

  Future<List<Map<String, dynamic>>> getPendingShifts() async {
    await init();
    final rows = await _database.query(
      _pendingShiftTable,
      orderBy: 'started_at ASC',
    );
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Future<void> removePendingShift(String localShiftId) async {
    await init();
    await _database.delete(
      _pendingShiftTable,
      where: 'local_shift_id = ?',
      whereArgs: [localShiftId],
    );
  }

  Future<int> syncPendingShifts(SupabaseClient supabase) async {
    final pending = await getPendingShifts();
    var synced = 0;
    for (final shift in pending) {
      final localShiftId = shift['local_shift_id']?.toString() ?? '';
      if (localShiftId.isEmpty) continue;
      await supabase.from('shifts').insert({
        'branch_id': shift['branch_id'],
        'started_at': shift['started_at'],
        'current_cashier_id': shift['cashier_id'],
        'status': 'open',
      });
      await removePendingShift(localShiftId);
      synced++;
    }
    return synced;
  }
}

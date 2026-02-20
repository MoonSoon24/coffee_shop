import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class OfflineOrderQueueRepository {
  static const String _dbName = 'offline_orders.db';
  static const int _dbVersion = 1;

  static const String pendingTable = 'offline_pending_orders';
  static const String failedTable = 'offline_failed_orders';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $pendingTable (
            local_txn_id TEXT PRIMARY KEY,
            queued_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE $failedTable (
            local_txn_id TEXT PRIMARY KEY,
            failed_at TEXT NOT NULL,
            failure_reason TEXT,
            payload_json TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('OfflineOrderQueueRepository not initialized');
    }
    return db;
  }

  Future<int> getPendingCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS c FROM $pendingTable',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> getFailedCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS c FROM $failedTable',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final rows = await _database.query(pendingTable, orderBy: 'queued_at ASC');

    return rows
        .map((row) {
          final payload = jsonDecode(row['payload_json'] as String);
          return Map<String, dynamic>.from(payload as Map);
        })
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getFailedOrders() async {
    final rows = await _database.query(failedTable, orderBy: 'failed_at DESC');

    return rows
        .map((row) {
          final payload = jsonDecode(row['payload_json'] as String);
          return Map<String, dynamic>.from(payload as Map);
        })
        .toList(growable: false);
  }

  Future<void> retryFailed(String localTxnId) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        failedTable,
        where: 'local_txn_id = ?',
        whereArgs: [localTxnId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final payloadJson = rows.first['payload_json'] as String;
      final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map)
        ..remove('failed_at')
        ..remove('failure_reason')
        ..['queued_at'] = DateTime.now().toIso8601String();

      await txn.insert(pendingTable, {
        'local_txn_id': localTxnId,
        'queued_at': payload['queued_at'],
        'payload_json': jsonEncode(payload),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        failedTable,
        where: 'local_txn_id = ?',
        whereArgs: [localTxnId],
      );
    });
  }

  Future<void> deleteFailed(String localTxnId) async {
    await _database.delete(
      failedTable,
      where: 'local_txn_id = ?',
      whereArgs: [localTxnId],
    );
  }

  Future<void> enqueue(Map<String, dynamic> payload) async {
    final key = payload['local_txn_id']?.toString();
    if (key == null || key.isEmpty) {
      throw ArgumentError('local_txn_id is required');
    }

    await _database.insert(pendingTable, {
      'local_txn_id': key,
      'queued_at':
          payload['queued_at']?.toString() ?? DateTime.now().toIso8601String(),
      'payload_json': jsonEncode(payload),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removePending(String localTxnId) async {
    await _database.delete(
      pendingTable,
      where: 'local_txn_id = ?',
      whereArgs: [localTxnId],
    );
  }

  Future<void> moveToFailed({
    required String localTxnId,
    required Map<String, dynamic> payload,
    required String reason,
  }) async {
    await _database.transaction((txn) async {
      final failedPayload = Map<String, dynamic>.from(payload)
        ..['failed_at'] = DateTime.now().toIso8601String()
        ..['failure_reason'] = reason;

      await txn.insert(failedTable, {
        'local_txn_id': localTxnId,
        'failed_at': failedPayload['failed_at'],
        'failure_reason': reason,
        'payload_json': jsonEncode(failedPayload),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        pendingTable,
        where: 'local_txn_id = ?',
        whereArgs: [localTxnId],
      );
    });
  }
}

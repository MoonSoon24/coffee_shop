import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalOrderItemStoreRepository {
  LocalOrderItemStoreRepository._();

  static final LocalOrderItemStoreRepository instance =
      LocalOrderItemStoreRepository._();

  static const String _dbName = 'local_order_items.db';
  static const int _dbVersion = 1;
  static const String _table = 'local_order_items';

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
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalOrderItemStoreRepository not initialized');
    }
    return db;
  }

  Future<void> replaceAll(List<Map<String, dynamic>> rows) async {
    await init();
    await _database.transaction((txn) async {
      await txn.delete(_table);
      final now = DateTime.now().toIso8601String();
      for (final row in rows) {
        final orderId = (row['order_id'] as num?)?.toInt();
        if (orderId == null) continue;
        await txn.insert(_table, {
          'order_id': orderId,
          'payload_json': jsonEncode(row),
          'updated_at': now,
        });
      }
    });
  }

  Future<void> replaceForOrder({
    required int orderId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await init();
    await _database.transaction((txn) async {
      await txn.delete(_table, where: 'order_id = ?', whereArgs: [orderId]);
      final now = DateTime.now().toIso8601String();
      for (final row in rows) {
        await txn.insert(_table, {
          'order_id': orderId,
          'payload_json': jsonEncode(row),
          'updated_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> fetchByOrderId(int orderId) async {
    await init();
    final rows = await _database.query(
      _table,
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }
}

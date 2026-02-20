import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalOrderStoreRepository {
  LocalOrderStoreRepository._();
  static final LocalOrderStoreRepository instance = LocalOrderStoreRepository._();

  static const String _dbName = 'local_orders.db';
  static const int _dbVersion = 1;
  static const String _table = 'local_orders';

  Database? _db;
  final StreamController<List<Map<String, dynamic>>> _allController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

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
            id INTEGER PRIMARY KEY,
            status TEXT,
            order_source TEXT,
            created_at TEXT,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id INTEGER PRIMARY KEY,
            status TEXT,
            order_source TEXT,
            created_at TEXT,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );

    await _emitAll();
  }

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('LocalOrderStoreRepository not initialized');
    return db;
  }

  Future<void> upsertOrder(Map<String, dynamic> order) async {
    await init();
    final id = (order['id'] as num?)?.toInt();
    if (id == null) return;

    await _database.insert(_table, {
      'id': id,
      'status': order['status']?.toString(),
      'order_source': order['order_source']?.toString(),
      'created_at': order['created_at']?.toString(),
      'payload_json': jsonEncode(order),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _emitAll();
  }

  Future<void> upsertOrders(List<Map<String, dynamic>> orders) async {
    await init();
    await _database.transaction((txn) async {
      for (final order in orders) {
        final id = (order['id'] as num?)?.toInt();
        if (id == null) continue;
        await txn.insert(_table, {
          'id': id,
          'status': order['status']?.toString(),
          'order_source': order['order_source']?.toString(),
          'created_at': order['created_at']?.toString(),
          'payload_json': jsonEncode(order),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await _emitAll();
  }

  Future<List<Map<String, dynamic>>> fetchAllOrders() async {
    await init();
    final rows = await _database.query(_table, orderBy: 'id DESC');
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Stream<List<Map<String, dynamic>>> watchAllOrders() async* {
    await init();
    yield await fetchAllOrders();
    yield* _allController.stream;
  }

  Stream<List<Map<String, dynamic>>> watchActiveOrders() {
    return watchAllOrders().map(
      (rows) => rows
          .where((row) => row['status']?.toString() == 'active')
          .toList(growable: false),
    );
  }

  Future<void> _emitAll() async {
    if (_allController.isClosed) return;
    _allController.add(await fetchAllOrders());
  }
}
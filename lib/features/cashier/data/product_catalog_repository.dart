part of '../presentation/screens/cashier_screen.dart';

class ProductCatalogRepository {
  static const String _dbName = 'product_catalog.db';
  static const String _table = 'cached_products';

  Future<Database> _openDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id INTEGER PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id INTEGER PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveProducts(List<Product> products) async {
    final db = await _openDb();
    await _ensureTable(db);
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final product in products) {
        await txn.insert(_table, {
          'id': product.id,
          'payload_json': jsonEncode(product.toJson()),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Product>> loadCachedProducts() async {
    final db = await _openDb();
    await _ensureTable(db);
    final rows = await db.query(_table, orderBy: 'id ASC');
    return rows
        .map(
          (row) => Product.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(row['payload_json'] as String) as Map,
            ),
          ),
        )
        .toList(growable: false);
  }
}

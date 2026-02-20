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

  Future<String?> _cacheProductImage(Product product) async {
    final imageUrl = product.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme) return imageUrl;

      final basePath = await getDatabasesPath();
      final imageDir = Directory(p.join(basePath, 'product_images'));
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      final extension = p.extension(uri.path).isEmpty
          ? '.img'
          : p.extension(uri.path);
      final targetPath = p.join(imageDir.path, '${product.id}$extension');
      final file = File(targetPath);
      if (await file.exists()) {
        return targetPath;
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        await file.writeAsBytes(bytes, flush: true);
        return targetPath;
      }
    } catch (_) {
      // Keep catalog caching even if image download fails.
    }

    return imageUrl;
  }

  Future<void> saveProducts(List<Product> products) async {
    final db = await _openDb();
    await _ensureTable(db);
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final product in products) {
        final localImage = await _cacheProductImage(product);
        final payload = product.toJson();
        if (localImage != null) {
          payload['image_url'] = localImage;
        }

        await txn.insert(_table, {
          'id': product.id,
          'payload_json': jsonEncode(payload),
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

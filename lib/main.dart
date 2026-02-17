import 'dart:convert';
import 'package:coffee_shop/providers/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://iasodtouoikaeuxkuecy.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlhc29kdG91b2lrYWV1eGt1ZWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0ODYxMzIsImV4cCI6MjA4NjA2MjEzMn0.iqm3zxfy-Xl2a_6GDmTj6io8vJW2B3Sr5SHq_4vjJW4',
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => CartProvider(),
      child: const MyApp(),
    ),
  );
}

final supabase = Supabase.instance.client;

class OrderStatus {
  static const pending = 'pending';
  static const processing = 'processing';
  static const assigned = 'assigned';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coffee Shop Cashier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const ProductListScreen(),
    );
  }
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final Future<List<Product>> _future = supabase.from('products').select().then(
    (data) {
      return data.map((item) => Product.fromJson(item)).toList();
    },
  );

  String? _selectedCategory;
  String _orderType = 'dine_in';
  String? _customerName;
  String? _tableName;
  int? _currentActiveOrderId;
  final Set<String> _selectedCartItems = <String>{};
  bool _isCartSelectionMode = false;
  int? _pendingParentOrderIdForNextSubmit;

  Stream<List<Map<String, dynamic>>> get _onlinePendingOrdersStream => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map(
        (rows) => rows
            .where(
              (row) =>
                  row['status'] == OrderStatus.pending &&
                  row['order_source'] == 'online',
            )
            .toList(),
      );

  Stream<List<Map<String, dynamic>>> get _activeOrdersStream => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.where((row) => row['status'] == 'active').toList());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'App menu',
            icon: const Icon(Icons.apps),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'cashier', child: Text('Cashier Page')),
              PopupMenuItem(value: 'pesanan', child: Text('Pesanan')),
            ],
            onSelected: (value) {
              if (value == 'cashier') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cashier Page aktif')),
                );
              } else if (value == 'pesanan') {
                _showOnlineOrdersDialog();
              }
            },
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildColumnHeader(
                  title: 'Menu List',
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Menu settings',
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'refresh',
                        child: Text('Refresh menu'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.grey[100],
                    child: FutureBuilder<List<Product>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text('No products found!'),
                          );
                        }

                        final products = snapshot.data!;
                        final categories =
                            products
                                .map((product) => product.category)
                                .toSet()
                                .toList()
                              ..sort();
                        final filteredProducts = _selectedCategory == null
                            ? products
                            : products
                                  .where(
                                    (product) =>
                                        product.category == _selectedCategory,
                                  )
                                  .toList();

                        return Column(
                          children: [
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(16.0),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      childAspectRatio: 4 / 3,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = filteredProducts[index];
                                  return _buildProductCard(product);
                                },
                              ),
                            ),
                            SizedBox(
                              height: 56,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: ChoiceChip(
                                      label: const Text('All'),
                                      selected: _selectedCategory == null,
                                      onSelected: (_) => setState(
                                        () => _selectedCategory = null,
                                      ),
                                    ),
                                  ),
                                  ...categories.map(
                                    (category) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      child: ChoiceChip(
                                        label: Text(category),
                                        selected: _selectedCategory == category,
                                        onSelected: (_) => setState(
                                          () => _selectedCategory = category,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Consumer<CartProvider>(
              builder: (context, cart, child) {
                final hasCurrentOrderDraft =
                    cart.items.isNotEmpty ||
                    _customerName != null ||
                    _tableName != null;
                return Column(
                  children: [
                    _buildColumnHeader(
                      title: 'Cart',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isCartSelectionMode)
                            TextButton(
                              onPressed: cart.items.isEmpty
                                  ? null
                                  : _selectAllCartItems,
                              child: const Text('Select all'),
                            )
                          else ...[
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _onlinePendingOrdersStream,
                              builder: (context, snapshot) {
                                final pendingOrders =
                                    snapshot.data ?? <Map<String, dynamic>>[];
                                return IconButton(
                                  tooltip: 'Notification (online order)',
                                  onPressed: _showOnlineOrdersDialog,
                                  icon: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.notifications_active),
                                      if (pendingOrders.isNotEmpty)
                                        Positioned(
                                          right: -8,
                                          top: -8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              pendingOrders.length.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _activeOrdersStream,
                              builder: (context, snapshot) {
                                final activeOrders =
                                    snapshot.data ?? <Map<String, dynamic>>[];
                                return IconButton(
                                  tooltip: 'List (active order list)',
                                  onPressed: _showActiveCashierOrdersDialog,
                                  icon: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.list_alt),
                                      if (activeOrders.isNotEmpty)
                                        Positioned(
                                          right: -8,
                                          top: -8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              activeOrders.length.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Clear cart',
                              onPressed: hasCurrentOrderDraft
                                  ? _resetCurrentOrderDraft
                                  : null,
                              icon: const Icon(Icons.delete_sweep),
                            ),
                          ],
                          PopupMenuButton<String>(
                            tooltip: 'Cart settings',
                            icon: const Icon(Icons.more_vert),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'gabung_nota',
                                child: Text('Gabung nota'),
                              ),
                              PopupMenuItem(
                                value: 'pisah_nota',
                                child: Text('Pisah nota'),
                              ),
                              PopupMenuItem(
                                value: 'batal_pesanan',
                                child: Text('Batal pesanan'),
                              ),
                            ],
                            onSelected: _onCartSettingSelected,
                          ),
                        ],
                      ),
                    ),
                    _buildCartOrderDetailsTab(),
                    Expanded(
                      child: ClipRect(
                        child: ListView.builder(
                          itemCount: cart.items.length,
                          itemBuilder: (context, index) {
                            final entry = cart.items.entries.elementAt(index);
                            final key = entry.key;
                            final item = entry.value;

                            final isSelected = _selectedCartItems.contains(key);

                            final tile = ListTile(
                              onLongPress: () =>
                                  _enterSelectionModeWithItem(key),
                              onTap: () {
                                if (_isCartSelectionMode) {
                                  _toggleSelectedCartItem(key);
                                  return;
                                }
                                _openCartItemEditor(key, item);
                              },
                              title: Text(item.name),
                              subtitle: Text(_cartSubtitle(item)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isCartSelectionMode)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: isSelected
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 18,
                                      ),
                                    )
                                  else if (isSelected)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                    ),
                                  Text(
                                    'Rp ${((item.price + _modifierExtraFromData(item.modifiersData)) * item.quantity).toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                            );

                            if (_isCartSelectionMode) {
                              return tile;
                            }

                            return Slidable(
                              key: ValueKey(key),
                              endActionPane: ActionPane(
                                motion: const ScrollMotion(),
                                extentRatio: 0.24,
                                children: [
                                  SlidableAction(
                                    onPressed: (_) {
                                      context.read<CartProvider>().removeItem(
                                        key,
                                      );
                                      setState(() {
                                        _selectedCartItems.remove(key);
                                      });
                                    },
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    icon: Icons.delete,
                                    label: 'Delete',
                                  ),
                                ],
                              ),
                              child: tile,
                            );
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: Colors.grey[200],
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total:',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Rp ${cart.totalAmount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: cart.items.isEmpty
                                  ? null
                                  : () async {
                                      final payment =
                                          await _showPaymentMethodModal(
                                            cart.totalAmount,
                                          );
                                      if (!context.mounted || payment == null) {
                                        return;
                                      }

                                      try {
                                        if (_currentActiveOrderId != null) {
                                          await cart.updateExistingOrder(
                                            orderId: _currentActiveOrderId!,
                                            customerName: _customerName,
                                            tableName: _tableName,
                                            orderType: _orderType,
                                            paymentMethod: payment.method,
                                            totalPaymentReceived:
                                                payment.totalPaymentReceived,
                                            cashNominalBreakdown:
                                                payment.cashNominalBreakdown,
                                            changeAmount: payment.changeAmount,
                                            status: 'completed',
                                          );
                                        } else {
                                          await cart.submitOrder(
                                            customerName: _customerName,
                                            tableName: _tableName,
                                            orderType: _orderType,
                                            paymentMethod: payment.method,
                                            totalPaymentReceived:
                                                payment.totalPaymentReceived,
                                            cashNominalBreakdown:
                                                payment.cashNominalBreakdown,
                                            changeAmount: payment.changeAmount,
                                            status: 'completed',
                                            parentOrderId:
                                                _pendingParentOrderIdForNextSubmit,
                                          );
                                        }
                                      } catch (error) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Failed to process payment: $error',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      _resetCurrentOrderDraft(
                                        showMessage: false,
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Payment success (${payment.method})',
                                          ),
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('PAY'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader({required String title, required Widget trailing}) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category.trim().toLowerCase()) {
      case 'coffee':
        return Colors.brown;
      case 'tea':
        return Colors.green;
      case 'non coffee':
      case 'non-coffee':
        return Colors.deepPurple;
      case 'dessert':
      case 'pastry':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _cartSubtitle(CartItem item) {
    final selected =
        item.modifiers?.selections.values
            .expand((entries) => entries)
            .toList() ??
        <String>[];
    if (selected.isEmpty) {
      return 'x${item.quantity}';
    }

    return 'x${item.quantity} • ${selected.join(', ')}';
  }

  double _modifierExtraFromData(List<dynamic>? modifiersData) {
    if (modifiersData == null) {
      return 0;
    }

    return modifiersData.whereType<Map<String, dynamic>>().fold<double>(0, (
      sum,
      modifier,
    ) {
      final selected =
          modifier['selected_options'] as List<dynamic>? ?? <dynamic>[];
      return sum +
          selected.whereType<Map<String, dynamic>>().fold<double>(
            0,
            (s, option) => s + ((option['price'] as num?)?.toDouble() ?? 0),
          );
    });
  }

  String _formatRupiah(num amount) {
    final rounded = amount.round();
    final isNegative = rounded < 0;
    final digits = rounded.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

    return 'Rp ${isNegative ? '-' : ''}$grouped';
  }

  Widget _buildProductCard(Product product) {
    final categoryColor = _categoryColor(product.category);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onProductTap(product),
        child: ColoredBox(
          color: categoryColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  _formatRupiah(product.price),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCartItemEditor(String key, CartItem item) async {
    final product = Product(
      id: item.id,
      name: item.name,
      price: item.price,
      category: item.category,
      description: item.description,
      imageUrl: item.imageUrl,
      isAvailable: item.isAvailable,
      isBundle: item.isBundle,
      isRecommended: item.isRecommended,
      productBundles: item.productBundles,
      productModifiers: item.productModifiers,
    );

    await _editCartItem(key, item, product);
  }

  void _toggleSelectedCartItem(String key) {
    setState(() {
      if (_selectedCartItems.contains(key)) {
        _selectedCartItems.remove(key);
      } else {
        _selectedCartItems.add(key);
      }

      if (_selectedCartItems.isEmpty) {
        _isCartSelectionMode = false;
      }
    });
  }

  void _enterSelectionModeWithItem(String key) {
    setState(() {
      _isCartSelectionMode = true;
      _selectedCartItems.add(key);
    });
  }

  void _selectAllCartItems() {
    final items = context.read<CartProvider>().items;
    setState(() {
      _isCartSelectionMode = true;
      _selectedCartItems
        ..clear()
        ..addAll(items.keys);
    });
  }

  void _onCartSettingSelected(String value) async {
    if (value == 'gabung_nota') {
      await _handleMergeBill();
      return;
    }

    if (value == 'pisah_nota') {
      await _handleSplitBill();
      return;
    }

    if (value == 'batal_pesanan') {
      await _handleCancelOrder();
    }
  }

  Map<String, CartItem> _selectedCartEntries() {
    final cart = context.read<CartProvider>();
    final selected = <String, CartItem>{};
    for (final key in _selectedCartItems) {
      final item = cart.items[key];
      if (item != null) {
        selected[key] = item;
      }
    }
    return selected;
  }

  Future<List<Map<String, dynamic>>> _fetchOtherActiveOrders() async {
    final rows = await supabase
        .from('orders')
        .select('id, customer_name, total_price, order_source, type, notes')
        .eq('status', 'active')
        .neq('id', _currentActiveOrderId ?? -1)
        .order('created_at');

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>?> _showSelectOrderDialog({
    required String title,
    required List<Map<String, dynamic>> orders,
  }) async {
    if (orders.isEmpty) {
      return null;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = orders[index];
                final orderId = order['id'];
                final customerName = order['customer_name'] ?? 'Guest';
                final total = order['total_price'] ?? 0;
                return ListTile(
                  title: Text('Order #$orderId - $customerName'),
                  subtitle: Text('Total: Rp $total'),
                  onTap: () => Navigator.of(dialogContext).pop(order),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItemRows(int orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('id, product_id, quantity, price_at_time, modifiers')
        .eq('order_id', orderId);

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  }

  dynamic _canonicalizeJsonValue(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonicalizeJsonValue(entry.value),
      };
    }

    if (value is List) {
      final canonicalItems = value.map(_canonicalizeJsonValue).toList();
      final allScalar = canonicalItems.every(
        (item) => item is String || item is num || item is bool || item == null,
      );
      if (allScalar) {
        canonicalItems.sort((a, b) => a.toString().compareTo(b.toString()));
        return canonicalItems;
      }

      canonicalItems.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      return canonicalItems;
    }

    return value;
  }

  String _modifierSignature(dynamic rawModifiers) {
    final normalized = _normalizeRawModifiers(rawModifiers);
    final canonical = _canonicalizeJsonValue(normalized);
    return jsonEncode(canonical);
  }

  String _orderItemRowSignature(Map<String, dynamic> row) {
    final productId = (row['product_id'] as num?)?.toInt() ?? 0;
    final quantity = (row['quantity'] as num?)?.toInt() ?? 0;
    final priceAtTime = (row['price_at_time'] as num?)?.toDouble() ?? 0;

    return [
      productId,
      quantity,
      priceAtTime.toStringAsFixed(6),
      _modifierSignature(row['modifiers']),
    ].join('|');
  }

  String _selectedCartItemSignature(CartItem item) {
    return [
      item.id,
      item.quantity,
      item.price.toStringAsFixed(6),
      _modifierSignature(item.modifiers?.toJson()),
    ].join('|');
  }

  List<int> _matchSelectedOrderItemIds({
    required List<Map<String, dynamic>> rows,
    required Iterable<CartItem> selectedItems,
  }) {
    final rowBuckets = <String, List<int>>{};

    for (final row in rows) {
      final rowId = (row['id'] as num?)?.toInt();
      if (rowId == null) {
        continue;
      }

      final signature = _orderItemRowSignature(row);
      rowBuckets.putIfAbsent(signature, () => <int>[]).add(rowId);
    }

    final matchedIds = <int>[];
    for (final item in selectedItems) {
      final signature = _selectedCartItemSignature(item);
      final bucket = rowBuckets[signature];
      if (bucket == null || bucket.isEmpty) {
        continue;
      }

      matchedIds.add(bucket.removeAt(0));
    }

    return matchedIds;
  }

  num _normalizeNum(num value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.000001) {
      return rounded.toInt();
    }
    return value;
  }

  Future<void> _recalculateAndPersistOrderTotals(int orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('quantity, price_at_time')
        .eq('order_id', orderId);

    var total = 0.0;
    for (final row
        in (rows as List<dynamic>).whereType<Map<String, dynamic>>()) {
      final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
      final price = (row['price_at_time'] as num?)?.toDouble() ?? 0;
      total += quantity * price;
    }

    final normalizedTotal = _normalizeNum(total);

    await supabase
        .from('orders')
        .update({
          'total_price': normalizedTotal,
          'subtotal': normalizedTotal,
          'discount_total': 0,
        })
        .eq('id', orderId);
  }

  Future<int> _generateDailyUniqueOrderId() async {
    final now = DateTime.now();
    final year = (now.year % 100).toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final prefix = '$year$month$day';
    final prefixValue = int.parse(prefix);
    final minId = prefixValue * 1000;
    final maxId = minId + 999;

    final existingRows = await supabase
        .from('orders')
        .select('id')
        .gte('id', minId)
        .lte('id', maxId);

    final usedIds = (existingRows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((row) => int.tryParse(row['id'].toString()))
        .whereType<int>()
        .toSet();

    if (usedIds.length >= 1000) {
      throw Exception('Daily order id capacity exhausted for $prefix');
    }

    for (var suffix = 0; suffix < 1000; suffix++) {
      final candidate = minId + suffix;
      if (!usedIds.contains(candidate)) {
        return candidate;
      }
    }

    throw Exception('Unable to generate daily unique order id for $prefix');
  }

  String? _buildOrderNotes({String? tableName, String? extraNote}) {
    final parts = <String>[];
    final normalizedTable = tableName?.trim() ?? '';
    final normalizedExtra = extraNote?.trim() ?? '';

    if (normalizedTable.isNotEmpty) {
      parts.add('Table: $normalizedTable');
    }

    if (normalizedExtra.isNotEmpty) {
      parts.add(normalizedExtra);
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join('\n');
  }

  String? _tableNameFromNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) {
      return null;
    }

    for (final line in notes.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Table:')) {
        final table = trimmed.replaceFirst('Table:', '').trim();
        return table.isEmpty ? null : table;
      }
    }

    return null;
  }

  Future<String?> _showCancelReasonDialog() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Batal pesanan'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Alasan batal (opsional)',
              hintText: 'Contoh: Customer ubah pesanan',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Konfirmasi'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return reason;
  }

  Future<int> _createActiveOrderDraft({
    String? customerName,
    String? tableName,
    required String orderType,
    int? parentOrderId,
    String? extraNote,
  }) async {
    final orderId = await _generateDailyUniqueOrderId();
    await supabase.from('orders').insert({
      'id': orderId,
      'status': 'active',
      'type': orderType,
      'order_source': 'cashier',
      'payment_method': null,
      'total_price': 0,
      'subtotal': 0,
      'discount_total': 0,
      'points_earned': 0,
      'points_used': 0,
      'total_payment_received': null,
      'cash_nominal_breakdown': null,
      'change_amount': null,
      'customer_name': customerName,
      'parent_order_id': parentOrderId,
      'notes': _buildOrderNotes(tableName: tableName, extraNote: extraNote),
    });

    return orderId;
  }

  Future<void> _insertCartEntriesToOrder({
    required int orderId,
    required Iterable<CartItem> items,
  }) async {
    final payload = items
        .map(
          (item) => {
            'order_id': orderId,
            'product_id': item.id,
            'quantity': item.quantity,
            'price_at_time': item.price,
            'modifiers': item.modifiers?.toJson(),
          },
        )
        .toList();

    if (payload.isEmpty) {
      return;
    }

    await supabase.from('order_items').insert(payload);
  }

  Future<bool> _cancelSourceIfNoRemainingItems(
    int sourceOrderId, {
    String? extraNote,
  }) async {
    final remaining = await _fetchOrderItemRows(sourceOrderId);
    if (remaining.isNotEmpty) {
      return false;
    }

    final existingOrder = await supabase
        .from('orders')
        .select('notes')
        .eq('id', sourceOrderId)
        .single();
    final existingNotes = existingOrder['notes']?.toString();

    final updatedNotes = _buildOrderNotes(
      tableName: _tableNameFromNotes(existingNotes),
      extraNote: extraNote,
    );

    await supabase
        .from('orders')
        .update({'status': OrderStatus.cancelled, 'notes': updatedNotes})
        .eq('id', sourceOrderId);
    return true;
  }

  Future<void> _handleMergeBill() async {
    final selectedEntries = _selectedCartEntries();
    if (selectedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih item yang ingin digabung dulu.')),
      );
      return;
    }

    final targetCandidates = await _fetchOtherActiveOrders();
    if (!mounted) return;
    if (targetCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada order aktif tujuan gabung.')),
      );
      return;
    }

    final target = await _showSelectOrderDialog(
      title: 'Gabung ke order aktif',
      orders: targetCandidates,
    );
    if (!mounted || target == null) return;

    final targetOrderId = int.tryParse(target['id'].toString());
    if (targetOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order tujuan tidak valid.')),
      );
      return;
    }

    try {
      if (_currentActiveOrderId != null) {
        final cart = context.read<CartProvider>();
        await cart.updateExistingOrder(
          orderId: _currentActiveOrderId!,
          customerName: _customerName,
          tableName: _tableName,
          orderType: _orderType,
        );

        final rows = await _fetchOrderItemRows(_currentActiveOrderId!);
        final selectedIds = _matchSelectedOrderItemIds(
          rows: rows,
          selectedItems: selectedEntries.values,
        );

        if (selectedIds.isEmpty) {
          throw Exception(
            'Tidak menemukan item order yang dipilih untuk digabung.',
          );
        }

        await supabase
            .from('order_items')
            .update({'order_id': targetOrderId})
            .inFilter('id', selectedIds);

        await _recalculateAndPersistOrderTotals(_currentActiveOrderId!);
        await _recalculateAndPersistOrderTotals(targetOrderId);

        final sourceCancelled = await _cancelSourceIfNoRemainingItems(
          _currentActiveOrderId!,
          extraNote: 'Merged into Order #$targetOrderId',
        );
        if (sourceCancelled) {
          _resetCurrentOrderDraft(showMessage: false);
        } else {
          final refreshed = await supabase
              .from('orders')
              .select('id, customer_name, type, notes')
              .eq('id', _currentActiveOrderId!)
              .single();
          if (!mounted) return;
          await _switchToActiveOrder(refreshed);
        }
      } else {
        await _insertCartEntriesToOrder(
          orderId: targetOrderId,
          items: selectedEntries.values,
        );
        await _recalculateAndPersistOrderTotals(targetOrderId);
        final cart = context.read<CartProvider>();
        for (final key in selectedEntries.keys) {
          cart.removeItem(key);
        }
        setState(() {
          _selectedCartItems.removeAll(selectedEntries.keys);
          _isCartSelectionMode = _selectedCartItems.isNotEmpty;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal gabung nota: $error')));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Item berhasil digabung ke Order #$targetOrderId'),
      ),
    );
  }

  Future<void> _handleSplitBill() async {
    if (_currentActiveOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pisah nota membutuhkan order aktif. Simpan order dulu lalu coba lagi.',
          ),
        ),
      );
      return;
    }

    final selectedEntries = _selectedCartEntries();
    if (selectedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih item yang ingin dipisah dulu.')),
      );
      return;
    }

    final sourceOrderId = _currentActiveOrderId!;

    try {
      final cart = context.read<CartProvider>();
      await cart.updateExistingOrder(
        orderId: sourceOrderId,
        customerName: _customerName,
        tableName: _tableName,
        orderType: _orderType,
      );

      final rows = await _fetchOrderItemRows(sourceOrderId);
      final selectedIds = _matchSelectedOrderItemIds(
        rows: rows,
        selectedItems: selectedEntries.values,
      );

      if (selectedIds.isEmpty) {
        throw Exception(
          'Tidak menemukan item order yang dipilih untuk dipisah.',
        );
      }

      await supabase.from('order_items').delete().inFilter('id', selectedIds);

      await _recalculateAndPersistOrderTotals(sourceOrderId);
      await _cancelSourceIfNoRemainingItems(
        sourceOrderId,
        extraNote: 'Items split to new cashier draft',
      );

      cart.clearCart();
      for (final item in selectedEntries.values) {
        cart.addItem(
          item,
          quantity: item.quantity,
          modifiers: item.modifiers,
          modifiersData: item.modifiersData,
        );
      }

      if (!mounted) return;
      setState(() {
        _currentActiveOrderId = null;
        _pendingParentOrderIdForNextSubmit = sourceOrderId;
        _customerName = null;
        _tableName = null;
        _selectedCartItems.clear();
        _isCartSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Item dipisah ke draft baru. Parent order: #$sourceOrderId',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal pisah nota: $error')));
    }
  }

  Future<void> _handleCancelOrder() async {
    final cancelReason = await _showCancelReasonDialog();
    if (!mounted || cancelReason == null) {
      return;
    }

    if (_currentActiveOrderId != null) {
      try {
        final reasonText = cancelReason.trim().isEmpty
            ? 'Cancelled from cashier app'
            : 'Cancel reason: ${cancelReason.trim()}';

        await supabase
            .from('orders')
            .update({
              'status': OrderStatus.cancelled,
              'notes': _buildOrderNotes(
                tableName: _tableName,
                extraNote: reasonText,
              ),
            })
            .eq('id', _currentActiveOrderId!);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal batal pesanan: $error')));
        return;
      }
    }

    if (!mounted) return;
    _resetCurrentOrderDraft(showMessage: false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Pesanan dibatalkan')));
  }

  void _resetCurrentOrderDraft({bool showMessage = true}) {
    context.read<CartProvider>().clearCart();
    setState(() {
      _customerName = null;
      _tableName = null;
      _orderType = 'dine_in';
      _currentActiveOrderId = null;
      _selectedCartItems.clear();
      _isCartSelectionMode = false;
      _pendingParentOrderIdForNextSubmit = null;
    });

    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart dan detail order di-reset')),
      );
    }
  }

  Widget _buildCartOrderDetailsTab() {
    return InkWell(
      onTap: _showOfflineOrderDetailModal,
      child: Container(
        width: double.infinity,
        color: Colors.blueGrey.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.receipt, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _customerName == null && _tableName == null
                    ? 'Order details'
                    : '$_orderType • ${_customerName ?? '-'} • Table ${_tableName ?? '-'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Future<void> _showOfflineOrderDetailModal() async {
    final nameController = TextEditingController(text: _customerName ?? '');
    final tableController = TextEditingController(text: _tableName ?? '');
    var selectedType = _orderType;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Offline Order Details'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Customer name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: tableController,
                      decoration: const InputDecoration(labelText: 'Table'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Order type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'dine_in',
                          child: Text('Dine In'),
                        ),
                        DropdownMenuItem(
                          value: 'takeaway',
                          child: Text('Takeaway'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => selectedType = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _customerName = nameController.text.trim().isEmpty
                          ? null
                          : nameController.text.trim();
                      _tableName = tableController.text.trim().isEmpty
                          ? null
                          : tableController.text.trim();
                      _orderType = selectedType;
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onProductTap(Product product) async {
    final modifiers = await _fetchProductModifiers(product);
    if (!mounted) return;

    final config = await _showProductConfigModal(product, modifiers);
    if (!mounted || config == null) {
      return;
    }

    context.read<CartProvider>().addItem(
      product,
      quantity: config.quantity,
      modifiers: config.cartModifiers,
      modifiersData: config.modifiersData,
    );
  }

  Future<void> _editCartItem(String key, CartItem item, Product product) async {
    final modifiers = await _fetchProductModifiers(product);
    if (!mounted) return;

    final config = await _showProductConfigModal(
      product,
      modifiers,
      initialQuantity: item.quantity,
      initialModifiers: item.modifiers,
    );

    if (!mounted || config == null) return;

    context.read<CartProvider>().replaceItem(
      existingKey: key,
      product: product,
      quantity: config.quantity,
      modifiers: config.cartModifiers,
      modifiersData: config.modifiersData,
    );
  }

  Future<List<ProductModifier>> _fetchProductModifiers(Product product) async {
    List<ProductModifier> fromRaw(dynamic raw) {
      List<dynamic> groups;
      if (raw is List) {
        groups = raw;
      } else if (raw is Map<String, dynamic> && raw['groups'] is List) {
        groups = raw['groups'] as List<dynamic>;
      } else {
        return <ProductModifier>[];
      }

      return groups
          .whereType<Map<String, dynamic>>()
          .map((group) {
            final optionsRaw =
                (group['options'] as List<dynamic>?) ??
                (group['modifier_options'] as List<dynamic>?) ??
                <dynamic>[];
            final options = optionsRaw
                .whereType<Map<String, dynamic>>()
                .map(
                  (option) => ModifierOption(
                    id:
                        option['id']?.toString() ??
                        option['name']?.toString() ??
                        '',
                    name: option['name'] as String? ?? '',
                    price: (option['price'] as num?)?.toDouble() ?? 0,
                  ),
                )
                .toList();

            return ProductModifier(
              id:
                  group['id']?.toString() ??
                  group['name']?.toString() ??
                  'modifier',
              name: group['name'] as String? ?? 'Modifier',
              isRequired:
                  (group['is_required'] as bool?) ??
                  (group['isRequired'] as bool?) ??
                  false,
              type: group['type'] as String? ?? 'single',
              options: options,
            );
          })
          .where((modifier) => modifier.options.isNotEmpty)
          .toList();
    }

    final fromProduct = fromRaw(product.productModifiers);
    if (fromProduct.isNotEmpty) {
      return fromProduct;
    }

    try {
      final row = await supabase
          .from('products')
          .select('modifiers')
          .eq('id', product.id)
          .maybeSingle();

      final parsed = fromRaw(row?['modifiers']);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // fallback below
    }

    return <ProductModifier>[];
  }

  Future<_ModifierSelectionResult?> _showProductConfigModal(
    Product product,
    List<ProductModifier> modifiers, {
    int initialQuantity = 1,
    CartModifiers? initialModifiers,
  }) async {
    var quantity = initialQuantity;
    final selectedByModifier = <String, List<ModifierOption>>{
      for (final modifier in modifiers) modifier.id: <ModifierOption>[],
    };

    if (initialModifiers != null) {
      for (final modifier in modifiers) {
        final names = initialModifiers.selections[modifier.name] ?? <String>[];
        selectedByModifier[modifier.id] = modifier.options
            .where((option) => names.contains(option.name))
            .toList();
      }
    }

    return showDialog<_ModifierSelectionResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogStateContext, setState) {
            final selectedModifierExtra = selectedByModifier.values
                .expand((items) => items)
                .fold<double>(0, (sum, option) => sum + option.price);
            final lineTotal =
                (product.price + selectedModifierExtra) * quantity;

            return AlertDialog(
              title: Text('Customize ${product.name}'),
              content: SizedBox(
                width: 460,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Quantity',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: quantity > 1
                              ? () => setState(() => quantity--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$quantity', style: const TextStyle(fontSize: 16)),
                        IconButton(
                          onPressed: () => setState(() => quantity++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const Divider(),
                    ...modifiers.map((modifier) {
                      final currentSelected =
                          selectedByModifier[modifier.id] ?? <ModifierOption>[];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${modifier.name}${modifier.isRequired ? ' *' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...modifier.options.map((option) {
                              final isSingle = modifier.type == 'single';
                              final isSelected = currentSelected.any(
                                (item) => item.id == option.id,
                              );

                              if (isSingle) {
                                return RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(_optionLabel(option)),
                                  value: option.id,
                                  groupValue: currentSelected.isEmpty
                                      ? null
                                      : currentSelected.first.id,
                                  onChanged: (_) {
                                    setState(() {
                                      selectedByModifier[modifier.id] = [
                                        option,
                                      ];
                                    });
                                  },
                                );
                              }

                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(_optionLabel(option)),
                                value: isSelected,
                                onChanged: (checked) {
                                  setState(() {
                                    final next = List<ModifierOption>.from(
                                      currentSelected,
                                    );
                                    if (checked == true) {
                                      if (!next.any(
                                        (item) => item.id == option.id,
                                      )) {
                                        next.add(option);
                                      }
                                    } else {
                                      next.removeWhere(
                                        (item) => item.id == option.id,
                                      );
                                    }
                                    selectedByModifier[modifier.id] = next;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Total: ${_formatRupiah(lineTotal)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final missingRequired = modifiers.any(
                                  (modifier) =>
                                      modifier.isRequired &&
                                      (selectedByModifier[modifier.id] ??
                                              <ModifierOption>[])
                                          .isEmpty,
                                );

                                if (missingRequired) {
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please complete all required modifiers.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                final cartSelections = <String, List<String>>{};
                                final modifiersData = <Map<String, dynamic>>[];

                                for (final modifier in modifiers) {
                                  final selected =
                                      selectedByModifier[modifier.id] ??
                                      <ModifierOption>[];
                                  if (selected.isEmpty) continue;

                                  cartSelections[modifier.name] = selected
                                      .map((item) => item.name)
                                      .toList();

                                  modifiersData.add({
                                    'modifier_id': modifier.id,
                                    'modifier_name': modifier.name,
                                    'type': modifier.type,
                                    'selected_options': selected
                                        .map(
                                          (option) => {
                                            'id': option.id,
                                            'name': option.name,
                                            'price': option.price,
                                          },
                                        )
                                        .toList(),
                                  });
                                }

                                Navigator.of(dialogContext).pop(
                                  _ModifierSelectionResult(
                                    quantity: quantity,
                                    cartModifiers: cartSelections.isEmpty
                                        ? null
                                        : CartModifiers(
                                            selections: cartSelections,
                                            notes: '',
                                          ),
                                    modifiersData: modifiersData,
                                  ),
                                );
                              },
                              child: const Text('Add to Cart'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _optionLabel(ModifierOption option) {
    if (option.price == 0) {
      return option.name;
    }

    return '${option.name} (+${_formatRupiah(option.price)})';
  }

  Future<_PaymentResult?> _showPaymentMethodModal(double totalAmount) async {
    const cashDenominations = <int>[
      1000,
      2000,
      5000,
      10000,
      20000,
      50000,
      100000,
    ];

    var paymentMethod = 'cash';
    var selectedCashCounts = <int, int>{};

    return showDialog<_PaymentResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final cashPaid = selectedCashCounts.entries.fold<int>(
              0,
              (sum, entry) => sum + (entry.key * entry.value),
            );
            final change = cashPaid - totalAmount;
            final selectedBreakdown = cashDenominations
                .where((value) => (selectedCashCounts[value] ?? 0) > 0)
                .map((value) => 'Rp $value x${selectedCashCounts[value]}')
                .toList();

            return AlertDialog(
              title: const Text('Payment Method'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total: ${_formatRupiah(totalAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash', label: Text('Cash')),
                        ButtonSegment(value: 'qris', label: Text('QRIS')),
                      ],
                      selected: {paymentMethod},
                      onSelectionChanged: (selection) {
                        setState(() {
                          paymentMethod = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (paymentMethod == 'cash') ...[
                      const Text('Pilih nominal uang:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: cashDenominations.map((value) {
                          return ActionChip(
                            label: Text(_formatRupiah(value)),
                            onPressed: () {
                              setState(() {
                                selectedCashCounts = {
                                  ...selectedCashCounts,
                                  value: (selectedCashCounts[value] ?? 0) + 1,
                                };
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      if (selectedBreakdown.isNotEmpty) ...[
                        const Text(
                          'Nominal terpilih (tap - untuk mengurangi):',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: cashDenominations
                              .where(
                                (value) => (selectedCashCounts[value] ?? 0) > 0,
                              )
                              .map((value) {
                                final count = selectedCashCounts[value] ?? 0;
                                return InputChip(
                                  avatar: const Icon(Icons.remove, size: 18),
                                  label: Text('Rp $value x$count'),
                                  onPressed: () {
                                    setState(() {
                                      final nextCount = count - 1;
                                      selectedCashCounts = {
                                        ...selectedCashCounts,
                                      };
                                      if (nextCount <= 0) {
                                        selectedCashCounts.remove(value);
                                      } else {
                                        selectedCashCounts[value] = nextCount;
                                      }
                                    });
                                  },
                                );
                              })
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text('Dibayar: Rp $cashPaid'),
                      if (selectedBreakdown.isNotEmpty)
                        Text(
                          selectedBreakdown.join(', '),
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      Text(
                        'Kembalian: Rp ${change > 0 ? change.toStringAsFixed(0) : '0'}',
                      ),
                      const SizedBox(height: 6),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        height: 180,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade100,
                        ),
                        child: const Text(
                          'QRIS image placeholder\n(akan diisi nanti)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: paymentMethod == 'cash' && cashPaid < totalAmount
                      ? null
                      : () {
                          final normalizedTotal = totalAmount % 1 == 0
                              ? totalAmount.toInt()
                              : totalAmount;
                          final cashBreakdown = paymentMethod == 'cash'
                              ? selectedCashCounts.map(
                                  (key, value) =>
                                      MapEntry(key.toString(), value),
                                )
                              : null;
                          final totalPaymentReceived = paymentMethod == 'cash'
                              ? cashPaid
                              : normalizedTotal;
                          final changeAmount = paymentMethod == 'cash'
                              ? (cashPaid - totalAmount)
                              : 0;

                          Navigator.of(dialogContext).pop(
                            _PaymentResult(
                              method: paymentMethod,
                              totalPaymentReceived: totalPaymentReceived,
                              cashNominalBreakdown: cashBreakdown,
                              changeAmount: changeAmount,
                            ),
                          );
                        },
                  child: const Text('Confirm Payment'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _onlineOrderModifiersText(_OnlineOrderItem item) {
    final selections = item.modifiers?.selections;
    if (selections != null && selections.isNotEmpty) {
      return selections.entries
          .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
          .join('\n');
    }

    final data = item.modifiersData;
    if (data != null) {
      final parts = <String>[];
      for (final group in data.whereType<Map<String, dynamic>>()) {
        final name =
            group['modifier_name']?.toString() ??
            group['name']?.toString() ??
            'Modifier';
        final selected =
            (group['selected_options'] as List<dynamic>? ?? <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map((entry) => entry['name']?.toString() ?? '')
                .where((value) => value.isNotEmpty)
                .toList();
        if (selected.isNotEmpty) {
          parts.add('$name: ${selected.join(', ')}');
        }
      }
      if (parts.isNotEmpty) {
        return parts.join('\n');
      }
    }

    return '';
  }

  Future<void> _showActiveCashierOrdersDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Switch Active Order'),
          content: SizedBox(
            width: 500,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _activeOrdersStream,
              builder: (context, snapshot) {
                final activeOrders = snapshot.data ?? <Map<String, dynamic>>[];
                final switchableOrders = activeOrders.where((order) {
                  final id = int.tryParse(order['id']?.toString() ?? '');
                  return id == null || id != _currentActiveOrderId;
                }).toList();
                if (snapshot.connectionState == ConnectionState.waiting &&
                    switchableOrders.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (switchableOrders.isEmpty) {
                  return const Text('No other active orders.');
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: switchableOrders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = switchableOrders[index];
                    final orderId = order['id'];
                    final customerName = order['customer_name'] ?? 'Guest';
                    final total =
                        order['total_price'] ?? order['total_amount'] ?? 0;
                    final source = order['order_source']?.toString() ?? '-';
                    return ListTile(
                      title: Text('Order #$orderId - $customerName'),
                      subtitle: Text(
                        'Total: ${_formatRupiah((total as num?) ?? 0)} • Source: $source',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final canContinue = await _handleDraftBeforeSwitch(
                          dialogContext,
                        );
                        if (!canContinue || !context.mounted) {
                          return;
                        }

                        await _switchToActiveOrder(order);
                        if (!context.mounted) return;
                        Navigator.of(dialogContext).pop();
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  bool get _hasOrderDetailDraft {
    final customer = _customerName?.trim() ?? '';
    final table = _tableName?.trim() ?? '';
    return customer.isNotEmpty || table.isNotEmpty;
  }

  Future<bool> _handleDraftBeforeSwitch(BuildContext dialogContext) async {
    final cart = context.read<CartProvider>();

    if (_currentActiveOrderId != null) {
      try {
        await cart.updateExistingOrder(
          orderId: _currentActiveOrderId!,
          customerName: _customerName,
          tableName: _tableName,
          orderType: _orderType,
        );
      } catch (error) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update current order: $error')),
        );
        return false;
      }

      if (!mounted) return false;
      setState(() {
        _selectedCartItems.clear();
        _isCartSelectionMode = false;
        _pendingParentOrderIdForNextSubmit = null;
      });
      return true;
    }

    if (cart.items.isEmpty) {
      return true;
    }

    if (_hasOrderDetailDraft) {
      try {
        await cart.submitOrder(
          customerName: _customerName,
          tableName: _tableName,
          orderType: _orderType,
          parentOrderId: _pendingParentOrderIdForNextSubmit,
        );
      } catch (error) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save current order: $error')),
        );
        return false;
      }

      if (!mounted) return false;

      setState(() {
        _selectedCartItems.clear();
        _selectedCartItems.clear();
        _isCartSelectionMode = false;
        _pendingParentOrderIdForNextSubmit = null;
      });

      return true;
    }

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Order detail is empty'),
          content: const Text(
            'If you switch now, current cart items will be erased. '
            'Add order detail first if you want to keep this order.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Add Order Detail'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue Switching'),
            ),
          ],
        );
      },
    );

    if (!mounted) return false;
    if (shouldContinue == true) {
      return true;
    }

    Navigator.of(dialogContext).pop();
    await _showOfflineOrderDetailModal();
    if (!mounted) return false;
    await _showActiveCashierOrdersDialog();
    return false;
  }

  Future<void> _switchToActiveOrder(Map<String, dynamic> order) async {
    final orderId = order['id'];
    if (orderId == null) {
      return;
    }

    final cart = context.read<CartProvider>();
    final items = await _fetchOrderItems(orderId as int);
    if (!mounted) return;

    cart.clearCart();
    for (final item in items) {
      cart.addItem(
        item.product,
        quantity: item.quantity,
        modifiers: item.modifiers,
        modifiersData: item.modifiersData,
      );
    }

    setState(() {
      _currentActiveOrderId = orderId as int;
      _customerName = order['customer_name']?.toString();
      _orderType = order['type']?.toString() ?? _orderType;
      final notes = order['notes']?.toString();
      _tableName = _tableNameFromNotes(notes);
      _selectedCartItems.clear();
      _isCartSelectionMode = false;
      _pendingParentOrderIdForNextSubmit = null;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Switched to Order #$orderId')));
  }

  Future<void> _showOnlineOrdersDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Online Pending Orders'),
          content: SizedBox(
            width: 500,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _onlinePendingOrdersStream,
              builder: (context, snapshot) {
                final orders = snapshot.data ?? <Map<String, dynamic>>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    orders.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (orders.isEmpty) {
                  return const Text('No pending online orders.');
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final orderId = order['id'];
                    final customerName = order['customer_name'] ?? 'Guest';
                    final totalPrice =
                        order['total_price'] ?? order['total_amount'] ?? 0;
                    return ListTile(
                      title: Text('Order #$orderId - $customerName'),
                      subtitle: Text(
                        'Total: ${_formatRupiah((totalPrice as num?) ?? 0)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _showOrderDetailModal(order);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showOrderDetailModal(Map<String, dynamic> order) async {
    final orderId = order['id'];
    if (orderId == null) return;

    final items = await _fetchOrderItems(orderId as int);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Order #$orderId'),
          content: SizedBox(
            width: 520,
            child: items.isEmpty
                ? const Text('No order items found.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        title: Text(item.product.name),
                        subtitle: Text(
                          (() {
                            final modifiersText = _onlineOrderModifiersText(
                              item,
                            );
                            if (modifiersText.isEmpty) {
                              return 'Qty: ${item.quantity}';
                            }
                            return 'Qty: ${item.quantity}\n$modifiersText';
                          })(),
                        ),
                        trailing: Text(
                          _formatRupiah(
                            ((item.product.price +
                                    _modifierExtraFromData(
                                      item.modifiersData,
                                    )) *
                                item.quantity),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final updated = await _updateOrderStatusIfPending(
                  orderId,
                  OrderStatus.cancelled,
                );

                if (!context.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!updated) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Order status changed by another user. Refresh applied.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Decline'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updated = await _updateOrderStatusIfPending(
                  orderId,
                  OrderStatus.processing,
                );

                if (!context.mounted) return;
                if (!updated) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Order already handled from another app/session.',
                      ),
                    ),
                  );
                  return;
                }

                final cart = context.read<CartProvider>();
                for (final item in items) {
                  cart.addItem(
                    item.product,
                    quantity: item.quantity,
                    modifiers: item.modifiers,
                    modifiersData: item.modifiersData,
                  );
                }

                Navigator.of(dialogContext).pop();
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  Future<List<_OnlineOrderItem>> _fetchOrderItems(int orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('quantity, product_id, modifiers, products(*)')
        .eq('order_id', orderId);

    final List<_OnlineOrderItem> items = [];
    for (final row in rows as List<dynamic>) {
      final data = row as Map<String, dynamic>;
      final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
      final productData = data['products'] as Map<String, dynamic>?;
      final rawModifiers = data['modifiers'];

      if (productData != null) {
        final product = Product.fromJson(productData);
        items.add(
          _OnlineOrderItem(
            product: product,
            quantity: quantity,
            modifiers: _toCartModifiers(rawModifiers, product),
            modifiersData: _toModifiersData(rawModifiers, product),
          ),
        );
      }
    }

    return items;
  }

  dynamic _normalizeRawModifiers(dynamic rawModifiers) {
    if (rawModifiers is String) {
      try {
        return jsonDecode(rawModifiers);
      } catch (_) {
        return null;
      }
    }
    return rawModifiers;
  }

  Map<String, String> _modifierGroupNameLookup(Product product) {
    final lookup = <String, String>{};
    final groups = product.productModifiers;
    if (groups == null) {
      return lookup;
    }

    for (final group in groups.whereType<Map<String, dynamic>>()) {
      final id = group['id']?.toString();
      final name = group['name']?.toString();
      if (id != null && name != null && name.isNotEmpty) {
        lookup[id] = name;
      }
    }

    return lookup;
  }

  Map<String, double> _modifierOptionPriceByNameLookup(Product product) {
    final lookup = <String, double>{};
    final groups = product.productModifiers;
    if (groups == null) {
      return lookup;
    }

    for (final group in groups.whereType<Map<String, dynamic>>()) {
      final options =
          (group['options'] as List<dynamic>?) ??
          (group['modifier_options'] as List<dynamic>?) ??
          <dynamic>[];
      for (final option in options.whereType<Map<String, dynamic>>()) {
        final name = option['name']?.toString();
        if (name != null && name.isNotEmpty) {
          lookup[name] = (option['price'] as num?)?.toDouble() ?? 0;
        }
      }
    }

    return lookup;
  }

  Map<String, String> _modifierOptionNameLookup(Product product) {
    final lookup = <String, String>{};
    final groups = product.productModifiers;
    if (groups == null) {
      return lookup;
    }

    for (final group in groups.whereType<Map<String, dynamic>>()) {
      final options =
          (group['options'] as List<dynamic>?) ??
          (group['modifier_options'] as List<dynamic>?) ??
          <dynamic>[];
      for (final option in options.whereType<Map<String, dynamic>>()) {
        final id = option['id']?.toString();
        final name = option['name']?.toString();
        if (id != null && name != null && name.isNotEmpty) {
          lookup[id] = name;
        }
      }
    }

    return lookup;
  }

  Map<String, double> _modifierOptionPriceLookup(Product product) {
    final lookup = <String, double>{};
    final groups = product.productModifiers;
    if (groups == null) {
      return lookup;
    }

    for (final group in groups.whereType<Map<String, dynamic>>()) {
      final options =
          (group['options'] as List<dynamic>?) ??
          (group['modifier_options'] as List<dynamic>?) ??
          <dynamic>[];
      for (final option in options.whereType<Map<String, dynamic>>()) {
        final id = option['id']?.toString();
        if (id != null) {
          lookup[id] = (option['price'] as num?)?.toDouble() ?? 0;
        }
      }
    }

    return lookup;
  }

  CartModifiers? _toCartModifiers(dynamic rawModifiers, Product product) {
    final normalized = _normalizeRawModifiers(rawModifiers);
    if (normalized == null) {
      return null;
    }

    if (normalized is Map<String, dynamic>) {
      final selectionsRaw = normalized['selections'];
      if (selectionsRaw is Map<String, dynamic>) {
        return CartModifiers.fromJson(normalized);
      }

      final selectedOptions = normalized['selected_options'];
      if (selectedOptions is List) {
        final names = selectedOptions
            .whereType<Map<String, dynamic>>()
            .map((entry) => entry['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();

        return CartModifiers(
          selections: {
            normalized['modifier_name']?.toString() ?? 'Modifier': names,
          },
          notes: '',
        );
      }

      final groupNameLookup = _modifierGroupNameLookup(product);
      final optionLookup = _modifierOptionNameLookup(product);
      final selections = <String, List<String>>{};

      for (final entry in normalized.entries) {
        final optionIds = (entry.value as List<dynamic>? ?? <dynamic>[])
            .map((item) => item.toString())
            .toList();

        if (optionIds.isEmpty) {
          continue;
        }

        final groupName = groupNameLookup[entry.key] ?? entry.key;
        final optionNames = optionIds
            .map((id) => optionLookup[id] ?? id)
            .toList();
        selections[groupName] = optionNames;
      }

      if (selections.isNotEmpty) {
        return CartModifiers(selections: selections, notes: '');
      }
    }

    if (normalized is List) {
      final selections = <String, List<String>>{};
      for (final group in normalized.whereType<Map<String, dynamic>>()) {
        final groupName =
            group['modifier_name']?.toString() ??
            group['name']?.toString() ??
            'Modifier';
        final selected =
            (group['selected_options'] as List<dynamic>? ?? <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map((entry) => entry['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList();
        if (selected.isNotEmpty) {
          selections[groupName] = selected;
        }
      }
      if (selections.isNotEmpty) {
        return CartModifiers(selections: selections, notes: '');
      }
    }

    return null;
  }

  List<dynamic>? _toModifiersData(dynamic rawModifiers, Product product) {
    final normalized = _normalizeRawModifiers(rawModifiers);
    if (normalized == null) {
      return null;
    }

    if (normalized is List) {
      return normalized;
    }

    if (normalized is Map<String, dynamic>) {
      if (normalized['selected_options'] != null) {
        return [normalized];
      }

      if (normalized['selections'] is Map<String, dynamic>) {
        final optionPriceByName = _modifierOptionPriceByNameLookup(product);
        final selections =
            normalized['selections'] as Map<String, dynamic>? ??
            <String, dynamic>{};
        final list = <Map<String, dynamic>>[];

        for (final entry in selections.entries) {
          final selectedOptions = (entry.value as List<dynamic>? ?? <dynamic>[])
              .map((value) => value.toString())
              .where((name) => name.isNotEmpty)
              .map(
                (name) => {'name': name, 'price': optionPriceByName[name] ?? 0},
              )
              .toList();

          if (selectedOptions.isEmpty) {
            continue;
          }

          list.add({
            'modifier_name': entry.key,
            'selected_options': selectedOptions,
          });
        }

        return list.isEmpty ? null : list;
      }

      final groupNameLookup = _modifierGroupNameLookup(product);
      final optionLookup = _modifierOptionNameLookup(product);
      final optionPriceLookup = _modifierOptionPriceLookup(product);
      final list = <Map<String, dynamic>>[];

      for (final entry in normalized.entries) {
        final selectedOptions = (entry.value as List<dynamic>? ?? <dynamic>[])
            .map((id) {
              final optionId = id.toString();
              return {
                'id': optionId,
                'name': optionLookup[optionId] ?? optionId,
                'price': optionPriceLookup[optionId] ?? 0,
              };
            })
            .toList();

        if (selectedOptions.isEmpty) {
          continue;
        }

        list.add({
          'modifier_id': entry.key,
          'modifier_name': groupNameLookup[entry.key] ?? entry.key,
          'selected_options': selectedOptions,
        });
      }

      return list.isEmpty ? null : list;
    }

    return null;
  }

  Future<bool> _updateOrderStatusIfPending(int orderId, String status) async {
    final response = await supabase
        .from('orders')
        .update({'status': status})
        .eq('id', orderId)
        .eq('status', OrderStatus.pending)
        .select('id');

    final updatedRows = response as List<dynamic>;
    return updatedRows.isNotEmpty;
  }
}

class _PaymentResult {
  final String method;
  final num totalPaymentReceived;
  final Map<String, int>? cashNominalBreakdown;
  final num changeAmount;

  _PaymentResult({
    required this.method,
    required this.totalPaymentReceived,
    required this.cashNominalBreakdown,
    required this.changeAmount,
  });
}

class _OnlineOrderItem {
  final Product product;
  final int quantity;
  final CartModifiers? modifiers;
  final List<dynamic>? modifiersData;

  _OnlineOrderItem({
    required this.product,
    required this.quantity,
    this.modifiers,
    this.modifiersData,
  });
}

class _ModifierSelectionResult {
  final int quantity;
  final CartModifiers? cartModifiers;
  final List<dynamic> modifiersData;

  _ModifierSelectionResult({
    required this.quantity,
    required this.cartModifiers,
    required this.modifiersData,
  });
}

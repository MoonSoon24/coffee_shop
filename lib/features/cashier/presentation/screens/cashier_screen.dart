import 'dart:convert';
import 'dart:convert';
import 'dart:math';

import 'package:coffee_shop/core/constants/order_status.dart';
import 'package:coffee_shop/core/services/supabase_client.dart';
import 'package:coffee_shop/core/utils/formatters.dart';
import 'package:coffee_shop/features/cashier/models/models.dart';
import 'package:coffee_shop/features/cashier/providers/cart_provider.dart';
import 'package:coffee_shop/features/printing/presentation/dialogs/printer_settings_dialog.dart';
import 'package:coffee_shop/features/printing/services/thermal_printer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part '../../controllers/cashier_controller.dart';
part '../widgets/cashier_app_bar.dart';
part '../widgets/menu_grid.dart';
part '../widgets/cart_item_tile.dart';
part '../widgets/cart_panel.dart';
part '../../../online_orders/presentation/dialogs/online_orders_dialog.dart';
part '../../../online_orders/presentation/dialogs/order_detail_dialog.dart';
part '../../models/payment_result.dart';
part '../../models/modifier_selection_result.dart';
part '../../data/cashier_repository.dart';
part '../../../online_orders/data/online_orders_repository.dart';

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
  int? _activeShiftId;
  int? _activeCashierId;
  final Set<String> _selectedCartItems = <String>{};
  bool _isCartSelectionMode = false;
  int? _pendingParentOrderIdForNextSubmit;
  OverlayEntry? _snackbarOverlayEntry;
  AnimationController? _snackbarAnimationController;
  final CashierRepository _cashierRepository = CashierRepository();
  final OnlineOrdersRepository _onlineOrdersRepository =
      OnlineOrdersRepository();

  Stream<List<Map<String, dynamic>>> get _onlinePendingOrdersStream =>
      _onlineOrdersRepository.pendingOnlineOrdersStream();

  Stream<List<Map<String, dynamic>>> get _activeOrdersStream =>
      _cashierRepository.activeOrdersStream(
        cashierId: _activeCashierId,
        shiftId: _activeShiftId,
      );

  Stream<List<Map<String, dynamic>>> get _allOrdersStream => _cashierRepository
      .allOrdersStream(cashierId: _activeCashierId, shiftId: _activeShiftId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncShiftContext();
    });
  }

  @override
  void dispose() {
    _snackbarAnimationController?.dispose();
    _snackbarOverlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildCashierAppBar(),
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
                          final errorText = snapshot.error.toString();
                          final isPolicyError =
                              errorText.contains('row-level security') ||
                              errorText.contains('permission denied') ||
                              errorText.contains('not authorized') ||
                              errorText.contains('42501');

                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 40,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isPolicyError
                                        ? 'Data cannot be read because Supabase Row Level Security policy blocks this client.'
                                        : 'Error loading menu data.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    isPolicyError
                                        ? 'Fix by updating Supabase RLS SELECT policies so this app client is allowed to read products/orders.'
                                        : errorText,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
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
                            PopupMenuButton<String>(
                              tooltip: 'Print options',
                              icon: const Icon(Icons.print),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'prebill',
                                  child: Text('Print pre-settlement bill'),
                                ),
                                PopupMenuItem(
                                  value: 'kitchen',
                                  child: Text('Print to kitchen'),
                                ),
                              ],
                              onSelected: (value) async {
                                if (value == 'prebill') {
                                  await _printPreSettlementBill();
                                } else if (value == 'kitchen') {
                                  await _printKitchenTicket();
                                }
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

                                      final receiptItems = cart.items.values
                                          .map((item) {
                                            final modifierExtra =
                                                (item.modifiersData ??
                                                        <dynamic>[])
                                                    .whereType<
                                                      Map<String, dynamic>
                                                    >()
                                                    .fold<double>(0, (
                                                      sum,
                                                      modifier,
                                                    ) {
                                                      final selected =
                                                          modifier['selected_options']
                                                              as List<
                                                                dynamic
                                                              >? ??
                                                          <dynamic>[];
                                                      return sum +
                                                          selected
                                                              .whereType<
                                                                Map<
                                                                  String,
                                                                  dynamic
                                                                >
                                                              >()
                                                              .fold<double>(
                                                                0,
                                                                (s, option) =>
                                                                    s +
                                                                    ((option['price']
                                                                                as num?)
                                                                            ?.toDouble() ??
                                                                        0),
                                                              );
                                                    });
                                            final unitPrice =
                                                item.price + modifierExtra;
                                            return <String, dynamic>{
                                              'name': item.name,
                                              'qty': item.quantity,
                                              'subtotal':
                                                  unitPrice * item.quantity,
                                            };
                                          })
                                          .toList(growable: false);

                                      final totalBeforeSubmit =
                                          cart.totalAmount;
                                      int? paidOrderId;

                                      try {
                                        if (_currentActiveOrderId != null) {
                                          paidOrderId = await cart
                                              .updateExistingOrder(
                                                orderId: _currentActiveOrderId!,
                                                customerName: _customerName,
                                                tableName: _tableName,
                                                orderType: _orderType,
                                                paymentMethod: payment.method,
                                                totalPaymentReceived: payment
                                                    .totalPaymentReceived,
                                                cashNominalBreakdown: payment
                                                    .cashNominalBreakdown,
                                                changeAmount:
                                                    payment.changeAmount,
                                                status: 'completed',
                                              );
                                        } else {
                                          paidOrderId = await cart.submitOrder(
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
                                        await ThermalPrinterService.instance
                                            .printPaymentReceipt(
                                              orderId: paidOrderId!,
                                              lines: receiptItems,
                                              total: totalBeforeSubmit,
                                              paymentMethod: payment.method,
                                              paid:
                                                  payment.totalPaymentReceived,
                                              change: payment.changeAmount,
                                              customerName: _customerName,
                                              tableName: _tableName,
                                            );
                                      } catch (error) {
                                        if (!context.mounted) return;
                                        if (paidOrderId != null) {
                                          _showDropdownSnackbar(
                                            'Payment saved, but failed to print: $error',
                                            isError: true,
                                          );
                                        } else {
                                          _showDropdownSnackbar(
                                            'Failed to process payment: $error',
                                            isError: true,
                                          );
                                          return;
                                        }
                                      }

                                      _resetCurrentOrderDraft(
                                        showMessage: false,
                                      );
                                      _showDropdownSnackbar(
                                        'Payment success (${payment.method})',
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

  Color _categoryColor(String category) {
    switch (category.trim().toLowerCase()) {
      case 'coffee':
        return Colors.blue.shade700;
      case 'tea':
        return Colors.lightBlue.shade600;
      case 'non coffee':
      case 'non-coffee':
        return Colors.indigo.shade400;
      case 'dessert':
      case 'pastry':
        return Colors.blue.shade400;
      default:
        return Colors.blueGrey.shade500;
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
      'cashier_id': _activeCashierId,
      'shift_id': _activeShiftId,
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
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 24,
              ),
              constraints: const BoxConstraints(maxWidth: 460),
              title: Text('Customize ${product.name}'),
              content: SizedBox(
                width: 420,
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
                                  _showDropdownSnackbar(
                                    'Please complete all required modifiers.',
                                    isError: true,
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

  bool get _hasOrderDetailDraft {
    final customer = _customerName?.trim() ?? '';
    final table = _tableName?.trim() ?? '';
    return customer.isNotEmpty || table.isNotEmpty;
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
}

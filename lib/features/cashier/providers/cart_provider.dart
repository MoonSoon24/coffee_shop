import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '/features/cashier/models/models.dart';
import '../data/offline_order_queue_repository.dart';

class CartProvider extends ChangeNotifier {
  final OfflineOrderQueueRepository _offlineRepo =
      OfflineOrderQueueRepository();
  final Uuid _uuid = const Uuid();

  final Map<String, CartItem> _items = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  CartProvider() {
    _bootstrapOffline();
  }

  Map<String, CartItem> get items => _items;

  int _pendingOfflineOrderCount = 0;

  int get pendingOfflineOrderCount => _pendingOfflineOrderCount;

  bool get isSyncingOfflineOrders => _isSyncing;

  Future<void> _bootstrapOffline() async {
    await _offlineRepo.init();
    await _refreshOfflineCounters();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasNetwork = !results.contains(ConnectivityResult.none);
      if (hasNetwork) {
        await syncOfflineOrders();
      }
    });
    notifyListeners();
  }

  Future<void> _refreshOfflineCounters() async {
    _pendingOfflineOrderCount = await _offlineRepo.getPendingCount();
  }

  bool _isTransientError(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('temporarily');
  }

  Future<List<Map<String, dynamic>>> getPendingOfflineOrders() async {
    await _offlineRepo.init();
    return _offlineRepo.getPendingOrders();
  }

  Future<int> syncOfflineOrders() async {
    if (_isSyncing) return 0;
    await _offlineRepo.init();

    final pending = await _offlineRepo.getPendingOrders();
    if (pending.isEmpty) {
      await _refreshOfflineCounters();
      notifyListeners();
      return 0;
    }

    _isSyncing = true;
    notifyListeners();

    final supabase = Supabase.instance.client;
    var synced = 0;

    try {
      for (final payload in pending) {
        final localTxnId = payload['local_txn_id']?.toString();
        if (localTxnId == null || localTxnId.isEmpty) {
          continue;
        }

        try {
          await _submitOfflinePayload(supabase, payload);
          await _offlineRepo.removePending(localTxnId);
          synced++;
        } catch (error) {
          if (_isTransientError(error)) {
            break;
          }

          await _offlineRepo.moveToFailed(
            localTxnId: localTxnId,
            payload: payload,
            reason: error.toString(),
          );
          continue;
        }
      }
    } finally {
      _isSyncing = false;
      await _refreshOfflineCounters();
      notifyListeners();
    }

    return synced;
  }

  Future<void> _submitOfflinePayload(
    SupabaseClient supabase,
    Map<String, dynamic> payload,
  ) async {
    final localTxnId = payload['local_txn_id']?.toString() ?? '';
    final order = Map<String, dynamic>.from(payload['order'] as Map);
    final items = (payload['items'] as List<dynamic>)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final existing = await supabase
        .from('orders')
        .select('id')
        .ilike('notes', '%client_txn_id:$localTxnId%')
        .limit(1);
    if (existing is List && existing.isNotEmpty) {
      return;
    }

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await supabase.from('orders').insert(order);
        await supabase.from('order_items').insert(items);
        return;
      } on PostgrestException catch (error) {
        final isDuplicateId =
            error.code == '23505' && error.message.toLowerCase().contains('id');
        final duplicateTxn =
            error.code == '23505' &&
            error.message.toLowerCase().contains('client_txn_id');
        if (duplicateTxn) {
          return;
        }
        if (!isDuplicateId || attempt == 4) rethrow;

        final newOrderId = await _generateDailyUniqueOrderId(supabase);
        order['id'] = newOrderId;
        for (final item in items) {
          item['order_id'] = newOrderId;
        }
      }
    }
  }

  double get totalAmount {
    var total = 0.0;
    _items.forEach((_, item) {
      final lineUnitPrice = item.price + _modifierUnitPrice(item);
      total += lineUnitPrice * item.quantity;
    });
    return total;
  }

  double _modifierUnitPrice(CartItem item) {
    final data = item.modifiersData;
    if (data == null) {
      return 0;
    }

    return data.whereType<Map<String, dynamic>>().fold<double>(0, (
      sum,
      modifier,
    ) {
      final selected =
          modifier['selected_options'] as List<dynamic>? ?? <dynamic>[];
      final selectedTotal = selected
          .whereType<Map<String, dynamic>>()
          .fold<double>(
            0,
            (s, option) => s + ((option['price'] as num?)?.toDouble() ?? 0),
          );
      return sum + selectedTotal;
    });
  }

  double _lineUnitPrice(CartItem item) {
    return item.price + _modifierUnitPrice(item);
  }

  void addItem(
    Product product, {
    required int quantity,
    CartModifiers? modifiers,
    List<dynamic>? modifiersData,
  }) {
    if (quantity <= 0) return;

    final cartLineKey = _buildCartLineKey(product, modifiers, modifiersData);
    if (_items.containsKey(cartLineKey)) {
      final existing = _items[cartLineKey]!;
      _items.update(
        cartLineKey,
        (_) => _toCartItem(
          product,
          quantity: existing.quantity + quantity,
          existingCartId: existing.cartId,
          modifiers: existing.modifiers,
          modifiersData: existing.modifiersData,
        ),
      );
    } else {
      _items.putIfAbsent(
        cartLineKey,
        () => _toCartItem(
          product,
          quantity: quantity,
          modifiers: modifiers,
          modifiersData: modifiersData,
        ),
      );
    }

    notifyListeners();
  }

  void replaceItem({
    required String existingKey,
    required Product product,
    required int quantity,
    CartModifiers? modifiers,
    List<dynamic>? modifiersData,
  }) {
    if (quantity <= 0) return;

    final newKey = _buildCartLineKey(product, modifiers, modifiersData);
    final existing = _items[existingKey];
    _items.remove(existingKey);

    if (_items.containsKey(newKey)) {
      final target = _items[newKey]!;
      _items[newKey] = _toCartItem(
        product,
        quantity: target.quantity + quantity,
        existingCartId: target.cartId,
        modifiers: target.modifiers,
        modifiersData: target.modifiersData,
      );
    } else {
      _items[newKey] = _toCartItem(
        product,
        quantity: quantity,
        existingCartId: existing?.cartId,
        modifiers: modifiers,
        modifiersData: modifiersData,
      );
    }

    notifyListeners();
  }

  void removeItem(String key) {
    _items.remove(key);
    notifyListeners();
  }

  String _buildCartLineKey(
    Product product,
    CartModifiers? modifiers,
    List<dynamic>? modifiersData,
  ) {
    final modifiersPayload =
        modifiers?.toJson() ?? {'modifiers_data': modifiersData ?? <dynamic>[]};

    return '${product.id}::${jsonEncode(modifiersPayload)}';
  }

  CartItem _toCartItem(
    Product product, {
    required int quantity,
    String? existingCartId,
    CartModifiers? modifiers,
    List<dynamic>? modifiersData,
  }) {
    return CartItem(
      id: product.id,
      name: product.name,
      price: product.price,
      category: product.category,
      description: product.description,
      imageUrl: product.imageUrl,
      isAvailable: product.isAvailable,
      isBundle: product.isBundle,
      isRecommended: product.isRecommended,
      productBundles: product.productBundles,
      cartId: existingCartId ?? DateTime.now().toIso8601String(),
      quantity: quantity,
      modifiers: modifiers,
      modifiersData: modifiersData,
    );
  }

  String _datePrefix(DateTime now) {
    final year = (now.year % 100).toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  Future<int> _generateDailyUniqueOrderId(SupabaseClient supabase) async {
    final now = DateTime.now();
    final prefix = _datePrefix(now);
    final prefixValue = int.parse(prefix);
    final minId = prefixValue * 1000;
    final maxId = minId + 999;

    final existingRows = await supabase
        .from('orders')
        .select('id')
        .gte('id', minId)
        .lte('id', maxId);

    final usedIds = existingRows
        .whereType<Map<String, dynamic>>()
        .map((row) => int.tryParse(row['id'].toString()))
        .whereType<int>()
        .toSet();

    if (usedIds.length >= 1000) {
      throw Exception('Daily order id capacity exhausted for $prefix');
    }

    final random = Random();
    for (var i = 0; i < 2000; i++) {
      final suffix = random.nextInt(1000);
      final candidate = minId + suffix;
      if (!usedIds.contains(candidate)) {
        return candidate;
      }
    }

    for (var suffix = 0; suffix < 1000; suffix++) {
      final candidate = minId + suffix;
      if (!usedIds.contains(candidate)) {
        return candidate;
      }
    }

    throw Exception('Unable to generate daily unique order id for $prefix');
  }

  Future<int> updateExistingOrder({
    required int orderId,
    String? customerName,
    String? tableName,
    required String orderType,
    String? paymentMethod,
    num? totalPaymentReceived,
    Map<String, int>? cashNominalBreakdown,
    num? changeAmount,
    String? status,
  }) async {
    final supabase = Supabase.instance.client;
    final normalizedTotal = totalAmount % 1 == 0
        ? totalAmount.toInt()
        : totalAmount;

    await supabase
        .from('orders')
        .update({
          'total_price': normalizedTotal,
          'subtotal': normalizedTotal,
          'discount_total': 0,
          'points_earned': 0,
          'points_used': 0,
          'status': status ?? 'active',
          'type': orderType,
          'payment_method': paymentMethod,
          'total_payment_received': totalPaymentReceived,
          'cash_nominal_breakdown': cashNominalBreakdown,
          'change_amount': changeAmount,
          'customer_name': customerName,
          'notes': (tableName == null || tableName.isEmpty)
              ? null
              : 'Table: $tableName',
        })
        .eq('id', orderId);

    await supabase.from('order_items').delete().eq('order_id', orderId);

    if (_items.isNotEmpty) {
      final orderItems = _items.values.map((item) {
        return {
          'order_id': orderId,
          'product_id': item.id,
          'quantity': item.quantity,
          'price_at_time': item.price,
          'modifiers': item.modifiers?.toJson(),
        };
      }).toList();

      await supabase.from('order_items').insert(orderItems);
    }
    return orderId;
  }

  Future<int> submitOrder({
    String? customerName,
    String? tableName,
    required String orderType,
    String paymentMethod = 'cash',
    num? totalPaymentReceived,
    Map<String, int>? cashNominalBreakdown,
    num? changeAmount,
    String status = 'active',
    int? parentOrderId,
    int? cashierId,
    int? shiftId,
  }) async {
    final supabase = Supabase.instance.client;
    final normalizedTotal = totalAmount % 1 == 0
        ? totalAmount.toInt()
        : totalAmount;
    final localTxnId = _uuid.v4();

    String composeNotes() {
      final tableNote = (tableName == null || tableName.isEmpty)
          ? ''
          : 'Table: $tableName';
      if (tableNote.isEmpty) {
        return 'client_txn_id:$localTxnId';
      }
      return '$tableNote\nclient_txn_id:$localTxnId';
    }

    Map<String, dynamic>? orderPayload;
    List<Map<String, dynamic>> orderItems = <Map<String, dynamic>>[];

    try {
      Map<String, dynamic>? orderResponse;
      for (var attempt = 0; attempt < 5; attempt++) {
        final generatedOrderId = await _generateDailyUniqueOrderId(supabase);
        final payload = {
          'id': generatedOrderId,
          'total_price': normalizedTotal,
          'subtotal': normalizedTotal,
          'discount_total': 0,
          'points_earned': 0,
          'points_used': 0,
          'status': status,
          'type': orderType,
          'order_source': 'cashier',
          'payment_method': paymentMethod,
          'total_payment_received': totalPaymentReceived,
          'cash_nominal_breakdown': cashNominalBreakdown,
          'change_amount': changeAmount,
          'customer_name': customerName,
          'parent_order_id': parentOrderId,
          'cashier_id': cashierId,
          'shift_id': shiftId,
          'notes': composeNotes(),
        };
        orderPayload = Map<String, dynamic>.from(payload);

        try {
          orderResponse = await supabase
              .from('orders')
              .insert(payload)
              .select()
              .single();
          break;
        } on PostgrestException catch (error) {
          final isDuplicateId =
              error.code == '23505' &&
              error.message.toLowerCase().contains('id');
          if (!isDuplicateId || attempt == 4) {
            rethrow;
          }
        }
      }

      if (orderResponse == null) {
        throw Exception('Failed to create order id after retries');
      }

      final orderId = (orderResponse['id'] as num).toInt();

      orderItems = _items.values
          .map((item) {
            return {
              'order_id': orderId,
              'product_id': item.id,
              'quantity': item.quantity,
              'price_at_time': _lineUnitPrice(item),
              'modifiers': item.modifiers?.toJson(),
            };
          })
          .toList(growable: false);

      await supabase.from('order_items').insert(orderItems);

      clearCart();
      return orderId;
    } catch (_) {
      if (orderPayload == null) {
        final localOrderId = DateTime.now().millisecondsSinceEpoch;
        orderPayload = {
          'id': localOrderId,
          'total_price': normalizedTotal,
          'subtotal': normalizedTotal,
          'discount_total': 0,
          'points_earned': 0,
          'points_used': 0,
          'status': status,
          'type': orderType,
          'order_source': 'cashier',
          'payment_method': paymentMethod,
          'total_payment_received': totalPaymentReceived,
          'cash_nominal_breakdown': cashNominalBreakdown,
          'change_amount': changeAmount,
          'customer_name': customerName,
          'parent_order_id': parentOrderId,
          'cashier_id': cashierId,
          'shift_id': shiftId,
          'notes': composeNotes(),
        };
      }

      if (orderItems.isEmpty) {
        final offlineOrderId = orderPayload['id'];
        orderItems = _items.values
            .map((item) {
              return {
                'order_id': offlineOrderId,
                'product_id': item.id,
                'quantity': item.quantity,
                'price_at_time': _lineUnitPrice(item),
                'modifiers': item.modifiers?.toJson(),
              };
            })
            .toList(growable: false);
      }

      await _offlineRepo.enqueue({
        'local_txn_id': localTxnId,
        'queued_at': DateTime.now().toIso8601String(),
        'order': orderPayload,
        'items': orderItems,
      });

      await _refreshOfflineCounters();
      notifyListeners();
      clearCart();
      return -1;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}

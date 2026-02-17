import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => _items;

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

  Future<void> updateExistingOrder({
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
  }

  Future<void> submitOrder({
    String? customerName,
    String? tableName,
    required String orderType,
    String paymentMethod = 'cash',
    num? totalPaymentReceived,
    Map<String, int>? cashNominalBreakdown,
    num? changeAmount,
    String status = 'active',
    int? parentOrderId,
  }) async {
    final supabase = Supabase.instance.client;
    final normalizedTotal = totalAmount % 1 == 0
        ? totalAmount.toInt()
        : totalAmount;
    Map<String, dynamic>? orderResponse;
    for (var attempt = 0; attempt < 5; attempt++) {
      final generatedOrderId = await _generateDailyUniqueOrderId(supabase);
      try {
        orderResponse = await supabase
            .from('orders')
            .insert({
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
              'notes': (tableName == null || tableName.isEmpty)
                  ? null
                  : 'Table: $tableName',
            })
            .select()
            .single();
        break;
      } on PostgrestException catch (error) {
        final isDuplicateId =
            error.code == '23505' && error.message.toLowerCase().contains('id');
        if (!isDuplicateId || attempt == 4) {
          rethrow;
        }
      }
    }

    if (orderResponse == null) {
      throw Exception('Failed to create order id after retries');
    }

    final orderId = orderResponse['id'];

    final List<Map<String, dynamic>> orderItems = _items.values.map((item) {
      return {
        'order_id': orderId,
        'product_id': item.id,
        'quantity': item.quantity,
        'price_at_time': _lineUnitPrice(item),
        'modifiers': item.modifiers?.toJson(),
      };
    }).toList();

    await supabase.from('order_items').insert(orderItems);

    clearCart();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}

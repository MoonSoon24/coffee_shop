import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class CartProvider extends ChangeNotifier {
  final Map<int, CartItem> _items = {};

  Map<int, CartItem> get items => _items;

  double get totalAmount {
    var total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void addItem(Product product) {
    if (_items.containsKey(product.id)) {
      // If item exists, just increase quantity
      _items.update(
        product.id,
        (existing) => CartItem(
          id: existing.id,
          name: existing.name,
          price: existing.price,
          category: existing.category,
          description: existing.description,
          cartId: existing.cartId,
          quantity: existing.quantity + 1,
        ),
      );
    } else {
      // Add new item
      _items.putIfAbsent(
        product.id,
        () => CartItem(
          id: product.id,
          name: product.name,
          price: product.price,
          category: product.category,
          description: product.description,
          cartId: DateTime.now().toString(),
          quantity: 1,
        ),
      );
    }
    notifyListeners(); // Update the UI!
  }

  Future<void> submitOrder() async {
    final supabase = Supabase.instance.client;

    // 1. Create the Order Entry
    final orderResponse = await supabase
        .from('orders')
        .insert({
          'total_amount': totalAmount,
          'status':
              'completed', // In-store orders are usually instantly completed
          'payment_method': 'cash', // Or 'card'
          'type': 'dine_in', // You can add a toggle for this in UI
        })
        .select()
        .single();

    final orderId = orderResponse['id'];

    // 2. Create Order Items
    final List<Map<String, dynamic>> orderItems = _items.values.map((item) {
      return {
        'order_id': orderId,
        'product_id': item.id,
        'quantity': item.quantity,
        'price_at_time': item.price,
      };
    }).toList();

    await supabase.from('order_items').insert(orderItems);

    // 3. Clear Local Cart
    clearCart();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}

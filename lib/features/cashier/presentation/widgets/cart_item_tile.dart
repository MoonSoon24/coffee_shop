part of '../screens/cashier_screen.dart';

extension CartItemTileMethods on _ProductListScreenState {
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
}

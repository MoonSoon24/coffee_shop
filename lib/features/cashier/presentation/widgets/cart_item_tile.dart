part of '../screens/cashier_screen.dart';

extension CartItemTileMethods on _ProductListScreenState {
  String _cartSubtitle(CartItem item) {
    final fromSelections =
        item.modifiers?.selections.values
            .expand((entries) => entries)
            .toList() ??
        <String>[];
    final fromData = (item.modifiersData ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .expand((modifier) {
          final selected =
              modifier['selected_options'] as List<dynamic>? ??
              const <dynamic>[];
          return selected
              .whereType<Map<String, dynamic>>()
              .map((option) => option['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty);
        })
        .toList(growable: false);

    final selected = <String>{
      ...fromSelections,
      ...fromData,
    }.toList(growable: false);
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
    final cachedProducts = await _productCatalogRepository.loadCachedProducts();
    final product = cachedProducts.firstWhere(
      (entry) => entry.id == item.id,
      orElse: () => Product(
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
      ),
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

  List<ProductModifier> _modifiersFromCartItemData(CartItem item) {
    final data = item.modifiersData ?? const <dynamic>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map((modifier) {
          final optionsRaw =
              modifier['selected_options'] as List<dynamic>? ??
              const <dynamic>[];
          final options = optionsRaw
              .whereType<Map<String, dynamic>>()
              .map((option) {
                final name = option['name']?.toString() ?? '';
                return ModifierOption(
                  id: option['id']?.toString() ?? name,
                  name: name,
                  price: (option['price'] as num?)?.toDouble() ?? 0,
                );
              })
              .where((option) => option.name.isNotEmpty)
              .toList(growable: false);

          final modifierName =
              modifier['modifier_name']?.toString() ?? 'Modifier';
          return ProductModifier(
            id: modifier['modifier_id']?.toString() ?? modifierName,
            name: modifierName,
            isRequired: false,
            type: (modifier['type']?.toString() == 'multi')
                ? 'multi'
                : 'single',
            options: options,
          );
        })
        .where((modifier) => modifier.options.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _editCartItem(String key, CartItem item, Product product) async {
    var modifiers = await _fetchProductModifiers(product);
    if (modifiers.isEmpty) {
      modifiers = _modifiersFromCartItemData(item);
    }
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

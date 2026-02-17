part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

extension OnlineOrdersDialogMethods on _ProductListScreenState {
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

  String _onlineDateLabel(dynamic value) {
    DateTime date;
    if (value is DateTime) {
      date = value.toLocal();
    } else if (value is String) {
      date = DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _showOnlineOrdersDialog() async {
    String searchQuery = '';
    String selectedStatus = 'all';
    int? selectedOrderId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 1100,
                height: 680,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _onlineOrdersRepository.allOnlineOrdersStream(),
                  builder: (context, snapshot) {
                    final rawOrders = snapshot.data ?? <Map<String, dynamic>>[];
                    final normalizedSearch = searchQuery.trim().toLowerCase();

                    final filtered = rawOrders
                        .where((order) {
                          final status = (order['status'] ?? '').toString();
                          if (selectedStatus != 'all' &&
                              status != selectedStatus) {
                            return false;
                          }

                          if (normalizedSearch.isEmpty) {
                            return true;
                          }

                          final id = order['id']?.toString() ?? '';
                          final customer = (order['customer_name'] ?? '')
                              .toString()
                              .toLowerCase();
                          final notes = (order['notes'] ?? '')
                              .toString()
                              .toLowerCase();
                          return id.contains(normalizedSearch) ||
                              customer.contains(normalizedSearch) ||
                              notes.contains(normalizedSearch);
                        })
                        .toList(growable: false);

                    if (selectedOrderId != null &&
                        filtered.every((e) => e['id'] != selectedOrderId)) {
                      selectedOrderId = filtered.isEmpty
                          ? null
                          : (filtered.first['id'] as num?)?.toInt();
                    }
                    selectedOrderId ??= filtered.isEmpty
                        ? null
                        : (filtered.first['id'] as num?)?.toInt();

                    final selectedOrder = selectedOrderId == null
                        ? null
                        : filtered.firstWhere(
                            (o) =>
                                (o['id'] as num?)?.toInt() == selectedOrderId,
                            orElse: () => <String, dynamic>{},
                          );

                    final statusCount = <String, int>{
                      'all': rawOrders.length,
                      OrderStatus.pending: 0,
                      OrderStatus.processing: 0,
                      OrderStatus.assigned: 0,
                      OrderStatus.completed: 0,
                      OrderStatus.cancelled: 0,
                    };
                    for (final order in rawOrders) {
                      final status = (order['status'] ?? '').toString();
                      if (statusCount.containsKey(status)) {
                        statusCount[status] = (statusCount[status] ?? 0) + 1;
                      }
                    }

                    Widget statusCard({
                      required String value,
                      required String label,
                      required Color color,
                    }) {
                      final isActive = selectedStatus == value;
                      return Expanded(
                        child: InkWell(
                          onTap: () =>
                              setDialogState(() => selectedStatus = value),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? color.withOpacity(0.14)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive ? color : Colors.blue.shade100,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${statusCount[value] ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  label,
                                  style: TextStyle(color: color, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final grouped = <String, List<Map<String, dynamic>>>{};
                    for (final order in filtered) {
                      final label = _onlineDateLabel(order['created_at']);
                      grouped
                          .putIfAbsent(label, () => <Map<String, dynamic>>[])
                          .add(order);
                    }

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border(
                              bottom: BorderSide(color: Colors.blue.shade100),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.receipt_long,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Pesanan Online',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                onChanged: (value) =>
                                    setDialogState(() => searchQuery = value),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search order id, customer, notes...',
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.blue.shade100,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  statusCard(
                                    value: 'all',
                                    label: 'All',
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  statusCard(
                                    value: OrderStatus.pending,
                                    label: 'Pending',
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  statusCard(
                                    value: OrderStatus.processing,
                                    label: 'Processing',
                                    color: Colors.indigo,
                                  ),
                                  const SizedBox(width: 8),
                                  statusCard(
                                    value: OrderStatus.completed,
                                    label: 'Completed',
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  statusCard(
                                    value: OrderStatus.cancelled,
                                    label: 'Cancelled',
                                    color: Colors.red,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 430,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.blue.shade100,
                                    ),
                                  ),
                                  color: Colors.white,
                                ),
                                child: filtered.isEmpty
                                    ? const Center(
                                        child: Text('No orders found.'),
                                      )
                                    : ListView(
                                        padding: const EdgeInsets.all(12),
                                        children: grouped.entries.expand((
                                          entry,
                                        ) {
                                          final header = Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              '${entry.key}:',
                                              style: TextStyle(
                                                color: Colors.blue.shade700,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          );

                                          final tiles = entry.value.map((
                                            order,
                                          ) {
                                            final orderId = order['id'];
                                            final customer =
                                                order['customer_name'] ??
                                                'Guest';
                                            final total =
                                                (order['total_price'] ??
                                                        order['total_amount'] ??
                                                        0)
                                                    as num;
                                            final status =
                                                (order['status'] ?? '-')
                                                    .toString();
                                            final isSelected =
                                                (orderId as num?)?.toInt() ==
                                                selectedOrderId;

                                            return Card(
                                              color: isSelected
                                                  ? Colors.blue.shade50
                                                  : Colors.white,
                                              surfaceTintColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                  color: isSelected
                                                      ? Colors.blue
                                                      : Colors.blue.shade100,
                                                ),
                                              ),
                                              child: ListTile(
                                                onTap: () => setDialogState(
                                                  () => selectedOrderId =
                                                      (orderId as num?)
                                                          ?.toInt(),
                                                ),
                                                title: Text(
                                                  'Order #$orderId • $customer',
                                                ),
                                                subtitle: Text(
                                                  '${status.toUpperCase()} • ${_formatRupiah(total)}',
                                                ),
                                                trailing: const Icon(
                                                  Icons.chevron_right,
                                                ),
                                              ),
                                            );
                                          }).toList();

                                          return [header, ...tiles];
                                        }).toList(),
                                      ),
                              ),
                              Expanded(
                                child:
                                    selectedOrder == null ||
                                        selectedOrder.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Select an order to see details.',
                                        ),
                                      )
                                    : FutureBuilder<List<_OnlineOrderItem>>(
                                        future: _fetchOrderItems(
                                          (selectedOrder['id'] as num).toInt(),
                                        ),
                                        builder: (context, detailSnapshot) {
                                          final items =
                                              detailSnapshot.data ??
                                              <_OnlineOrderItem>[];
                                          return Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Order #${selectedOrder['id']} • ${selectedOrder['customer_name'] ?? 'Guest'}',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Status: ${(selectedOrder['status'] ?? '-').toString().toUpperCase()}',
                                                  style: TextStyle(
                                                    color: Colors.blue.shade700,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Expanded(
                                                  child:
                                                      detailSnapshot
                                                                  .connectionState ==
                                                              ConnectionState
                                                                  .waiting &&
                                                          items.isEmpty
                                                      ? const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        )
                                                      : ListView.separated(
                                                          itemCount:
                                                              items.length,
                                                          separatorBuilder:
                                                              (_, __) =>
                                                                  const Divider(),
                                                          itemBuilder: (_, index) {
                                                            final item =
                                                                items[index];
                                                            final modifierText =
                                                                _onlineOrderModifiersText(
                                                                  item,
                                                                );
                                                            final itemTotal =
                                                                ((item.product.price +
                                                                            _modifierExtraFromData(
                                                                              item.modifiersData,
                                                                            )) *
                                                                        item.quantity)
                                                                    .toDouble();
                                                            return ListTile(
                                                              title: Text(
                                                                item
                                                                    .product
                                                                    .name,
                                                              ),
                                                              subtitle: Text(
                                                                modifierText
                                                                        .isEmpty
                                                                    ? 'Qty: ${item.quantity}'
                                                                    : 'Qty: ${item.quantity}\n$modifierText',
                                                              ),
                                                              trailing: Text(
                                                                _formatRupiah(
                                                                  itemTotal,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                ),
                                                Row(
                                                  children: [
                                                    OutlinedButton(
                                                      onPressed: () =>
                                                          _showOrderDetailModal(
                                                            selectedOrder,
                                                          ),
                                                      child: const Text(
                                                        'Open detail',
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    TextButton(
                                                      onPressed: () async {
                                                        final updated =
                                                            await _updateOrderStatusIfPending(
                                                              (selectedOrder['id']
                                                                      as num)
                                                                  .toInt(),
                                                              OrderStatus
                                                                  .cancelled,
                                                            );
                                                        if (!context.mounted)
                                                          return;
                                                        if (!updated) {
                                                          _showDropdownSnackbar(
                                                            'Order status changed by another user.',
                                                            isError: true,
                                                          );
                                                        }
                                                      },
                                                      child: const Text(
                                                        'Decline',
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    ElevatedButton(
                                                      onPressed: () async {
                                                        final orderId =
                                                            (selectedOrder['id']
                                                                    as num)
                                                                .toInt();
                                                        final updated =
                                                            await _updateOrderStatusIfPending(
                                                              orderId,
                                                              OrderStatus
                                                                  .processing,
                                                            );
                                                        if (!context.mounted)
                                                          return;
                                                        if (!updated) {
                                                          _showDropdownSnackbar(
                                                            'Order already handled from another app/session.',
                                                            isError: true,
                                                          );
                                                          return;
                                                        }

                                                        final cart = context
                                                            .read<
                                                              CartProvider
                                                            >();
                                                        for (final item
                                                            in items) {
                                                          cart.addItem(
                                                            item.product,
                                                            quantity:
                                                                item.quantity,
                                                            modifiers:
                                                                item.modifiers,
                                                            modifiersData: item
                                                                .modifiersData,
                                                          );
                                                        }
                                                        _showDropdownSnackbar(
                                                          'Order #$orderId accepted.',
                                                        );
                                                      },
                                                      child: const Text(
                                                        'Accept',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
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
            );
          },
        );
      },
    );
  }
}

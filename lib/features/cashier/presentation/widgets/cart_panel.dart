part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

extension CartPanelMethods on _ProductListScreenState {
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

  Widget _buildCartOrderDetailsTab() {
    return InkWell(
      onTap: _showOfflineOrderDetailModal,
      child: Container(
        width: double.infinity,
        color: Colors.blue.shade50,
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

  String _formatRupiah(num amount) {
    return CurrencyFormatters.formatRupiah(amount);
  }
}

part of '../presentation/screens/cashier_screen.dart';

class CashierRepository {
  Stream<List<Map<String, dynamic>>> activeOrdersStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.where((row) => row['status'] == 'active').toList());

  Future<List<Map<String, dynamic>>> fetchOtherActiveOrders({
    int? excludedOrderId,
  }) async {
    final rows = await supabase
        .from('orders')
        .select('id, customer_name, total_price, order_source, type, notes')
        .eq('status', 'active')
        .neq('id', excludedOrderId ?? -1)
        .order('created_at');

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  }
}

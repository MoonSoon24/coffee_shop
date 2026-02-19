part of '../presentation/screens/cashier_screen.dart';

class CashierRepository {
  Stream<List<Map<String, dynamic>>> allOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false),
        );
  }

  Stream<List<Map<String, dynamic>>> activeOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map(
          (rows) => rows
              .where((row) => row['status'] == 'active')
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false),
        );
  }

  Future<List<Map<String, dynamic>>> fetchOtherActiveOrders({
    int? excludedOrderId,
    required int? cashierId,
    required int? shiftId,
  }) async {
    final rows = await supabase
        .from('orders')
        .select(
          'id, customer_name, total_price, order_source, type, notes, cashier_id, shift_id',
        )
        .eq('status', 'active')
        .neq('id', excludedOrderId ?? -1)
        .order('created_at');

    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}

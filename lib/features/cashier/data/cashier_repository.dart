part of '../presentation/screens/cashier_screen.dart';

class CashierRepository {
  Stream<List<Map<String, dynamic>>> allOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    if (cashierId == null) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }

    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .where((row) {
                final rowCashierId = (row['cashier_id'] as num?)?.toInt();
                final rowShiftId = (row['shift_id'] as num?)?.toInt();

                final matchesShift = shiftId == null
                    ? true
                    : rowShiftId == shiftId;
                final fallbackLegacyCashierMatch =
                    shiftId != null &&
                    rowShiftId == null &&
                    rowCashierId == cashierId;
                final matchesCashier = shiftId == null
                    ? rowCashierId == cashierId
                    : true;
                return (matchesShift && matchesCashier) ||
                    fallbackLegacyCashierMatch;
              })
              .toList(growable: false),
        );
  }

  Stream<List<Map<String, dynamic>>> activeOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    if (cashierId == null) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }

    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map(
          (rows) => rows
              .where((row) {
                final rowCashierId = (row['cashier_id'] as num?)?.toInt();
                final rowShiftId = (row['shift_id'] as num?)?.toInt();

                final matchesShift = shiftId == null
                    ? true
                    : rowShiftId == shiftId;
                final fallbackLegacyCashierMatch =
                    shiftId != null &&
                    rowShiftId == null &&
                    rowCashierId == cashierId;
                final matchesCashier = shiftId == null
                    ? rowCashierId == cashierId
                    : true;
                return row['status'] == 'active' &&
                    ((matchesShift && matchesCashier) ||
                        fallbackLegacyCashierMatch);
              })
              .toList(growable: false),
        );
  }

  Future<List<Map<String, dynamic>>> fetchOtherActiveOrders({
    int? excludedOrderId,
    required int? cashierId,
    required int? shiftId,
  }) async {
    if (cashierId == null) {
      return const <Map<String, dynamic>>[];
    }

    final rows = await supabase
        .from('orders')
        .select(
          'id, customer_name, total_price, order_source, type, notes, cashier_id, shift_id',
        )
        .eq('status', 'active')
        .neq('id', excludedOrderId ?? -1)
        .order('created_at');

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((row) {
          final rowCashierId = (row['cashier_id'] as num?)?.toInt();
          final rowShiftId = (row['shift_id'] as num?)?.toInt();
          final matchesShift = shiftId == null ? true : rowShiftId == shiftId;
          final fallbackLegacyCashierMatch =
              shiftId != null &&
              rowShiftId == null &&
              rowCashierId == cashierId;
          final matchesCashier = shiftId == null
              ? rowCashierId == cashierId
              : true;
          return (matchesShift && matchesCashier) || fallbackLegacyCashierMatch;
        })
        .toList(growable: false);
  }
}

part of '../presentation/screens/cashier_screen.dart';

class CashierRepository {
  Stream<List<Map<String, dynamic>>> allOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    return LocalOrderStoreRepository.instance.watchAllOrders();
  }

  Stream<List<Map<String, dynamic>>> activeOrdersStream({
    required int? cashierId,
    required int? shiftId,
  }) {
    return LocalOrderStoreRepository.instance.watchActiveOrders();
  }

  Future<List<Map<String, dynamic>>> fetchOtherActiveOrders({
    int? excludedOrderId,
    required int? cashierId,
    required int? shiftId,
  }) async {
    final rows = await LocalOrderStoreRepository.instance.fetchAllOrders();
    return rows
        .where(
          (row) =>
              row['status'] == 'active' &&
              ((row['id'] as num?)?.toInt() ?? -1) != (excludedOrderId ?? -1),
        )
        .toList(growable: false);
  }
}

part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

class OnlineOrdersRepository {
  Stream<List<Map<String, dynamic>>> pendingOnlineOrdersStream() =>
      LocalOrderStoreRepository.instance.watchAllOrders().map(
        (rows) => rows
            .where(
              (row) =>
                  row['status'] == OrderStatus.pending &&
                  row['order_source'] == 'online',
            )
            .toList(growable: false),
      );

  Stream<List<Map<String, dynamic>>> allOnlineOrdersStream() =>
      LocalOrderStoreRepository.instance.watchAllOrders();
}

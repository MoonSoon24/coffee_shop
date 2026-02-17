part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

class OnlineOrdersRepository {
  Stream<List<Map<String, dynamic>>> pendingOnlineOrdersStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map(
        (rows) => rows
            .where(
              (row) =>
                  row['status'] == OrderStatus.pending &&
                  row['order_source'] == 'online',
            )
            .toList(),
      );

  Stream<List<Map<String, dynamic>>> allOnlineOrdersStream() => supabase
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map(
        (rows) => rows
            .where((row) => row['order_source'] == 'online')
            .toList(growable: false),
      );
}

import 'package:coffee_shop/features/cashier/data/offline_order_queue_repository.dart';
import 'package:coffee_shop/features/cashier/data/offline_shift_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

const String offlineSyncTask = 'offline_sync_task';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != offlineSyncTask) return true;

    try {
      await Supabase.initialize(
        url: 'https://iasodtouoikaeuxkuecy.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlhc29kdG91b2lrYWV1eGt1ZWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0ODYxMzIsImV4cCI6MjA4NjA2MjEzMn0.iqm3zxfy-Xl2a_6GDmTj6io8vJW2B3Sr5SHq_4vjJW4',
      );
      final client = Supabase.instance.client;

      final queue = OfflineOrderQueueRepository();
      await queue.init();
      final pending = await queue.getPendingOrders();
      for (final payload in pending) {
        final localTxnId = payload['local_txn_id']?.toString();
        if (localTxnId == null || localTxnId.isEmpty) continue;

        final order = Map<String, dynamic>.from(payload['order'] as Map);
        final items = (payload['items'] as List<dynamic>)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);

        await client.from('orders').insert(order);
        await client.from('order_items').insert(items);
        await queue.removePending(localTxnId);
      }

      final shiftRepo = OfflineShiftRepository();
      await shiftRepo.init();
      await shiftRepo.syncPendingShifts(client);
    } catch (_) {
      // keep retrying on next schedule.
    }

    return true;
  });
}

class BackgroundSyncService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      backgroundSyncDispatcher,
      isInDebugMode: false,
    );
    await Workmanager().registerPeriodicTask(
      offlineSyncTask,
      offlineSyncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}

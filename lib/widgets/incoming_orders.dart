import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingOrdersStream extends StatelessWidget {
  const IncomingOrdersStream({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to the 'orders' table where status is 'pending'
    final stream = Supabase.instance.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at');

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          // You can return an empty Container or a small badge
          return const SizedBox.shrink();
        }

        final newOrders = snapshot.data!;

        // Show a banner or list of incoming orders
        return Container(
          color: Colors.orange[100],
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications_active, color: Colors.deepOrange),
              const SizedBox(width: 10),
              Text(
                '${newOrders.length} New Online Order(s)!',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              TextButton(
                onPressed: () {
                  // Show dialog with order details
                },
                child: const Text('VIEW'),
              ),
            ],
          ),
        );
      },
    );
  }
}

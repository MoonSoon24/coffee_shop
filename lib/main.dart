import 'dart:async';

import 'package:coffee_shop/app.dart';
import 'package:coffee_shop/core/services/background_sync_service.dart';
import 'package:coffee_shop/features/cashier/providers/cart_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> _signInTerminalIfNeeded() async {
  final client = Supabase.instance.client;
  if (client.auth.currentSession != null) return;

  final terminalEmail = dotenv.env['TERMINAL_EMAIL']?.trim();
  final terminalPassword = dotenv.env['TERMINAL_PASSWORD'];
  if (terminalEmail == null ||
      terminalEmail.isEmpty ||
      terminalPassword == null ||
      terminalPassword.isEmpty) {
    return;
  }

  try {
    await client.auth.signInWithPassword(
      email: terminalEmail,
      password: terminalPassword,
    );
  } catch (_) {
    // Keep app booting; cashier screen will show auth-related message if needed.
  }
}

Future<void> _initSupabaseInBackground() async {
  try {
    await Supabase.initialize(
      url: 'https://iasodtouoikaeuxkuecy.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlhc29kdG91b2lrYWV1eGt1ZWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0ODYxMzIsImV4cCI6MjA4NjA2MjEzMn0.iqm3zxfy-Xl2a_6GDmTj6io8vJW2B3Sr5SHq_4vjJW4',
    ).timeout(const Duration(seconds: 8));

    await _signInTerminalIfNeeded();
  } catch (_) {
    // App continues in local-first mode.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  unawaited(_initSupabaseInBackground());
  unawaited(BackgroundSyncService.initialize());

  runApp(
    ChangeNotifierProvider(
      create: (context) => CartProvider(),
      child: const MyApp(),
    ),
  );
}

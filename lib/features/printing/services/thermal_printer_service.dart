import 'dart:async';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';

class ThermalPrinterService {
  ThermalPrinterService._();
  static final ThermalPrinterService instance = ThermalPrinterService._();

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      final devices = await _printer.getBondedDevices().timeout(
        const Duration(seconds: 8),
      );
      return devices;
    } on TimeoutException {
      throw Exception(
        'Bluetooth scan timeout. Make sure Bluetooth is on, then tap Refresh.',
      );
    } on PlatformException catch (error) {
      throw Exception(
        error.message ?? 'Failed to load paired bluetooth devices.',
      );
    } catch (error) {
      throw Exception('Failed to load paired bluetooth devices: $error');
    }
  }

  Future<bool> get isConnected async {
    try {
      return await _printer.isConnected ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      if (await isConnected) {
        return true;
      }
      await _printer.connect(device).timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await _printer.disconnect();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> printPaymentReceipt({
    required int orderId,
    required List<Map<String, dynamic>> lines,
    required num total,
    required String paymentMethod,
    required num paid,
    required num change,
    String? customerName,
    String? tableName,
  }) async {
    if (!(await isConnected)) {
      throw Exception('Printer not connected');
    }

    await _printer.printNewLine();
    await _printer.printCustom('ULUN POS', 2, 1);
    await _printer.printCustom('ORDER #$orderId', 1, 1);
    await _printer.printCustom(
      DateTime.now().toString().substring(0, 16),
      1,
      1,
    );
    await _printer.printCustom('-------------------------------', 1, 1);

    if (customerName != null && customerName.trim().isNotEmpty) {
      await _printer.printCustom('Customer: $customerName', 1, 0);
    }
    if (tableName != null && tableName.trim().isNotEmpty) {
      await _printer.printCustom('Table: $tableName', 1, 0);
    }

    for (final line in lines) {
      final name = line['name']?.toString() ?? '-';
      final qty = (line['qty'] as num?)?.toInt() ?? 1;
      final subtotal = (line['subtotal'] as num?) ?? 0;
      await _printer.printCustom('$name x$qty', 1, 0);
      await _printer.printCustom(
        '  Rp ${subtotal.toDouble().toStringAsFixed(0)}',
        1,
        2,
      );
    }

    await _printer.printCustom('-------------------------------', 1, 1);
    await _printer.printCustom(
      'Total : Rp ${total.toDouble().toStringAsFixed(0)}',
      1,
      2,
    );
    await _printer.printCustom('Pay   : ${paymentMethod.toUpperCase()}', 1, 2);
    await _printer.printCustom(
      'Paid  : Rp ${paid.toDouble().toStringAsFixed(0)}',
      1,
      2,
    );
    await _printer.printCustom(
      'Change: Rp ${change.toDouble().toStringAsFixed(0)}',
      1,
      2,
    );
    await _printer.printNewLine();
    await _printer.printCustom('Thank You', 1, 1);
    await _printer.printNewLine();
    await _printer.paperCut();
  }

  /// Print a simple test receipt
  Future<void> printTestReceipt({required String printerName}) async {
    if (!(await isConnected)) {
      throw Exception('Printer not connected');
    }

    await _printer.printNewLine();
    await _printer.printCustom('CONNECTED SUCCESS', 2, 1);
    await _printer.printNewLine();
    await _printer.printCustom('Device: $printerName', 1, 0);
    await _printer.printCustom(
      'Date: ${DateTime.now().toString().substring(0, 16)}',
      1,
      0,
    );
    await _printer.printNewLine();
    await _printer.printCustom('--------------------------------', 1, 1);
    await _printer.paperCut();
  }
}

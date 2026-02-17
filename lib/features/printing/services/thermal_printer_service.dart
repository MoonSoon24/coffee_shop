import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';

class ThermalPrinterService {
  // Singleton pattern
  ThermalPrinterService._();
  static final ThermalPrinterService instance = ThermalPrinterService._();

  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  /// Get list of PAIRED devices (bonded in Android Settings)
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await _printer.getBondedDevices();
    } on PlatformException {
      return [];
    }
  }

  /// Check if currently connected
  Future<bool> get isConnected async {
    try {
      return await _printer.isConnected ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Connect to a specific device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      // Check if already connected to avoid errors
      if (await isConnected) {
        return true;
      }
      await _printer.connect(device);
      return true;
    } catch (e) {
      print("Connection Error: $e");
      return false;
    }
  }

  /// Disconnect
  Future<bool> disconnect() async {
    try {
      await _printer.disconnect();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Print a simple test receipt
  Future<void> printTestReceipt({required String printerName}) async {
    if (!(await isConnected)) {
      throw Exception("Printer not connected");
    }

    // Basic formatting commands
    await _printer.printNewLine();
    await _printer.printCustom('CONNECTED SUCCESS', 2, 1); // Size 2, Center
    await _printer.printNewLine();
    await _printer.printCustom('Device: $printerName', 1, 0); // Size 1, Left
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

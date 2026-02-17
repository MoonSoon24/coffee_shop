import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coffee_shop/features/printing/services/thermal_printer_service.dart';

// 1. Updated wrapper function to accept your onNotify callback
Future<void> showPrinterSettingsDialog(
  BuildContext context, {
  required void Function(String message, {bool isError}) onNotify,
}) async {
  await showDialog(
    context: context,
    builder: (context) => PrinterSettingsDialog(onNotify: onNotify),
  );
}

class PrinterSettingsDialog extends StatefulWidget {
  // 2. Pass the callback into the widget
  final void Function(String message, {bool isError}) onNotify;

  const PrinterSettingsDialog({super.key, required this.onNotify});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  final ThermalPrinterService _service = ThermalPrinterService.instance;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isLoading = true;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initPrinter();
  }

  Future<void> _initPrinter() async {
    setState(() => _isLoading = true);

    final devices = await _service.getBondedDevices();
    final connected = await _service.isConnected;
    final prefs = await SharedPreferences.getInstance();
    final savedAddress = prefs.getString('printer_address');

    BluetoothDevice? targetDevice;
    if (savedAddress != null && devices.isNotEmpty) {
      try {
        targetDevice = devices.firstWhere((d) => d.address == savedAddress);
      } catch (_) {
        targetDevice = null;
      }
    }

    if (mounted) {
      setState(() {
        _devices = devices;
        _isConnected = connected;
        _selectedDevice =
            targetDevice ?? (devices.isNotEmpty ? devices.first : null);
        _isLoading = false;
      });
    }
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;

    setState(() => _isLoading = true);

    final success = await _service.connect(_selectedDevice!);

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_address', _selectedDevice!.address ?? "");
      await prefs.setString('printer_name', _selectedDevice!.name ?? "");

      if (mounted) {
        setState(() => _isConnected = true);
        // 3. Use your custom callback here
        widget.onNotify("Printer Connected!");
      }
    } else {
      if (mounted) {
        // 3. Use your custom callback for errors too
        widget.onNotify("Connection Failed", isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleDisconnect() async {
    setState(() => _isLoading = true);
    await _service.disconnect();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
      });
      widget.onNotify("Printer Disconnected");
    }
  }

  Future<void> _handleTestPrint() async {
    try {
      await _service.printTestReceipt(
        printerName: _selectedDevice?.name ?? "Unknown",
      );
      widget.onNotify("Test Print Sent");
    } catch (e) {
      widget.onNotify(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Printer Settings"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devices.isEmpty)
              const Text(
                "No paired devices found.\nPlease pair a printer in Android Settings first.",
              )
            else
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isConnected
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.error,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isConnected
                              ? "Status: Connected"
                              : "Status: Disconnected",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  DropdownButtonFormField<BluetoothDevice>(
                    decoration: const InputDecoration(
                      labelText: "Select Printer",
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedDevice,
                    isExpanded: true,
                    items: _devices.map((device) {
                      return DropdownMenuItem(
                        value: device,
                        child: Text(
                          device.name ?? "Unknown Device",
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (device) {
                      setState(() {
                        _selectedDevice = device;
                      });
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        if (!_isLoading && _devices.isNotEmpty) ...[
          if (_isConnected)
            TextButton.icon(
              onPressed: _handleTestPrint,
              icon: const Icon(Icons.print),
              label: const Text("Test Print"),
            ),

          if (_isConnected)
            TextButton(
              onPressed: _handleDisconnect,
              child: const Text(
                "Disconnect",
                style: TextStyle(color: Colors.red),
              ),
            )
          else
            ElevatedButton(
              onPressed: _handleConnect,
              child: const Text("Connect"),
            ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }
}

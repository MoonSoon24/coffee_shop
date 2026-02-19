part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

extension CashierAppBarMethods on _ProductListScreenState {
  static const String _supabaseUrl = 'https://iasodtouoikaeuxkuecy.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlhc29kdG91b2lrYWV1eGt1ZWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0ODYxMzIsImV4cCI6MjA4NjA2MjEzMn0.iqm3zxfy-Xl2a_6GDmTj6io8vJW2B3Sr5SHq_4vjJW4';
  static const String _cachedShiftIdKey = 'cached_active_shift_id';
  static const String _cachedCashierIdKey = 'cached_active_cashier_id';

  PreferredSizeWidget _buildCashierAppBar() {
    return AppBar(
      title: const Text('Cashier Dashboard'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      actions: [
        if (_activeCashierId != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.person, size: 18),
                label: Text('Cashier #$_activeCashierId'),
              ),
            ),
          ),
        if (_activeShiftId == null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'No open shift',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _onlinePendingOrdersStream,
          builder: (context, snapshot) {
            final pendingOrders = snapshot.data ?? <Map<String, dynamic>>[];
            return IconButton(
              tooltip: 'Notification (online order)',
              onPressed: _showOnlinePendingOrdersDialog,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_active),
                  if (pendingOrders.isNotEmpty)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          pendingOrders.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Consumer<CartProvider>(
          builder: (context, cart, _) {
            if (cart.pendingOfflineOrderCount <= 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  backgroundColor: Colors.orange.shade100,
                  label: Text(
                    '${cart.pendingOfflineOrderCount} unsynced',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'App menu',
          icon: const Icon(Icons.menu),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'cashier', child: Text('Cashier Page')),
            PopupMenuItem(value: 'showorders', child: Text('Show Orders')),
            PopupMenuItem(value: 'shifts', child: Text('Shifts')),
            PopupMenuItem(
              value: 'sync_offline',
              child: Text('Sync offline orders'),
            ),
            PopupMenuItem(value: 'printer', child: Text('Printer settings')),
          ],
          onSelected: (value) async {
            if (value == 'cashier') {
              _showDropdownSnackbar('Cashier page active');
            } else if (value == 'showorders') {
              _showAllOrdersDialog();
            } else if (value == 'shifts') {
              await _showShiftsDialog();
            } else if (value == 'sync_offline') {
              await _syncOfflineOrders();
            } else if (value == 'printer') {
              showPrinterSettingsDialog(
                context,
                onNotify: _showDropdownSnackbar,
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _cacheActiveShiftLocally({
    required int? shiftId,
    required int? cashierId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (shiftId == null || cashierId == null) {
      await prefs.remove(_cachedShiftIdKey);
      await prefs.remove(_cachedCashierIdKey);
      return;
    }
    await prefs.setInt(_cachedShiftIdKey, shiftId);
    await prefs.setInt(_cachedCashierIdKey, cashierId);
  }

  Future<void> _restoreCachedShiftLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final shiftId = prefs.getInt(_cachedShiftIdKey);
    final cashierId = prefs.getInt(_cachedCashierIdKey);
    if (shiftId == null || cashierId == null) return;

    if (!mounted) return;
    setState(() {
      _activeShiftId = shiftId;
      _activeCashierId = cashierId;
    });
    _showDropdownSnackbar(
      'Using cached shift context while offline.',
      isError: true,
    );
  }

  Future<void> _syncOfflineOrders() async {
    final cart = context.read<CartProvider>();
    try {
      final synced = await cart.syncOfflineOrders();
      if (!mounted) return;
      if (synced == 0) {
        _showDropdownSnackbar('No offline orders to sync.');
      } else {
        _showDropdownSnackbar('Synced $synced offline order(s).');
      }
    } catch (e) {
      _showDropdownSnackbar('Failed syncing offline orders: $e', isError: true);
    }
  }

  Future<void> _syncShiftContext() async {
    try {
      final openShift = await supabase
          .from('shifts')
          .select('id, current_cashier_id')
          .eq('status', 'open')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      final shiftId = (openShift?['id'] as num?)?.toInt();
      final cashierId = (openShift?['current_cashier_id'] as num?)?.toInt();
      setState(() {
        _activeShiftId = shiftId;
        _activeCashierId = cashierId;
      });
      await _cacheActiveShiftLocally(shiftId: shiftId, cashierId: cashierId);

      if (_activeShiftId == null || _activeCashierId == null) {
        await _showOpenShiftDialog();
      }
    } catch (_) {
      await _restoreCachedShiftLocally();
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List<Map<String, dynamic>> _normalizeCashierRows(dynamic rows) {
    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _showShiftsDialog() async {
    Map<String, dynamic>? openShift;
    try {
      openShift = await supabase
          .from('shifts')
          .select('id, branch_id, started_at, current_cashier_id')
          .eq('status', 'open')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      await _restoreCachedShiftLocally();
      if (mounted) {
        _showDropdownSnackbar(
          'Offline mode: showing cached shift context.',
          isError: true,
        );
      }
    }

    if (!mounted) return;

    final openShiftId = _asInt(openShift?['id']) ?? _activeShiftId;
    final branchId = (openShift?['branch_id'] ?? '-').toString();
    final currentCashierId =
        _asInt(openShift?['current_cashier_id']) ?? _activeCashierId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shifts'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openShiftId == null
                    ? 'No active shift. Open a shift before making orders.'
                    : 'Active shift #$openShiftId (branch: $branchId).',
              ),
              if (currentCashierId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Current cashier id: $currentCashierId'),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: openShiftId == null
                        ? () async {
                            Navigator.of(dialogContext).pop();
                            await _showOpenShiftDialog(force: true);
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Open Shift'),
                  ),
                  ElevatedButton.icon(
                    onPressed: openShiftId == null
                        ? null
                        : () async {
                            Navigator.of(dialogContext).pop();
                            await _closeShift(openShiftId);
                          },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Close Shift'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await _showAddCashierDialog();
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add Cashier'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOpenShiftDialog({bool force = false}) async {
    if (!mounted) return;
    if (!force && _activeShiftId != null && _activeCashierId != null) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _showDropdownSnackbar(
        'Terminal session not authenticated. Set TERMINAL_EMAIL and TERMINAL_PASSWORD in .env, then restart app.',
        isError: true,
      );
      return;
    }

    final pinController = TextEditingController();
    final branchController = TextEditingController(text: 'main');
    int? selectedCashierId;
    List<Map<String, dynamic>> cashiers = <Map<String, dynamic>>[];

    try {
      final rows = await supabase
          .from('cashier')
          .select('id, name, code')
          .order('name', ascending: true);
      cashiers = _normalizeCashierRows(rows);
    } catch (e) {
      _showDropdownSnackbar('Failed to load cashiers: $e', isError: true);
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: force,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> openShift() async {
              final cashierId = selectedCashierId;
              final pin = pinController.text.trim();
              final branchId = branchController.text.trim();
              if (cashierId == null) {
                _showDropdownSnackbar(
                  'Please select cashier first.',
                  isError: true,
                );
                return;
              }
              if (pin.length != 4) {
                _showDropdownSnackbar('PIN must be 4 digits.', isError: true);
                return;
              }
              if (branchId.isEmpty) {
                _showDropdownSnackbar('Branch id is required.', isError: true);
                return;
              }

              final selectedCashier = cashiers.firstWhere(
                (row) => _asInt(row['id']) == cashierId,
              );

              final validPin =
                  (selectedCashier['code'] ?? '').toString() == pin;
              if (!validPin) {
                _showDropdownSnackbar('Invalid PIN.', isError: true);
                return;
              }

              try {
                final created = await supabase
                    .from('shifts')
                    .insert({
                      'branch_id': branchId,
                      'status': 'open',
                      'current_cashier_id': cashierId,
                      'opened_by': supabase.auth.currentUser?.id,
                    })
                    .select('id, current_cashier_id')
                    .single();

                if (!mounted) return;
                final shiftId = (created['id'] as num?)?.toInt();
                final createdCashierId = (created['current_cashier_id'] as num?)
                    ?.toInt();
                setState(() {
                  _activeShiftId = shiftId;
                  _activeCashierId = createdCashierId;
                });
                await _cacheActiveShiftLocally(
                  shiftId: shiftId,
                  cashierId: createdCashierId,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                _showDropdownSnackbar('Shift opened successfully.');
              } catch (e) {
                _showDropdownSnackbar(
                  'Failed to open shift: $e',
                  isError: true,
                );
              }
            }

            return AlertDialog(
              title: const Text('Open Shift'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedCashierId,
                      isExpanded: true,
                      hint: Text(
                        cashiers.isEmpty
                            ? 'No cashier found (check terminal RLS access)'
                            : 'Select cashier',
                      ),
                      items: cashiers
                          .map(
                            (cashier) => DropdownMenuItem<int>(
                              value: _asInt(cashier['id']),
                              child: Text(
                                (cashier['name'] ?? 'Unknown').toString(),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: cashiers.isEmpty
                          ? null
                          : (value) =>
                                setDialogState(() => selectedCashierId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Cashier PIN',
                      ),
                    ),
                    TextField(
                      controller: branchController,
                      decoration: const InputDecoration(labelText: 'Branch id'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await _showAddCashierDialog();
                          if (!context.mounted) return;
                          final rows = await supabase
                              .from('cashier')
                              .select('id, name, code')
                              .order('name', ascending: true);
                          setDialogState(() {
                            cashiers = _normalizeCashierRows(rows);
                          });
                        },
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add New Staff'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (force)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ElevatedButton(
                  onPressed: cashiers.isEmpty ? null : openShift,
                  child: const Text('Open Shift'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddCashierDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    final adminSupabase = SupabaseClient(_supabaseUrl, _supabaseAnonKey);

    var verified = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Admin verification'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Admin email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Admin password',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final password = passwordController.text;

                if (email.isEmpty || password.isEmpty) {
                  _showDropdownSnackbar(
                    'Admin credentials are required.',
                    isError: true,
                  );
                  return;
                }

                try {
                  await adminSupabase.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );
                  verified = true;
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } catch (e) {
                  _showDropdownSnackbar(
                    'Admin verification failed: $e',
                    isError: true,
                  );
                }
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    if (!verified) {
      return;
    }

    final nameController = TextEditingController();
    final pinController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add cashier'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Cashier name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinController,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cashier PIN (4-digit)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final cashierName = nameController.text.trim();
                final pin = pinController.text.trim();

                if (cashierName.isEmpty) {
                  _showDropdownSnackbar(
                    'Cashier name is required.',
                    isError: true,
                  );
                  return;
                }
                if (pin.length != 4) {
                  _showDropdownSnackbar(
                    'Cashier PIN must be 4 digits.',
                    isError: true,
                  );
                  return;
                }

                try {
                  await adminSupabase.from('cashier').insert({
                    'name': cashierName,
                    'code': pin,
                  });

                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  _showDropdownSnackbar('Cashier added successfully.');
                } catch (e) {
                  _showDropdownSnackbar(
                    'Failed to add cashier: $e',
                    isError: true,
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    await adminSupabase.auth.signOut();
  }

  Future<void> _closeShift(int shiftId) async {
    try {
      await supabase
          .from('shifts')
          .update({
            'status': 'closed',
            'ended_at': DateTime.now().toIso8601String(),
            'closed_by': supabase.auth.currentUser?.id,
          })
          .eq('id', shiftId);

      if (!mounted) return;
      setState(() {
        _activeShiftId = null;
        _activeCashierId = null;
      });
      await _cacheActiveShiftLocally(shiftId: null, cashierId: null);
      _showDropdownSnackbar('Shift closed.');
      await _showOpenShiftDialog();
    } catch (e) {
      _showDropdownSnackbar('Failed to close shift: $e', isError: true);
    }
  }

  void _showDropdownSnackbar(String message, {bool isError = false}) {
    _snackbarAnimationController?.dispose();
    _snackbarOverlayEntry?.remove();

    final overlayState = Overlay.of(context);
    final controller = AnimationController(
      vsync: overlayState,
      duration: const Duration(milliseconds: 2400),
    );

    final slideAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(
          begin: Offset.zero,
          end: const Offset(0, 0.35),
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(controller);

    final opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 25),
    ]).animate(controller);

    final backgroundColor = isError
        ? Colors.red.shade700
        : Colors.blue.shade700;

    _snackbarAnimationController = controller;
    _snackbarOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 16,
        left: 0,
        right: 0,
        child: SafeArea(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return Opacity(
                  opacity: opacityAnimation.value,
                  child: FractionalTranslation(
                    translation: slideAnimation.value,
                    child: child,
                  ),
                );
              },
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(_snackbarOverlayEntry!);
    controller.forward().whenComplete(() {
      _snackbarOverlayEntry?.remove();
      _snackbarOverlayEntry = null;
      if (_snackbarAnimationController == controller) {
        _snackbarAnimationController = null;
      }
      controller.dispose();
    });
  }
}

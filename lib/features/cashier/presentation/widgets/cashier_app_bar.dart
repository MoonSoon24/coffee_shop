part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

extension CashierAppBarMethods on _ProductListScreenState {
  PreferredSizeWidget _buildCashierAppBar() {
    return AppBar(
      title: const Text('Cashier Dashboard'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      actions: [
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
        PopupMenuButton<String>(
          tooltip: 'App menu',
          icon: const Icon(Icons.menu),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'cashier', child: Text('Cashier Page')),
            PopupMenuItem(value: 'showorders', child: Text('Show Orders')),
            PopupMenuItem(value: 'shifts', child: Text('Shifts')),
            PopupMenuItem(value: 'printer', child: Text('Printer settings')),
          ],
          onSelected: (value) async {
            if (value == 'cashier') {
              _showDropdownSnackbar('Cashier page active');
            } else if (value == 'showorders') {
              _showAllOrdersDialog();
            } else if (value == 'shifts') {
              await _showShiftsDialog();
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

  Future<void> _syncShiftContext() async {
    final openShift = await supabase
        .from('shifts')
        .select('id, current_cashier_id')
        .eq('status', 'open')
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (!mounted) {
      return;
    }

    if (openShift == null) {
      setState(() {
        _activeShiftId = null;
        _activeCashierId = null;
      });
      return;
    }

    setState(() {
      _activeShiftId = (openShift['id'] as num?)?.toInt();
      _activeCashierId = (openShift['current_cashier_id'] as num?)?.toInt();
    });
  }

  Future<void> _showShiftsDialog() async {
    final currentUserId = supabase.auth.currentUser?.id;

    Future<Map<String, dynamic>?> loadOpenShift() {
      return supabase
          .from('shifts')
          .select('id, branch_id, started_at, status, current_cashier_id')
          .eq('status', 'open')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
    }

    Future<List<Map<String, dynamic>>> loadCashiers() async {
      final rows = await supabase
          .from('cashier')
          .select('id, name, code, created_at')
          .order('name', ascending: true);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    }

    Future<void> createShift() async {
      await supabase.from('shifts').insert({
        'branch_id': 'main',
        'status': 'open',
        'opened_by': currentUserId,
      });
      await _syncShiftContext();
    }

    Future<void> assignCurrentCashier(int shiftId, int cashierId) async {
      await supabase
          .from('shifts')
          .update({'current_cashier_id': cashierId})
          .eq('id', shiftId);
      await _syncShiftContext();
    }

    Future<void> closeShift(int shiftId) async {
      final verifyController = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close shift verification'),
          content: TextField(
            controller: verifyController,
            decoration: const InputDecoration(
              labelText: "Type 'close shifts' to confirm",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final value = verifyController.text.trim().toLowerCase();
                if (value != 'close shifts') {
                  _showDropdownSnackbar(
                    "Verification failed. Type exactly 'close shifts'.",
                    isError: true,
                  );
                  return;
                }

                await supabase
                    .from('shifts')
                    .update({
                      'status': 'closed',
                      'ended_at': DateTime.now().toIso8601String(),
                      'closed_by': currentUserId,
                    })
                    .eq('id', shiftId);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _syncShiftContext();
                _showDropdownSnackbar('Shift closed.');
              },
              child: const Text('Close shift'),
            ),
          ],
        ),
      );
    }

    Future<void> showAddCashierDialog(VoidCallback onDone) async {
      final adminsRaw = await supabase
          .from('profiles')
          .select('email, full_name')
          .eq('role', 'admin')
          .not('email', 'is', null)
          .order('email', ascending: true);

      final admins = (adminsRaw as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      if (admins.isEmpty) {
        _showDropdownSnackbar(
          'No admin found for verification.',
          isError: true,
        );
        return;
      }

      String localPart(String email) => email.endsWith('@gmail.com')
          ? email.replaceFirst('@gmail.com', '')
          : email;

      final passwordController = TextEditingController();
      String? selectedAdminLocal;

      Future<void> openCashierForm() async {
        final nameController = TextEditingController();
        final codeController = TextEditingController();

        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add cashier'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Cashier name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Cashier code (optional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final code = codeController.text.trim();
                  if (name.isEmpty) {
                    _showDropdownSnackbar(
                      'Cashier name is required.',
                      isError: true,
                    );
                    return;
                  }

                  try {
                    await supabase.from('cashier').insert({
                      'name': name,
                      'code': code.isEmpty ? null : code,
                    });
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    onDone();
                    _showDropdownSnackbar('Cashier added.');
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
          ),
        );
      }

      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateVerify) => AlertDialog(
            title: const Text('Admin verification'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedAdminLocal,
                  hint: const Text('Select admin email'),
                  items: admins
                      .map((admin) => (admin['email'] ?? '').toString())
                      .where((email) => email.isNotEmpty)
                      .map((email) {
                        final lp = localPart(email);
                        final name = admins
                            .firstWhere(
                              (admin) =>
                                  (admin['email'] ?? '').toString() == email,
                              orElse: () => <String, dynamic>{},
                            )['full_name']
                            ?.toString();
                        return DropdownMenuItem<String>(
                          value: lp,
                          child: Text(
                            name == null || name.isEmpty
                                ? '$lp @gmail.com'
                                : '$name ($lp @gmail.com)',
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (value) =>
                      setStateVerify(() => selectedAdminLocal = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Admin password',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final adminLocal = selectedAdminLocal;
                  final password = passwordController.text;
                  if (adminLocal == null || adminLocal.isEmpty) {
                    _showDropdownSnackbar(
                      'Select admin email first.',
                      isError: true,
                    );
                    return;
                  }
                  if (password.isEmpty) {
                    _showDropdownSnackbar(
                      'Admin password is required.',
                      isError: true,
                    );
                    return;
                  }

                  final adminEmail = '$adminLocal@gmail.com';

                  try {
                    const supabaseUrl =
                        'https://iasodtouoikaeuxkuecy.supabase.co';
                    const supabaseAnonKey =
                        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlhc29kdG91b2lrYWV1eGt1ZWN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA0ODYxMzIsImV4cCI6MjA4NjA2MjEzMn0.iqm3zxfy-Xl2a_6GDmTj6io8vJW2B3Sr5SHq_4vjJW4';
                    final verifier = SupabaseClient(
                      supabaseUrl,
                      supabaseAnonKey,
                    );
                    await verifier.auth.signInWithPassword(
                      email: adminEmail,
                      password: password,
                    );
                    await verifier.auth.signOut();

                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    await openCashierForm();
                  } catch (_) {
                    _showDropdownSnackbar(
                      'Admin verification failed.',
                      isError: true,
                    );
                  }
                },
                child: const Text('Verify'),
              ),
            ],
          ),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return FutureBuilder<Map<String, dynamic>?>(
              future: loadOpenShift(),
              builder: (context, shiftSnapshot) {
                final shift = shiftSnapshot.data;
                final shiftId = (shift?['id'] as num?)?.toInt();
                final currentCashierId = (shift?['current_cashier_id'] as num?)
                    ?.toInt();

                return AlertDialog(
                  title: const Text('Shifts'),
                  content: SizedBox(
                    width: 560,
                    child:
                        shiftSnapshot.connectionState == ConnectionState.waiting
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : shiftId == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('No open shift found.'),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    await createShift();
                                    setDialogState(() {});
                                    _showDropdownSnackbar('New shift opened.');
                                  } catch (e) {
                                    _showDropdownSnackbar(
                                      'Failed to open shift: $e',
                                      isError: true,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Open shift'),
                              ),
                            ],
                          )
                        : FutureBuilder<List<Map<String, dynamic>>>(
                            future: loadCashiers(),
                            builder: (context, cashiersSnapshot) {
                              final cashiers =
                                  cashiersSnapshot.data ??
                                  <Map<String, dynamic>>[];
                              final active = cashiers.where(
                                (row) =>
                                    (row['id'] as num?)?.toInt() ==
                                    currentCashierId,
                              );
                              final activeLabel = active.isEmpty
                                  ? 'No current cashier selected.'
                                  : (active.first['name'] ?? 'Unknown cashier')
                                        .toString();

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Open shift #$shiftId'),
                                  const SizedBox(height: 6),
                                  Text('Current cashier: $activeLabel'),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          await showAddCashierDialog(() {
                                            setDialogState(() {});
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.person_add_alt_1,
                                        ),
                                        label: const Text('Add cashier'),
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            await closeShift(shiftId);
                                            setDialogState(() {});
                                          } catch (e) {
                                            _showDropdownSnackbar(
                                              'Failed to close shift: $e',
                                              isError: true,
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.lock_outline),
                                        label: const Text('Close shift'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (cashiersSnapshot.connectionState ==
                                      ConnectionState.waiting)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (cashiers.isEmpty)
                                    const Text(
                                      'No cashier data found. Add cashier first.',
                                    )
                                  else
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 280,
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: cashiers.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final cashier = cashiers[index];
                                          final cashierId =
                                              (cashier['id'] as num?)?.toInt();
                                          final isCurrent =
                                              cashierId == currentCashierId;
                                          final title =
                                              (cashier['name'] ??
                                                      'Unnamed cashier')
                                                  .toString();
                                          final subtitle =
                                              (cashier['code'] ?? '')
                                                  .toString();

                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(title),
                                            subtitle: Text(subtitle),
                                            trailing: isCurrent
                                                ? const Chip(
                                                    label: Text(
                                                      'Current shift',
                                                    ),
                                                  )
                                                : TextButton(
                                                    onPressed: cashierId == null
                                                        ? null
                                                        : () async {
                                                            try {
                                                              await assignCurrentCashier(
                                                                shiftId,
                                                                cashierId,
                                                              );
                                                              setDialogState(
                                                                () {},
                                                              );
                                                              _showDropdownSnackbar(
                                                                'Current cashier assigned.',
                                                              );
                                                            } catch (e) {
                                                              _showDropdownSnackbar(
                                                                'Failed to assign cashier: $e',
                                                                isError: true,
                                                              );
                                                            }
                                                          },
                                                    child: const Text(
                                                      'Set current',
                                                    ),
                                                  ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
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

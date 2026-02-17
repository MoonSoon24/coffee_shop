part of 'package:coffee_shop/features/cashier/presentation/screens/cashier_screen.dart';

extension CashierAppBarMethods on _ProductListScreenState {
  PreferredSizeWidget _buildCashierAppBar() {
    return AppBar(
      title: const Text('Cashier Dashboard'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'App menu',
          icon: const Icon(Icons.apps),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'cashier', child: Text('Cashier Page')),
            PopupMenuItem(value: 'pesanan', child: Text('Pesanan')),
            PopupMenuItem(value: 'printer', child: Text('Printer settings')),
          ],
          onSelected: (value) {
            if (value == 'cashier') {
              _showDropdownSnackbar('Cashier page active');
            } else if (value == 'pesanan') {
              _showOnlineOrdersDialog();
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
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 55),
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

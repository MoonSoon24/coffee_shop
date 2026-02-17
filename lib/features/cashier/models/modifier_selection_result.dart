part of '../presentation/screens/cashier_screen.dart';

class _ModifierSelectionResult {
  final int quantity;
  final CartModifiers? cartModifiers;
  final List<dynamic> modifiersData;

  _ModifierSelectionResult({
    required this.quantity,
    required this.cartModifiers,
    required this.modifiersData,
  });
}

enum WalletTransactionKind { topUp, charge, unknown }

class WalletTransaction {
  final String id;
  final double amount;
  final DateTime createdAt;
  final WalletTransactionKind kind;
  final String? description;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.createdAt,
    required this.kind,
    this.description,
  });
}

class WashSession {
  final String sessionId;
  final int boxNumber;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? runtimeMinutes;
  final int? amountEuro;

  const WashSession({
    required this.sessionId,
    required this.boxNumber,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.runtimeMinutes,
    this.amountEuro,
  });
}

enum BoxState { available, reserved, active, cleaning, outOfService }

extension BoxStateX on BoxState {
  String get label {
    switch (this) {
      case BoxState.available:
        return 'Verfuegbar';
      case BoxState.reserved:
        return 'Reserviert';
      case BoxState.active:
        return 'Aktiv';
      case BoxState.cleaning:
        return 'Reinigung';
      case BoxState.outOfService:
        return 'Ausser Betrieb';
    }
  }
}

class WashBox {
  final int number;
  BoxState state;
  int? remainingMinutes;
  int? remainingSeconds;
  DateTime? sessionStartedAt;
  DateTime? lastBackendUpdateAt;

  WashBox({
    required this.number,
    required this.state,
    this.remainingMinutes,
    this.remainingSeconds,
    this.sessionStartedAt,
    this.lastBackendUpdateAt,
  });
}

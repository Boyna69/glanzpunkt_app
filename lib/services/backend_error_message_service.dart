import 'wash_backend_gateway.dart';

class BackendErrorMessageService {
  const BackendErrorMessageService._();

  static String mapForStartFlow(BackendGatewayException error) {
    final reservePhase = _isOperation(error, 'reserve');
    final activatePhase =
        _isOperation(error, 'activate') ||
        _isOperation(error, 'activate_reward');

    switch (error.code) {
      case BackendErrorCode.invalidSignature:
        return 'QR-Code ungueltig. Bitte Box-QR erneut scannen.';
      case BackendErrorCode.boxUnavailable:
        if (reservePhase) {
          return 'Diese Box wurde gerade belegt. Bitte eine andere Box waehlen.';
        }
        if (activatePhase) {
          return 'Aktivierung nicht moeglich, Box ist nicht mehr verfuegbar. Bitte erneut starten.';
        }
        return 'Die Box wurde in der Zwischenzeit belegt.';
      case BackendErrorCode.boxNotFound:
        return 'Die gewaehlte Box wurde nicht gefunden.';
      case BackendErrorCode.reservationExpired:
        return 'Reservierung abgelaufen. Bitte erneut starten.';
      case BackendErrorCode.invalidAmount:
        return 'Ungueltiger Betrag. Bitte erneut waehlen.';
      case BackendErrorCode.sessionNotActive:
        return 'Es ist keine aktive Session vorhanden.';
      case BackendErrorCode.invalidSessionId:
        return 'Session-ID ungueltig. Bitte Vorgang neu starten.';
      case BackendErrorCode.insufficientBalance:
        return 'Nicht genug Guthaben. Bitte zuerst aufladen.';
      case BackendErrorCode.noRewardAvailable:
        return 'Keine Belohnung verfuegbar. Bitte erst weitere Waeschen sammeln.';
      case BackendErrorCode.unauthorized:
        return 'Sitzung abgelaufen. Bitte neu einloggen.';
      case BackendErrorCode.forbidden:
        return 'Keine Berechtigung fuer diese Aktion.';
      case BackendErrorCode.backendUnavailable:
        return 'Backend aktuell nicht erreichbar. Bitte kurz spaeter erneut versuchen.';
      case BackendErrorCode.unknown:
        return error.message;
    }
  }

  static String mapForBoxDetail(BackendGatewayException error) {
    switch (error.code) {
      case BackendErrorCode.invalidSignature:
        return 'QR-Signatur ungueltig.';
      case BackendErrorCode.boxUnavailable:
        return 'Box ist derzeit nicht verfuegbar.';
      case BackendErrorCode.boxNotFound:
        return 'Box wurde nicht gefunden.';
      case BackendErrorCode.reservationExpired:
        return 'Reservierung ist abgelaufen.';
      case BackendErrorCode.invalidAmount:
        return 'Ungueltiger Betrag.';
      case BackendErrorCode.sessionNotActive:
        return 'Es ist keine aktive Session vorhanden.';
      case BackendErrorCode.invalidSessionId:
        return 'Session-ID ungueltig.';
      case BackendErrorCode.insufficientBalance:
        return 'Nicht genug Guthaben.';
      case BackendErrorCode.noRewardAvailable:
        return 'Keine Belohnung verfuegbar.';
      case BackendErrorCode.unauthorized:
        return 'Sitzung abgelaufen. Bitte neu einloggen.';
      case BackendErrorCode.forbidden:
        return 'Keine Berechtigung fuer diese Aktion.';
      case BackendErrorCode.backendUnavailable:
        return 'Backend aktuell nicht erreichbar.';
      case BackendErrorCode.unknown:
        return error.message;
    }
  }

  static bool _isOperation(BackendGatewayException error, String op) {
    final normalizedOperation = (error.operation ?? '').trim().toLowerCase();
    if (normalizedOperation == op) {
      return true;
    }
    return error.message.toLowerCase().contains(op);
  }
}

import '../models/box.dart';
import '../models/wash_session.dart';

enum BoxIdentificationMethod { qr, manual }

enum BackendErrorCode {
  invalidSignature,
  boxUnavailable,
  boxNotFound,
  reservationExpired,
  invalidAmount,
  sessionNotActive,
  invalidSessionId,
  insufficientBalance,
  noRewardAvailable,
  unauthorized,
  forbidden,
  backendUnavailable,
  unknown,
}

class BackendGatewayException implements Exception {
  final BackendErrorCode code;
  final String message;
  final String? operation;

  const BackendGatewayException({
    required this.code,
    required this.message,
    this.operation,
  });

  @override
  String toString() => message;
}

class ReserveBoxRequest {
  final int boxNumber;
  final int amountEuro;
  final BoxIdentificationMethod identificationMethod;
  final String? boxSignature;

  const ReserveBoxRequest({
    required this.boxNumber,
    required this.amountEuro,
    required this.identificationMethod,
    this.boxSignature,
  });
}

class ReserveBoxResponse {
  final String reservationToken;
  final DateTime reservedUntil;

  const ReserveBoxResponse({
    required this.reservationToken,
    required this.reservedUntil,
  });
}

class ActivateBoxRequest {
  final String reservationToken;

  const ActivateBoxRequest({required this.reservationToken});
}

class ActivateBoxResponse {
  final String sessionId;
  final int runtimeMinutes;

  const ActivateBoxResponse({
    required this.sessionId,
    required this.runtimeMinutes,
  });
}

class BoxStatusResponse {
  final int boxNumber;
  final BoxState state;
  final int? remainingMinutes;
  final int? remainingSeconds;

  const BoxStatusResponse({
    required this.boxNumber,
    required this.state,
    this.remainingMinutes,
    this.remainingSeconds,
  });
}

abstract class WashBackendGateway {
  Future<List<BoxStatusResponse>> listBoxes();

  Future<ReserveBoxResponse> reserveBox(ReserveBoxRequest request);

  Future<ActivateBoxResponse> activateBox(ActivateBoxRequest request);

  Future<ActivateBoxResponse> activateRewardBox(int boxNumber);

  Future<BoxStatusResponse> getBoxStatus(int boxNumber);

  Future<void> cancelReservation(int boxNumber);

  Future<void> stopBoxSession(int boxNumber);

  Future<List<WashSession>> getRecentSessions({int limit = 30});
}

class MockWashBackendGateway implements WashBackendGateway {
  int _sequence = 0;
  final Map<String, _PendingReservation> _pendingReservations = {};
  final Map<int, _ActiveSession> _activeSessionByBoxNumber = {};
  final Map<int, DateTime> _cleaningUntilByBoxNumber = {};
  final List<WashSession> _recentSessions = <WashSession>[];
  static const Duration _cleaningDuration = Duration(minutes: 2);
  static const int _rewardRuntimeMinutes = 10;

  @override
  Future<List<BoxStatusResponse>> listBoxes() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final entries = <BoxStatusResponse>[];
    for (var number = 1; number <= 6; number++) {
      entries.add(await getBoxStatus(number));
    }
    return entries;
  }

  @override
  Future<ReserveBoxResponse> reserveBox(ReserveBoxRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (request.identificationMethod == BoxIdentificationMethod.qr &&
        request.boxSignature == 'invalid') {
      throw const BackendGatewayException(
        code: BackendErrorCode.invalidSignature,
        message: 'QR-Signatur ist ungueltig.',
      );
    }

    _sequence++;
    final token = 'res_${request.boxNumber}_$_sequence';
    _pendingReservations[token] = _PendingReservation(
      boxNumber: request.boxNumber,
      amountEuro: request.amountEuro,
    );

    return ReserveBoxResponse(
      reservationToken: token,
      reservedUntil: DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<ActivateBoxResponse> activateBox(ActivateBoxRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _sequence++;
    final pending = _pendingReservations.remove(request.reservationToken);
    if (pending == null) {
      throw StateError('Ungueltiger Reservierungs-Token');
    }
    final runtimeMinutes = pending.amountEuro * 2;
    _cleaningUntilByBoxNumber.remove(pending.boxNumber);
    final now = DateTime.now();
    final sessionId = 'wash_$_sequence';
    _activeSessionByBoxNumber[pending.boxNumber] = _ActiveSession(
      sessionId: sessionId,
      amountEuro: pending.amountEuro,
      activeUntil: now.add(Duration(minutes: runtimeMinutes)),
      startedAt: now,
      runtimeMinutes: runtimeMinutes,
    );
    _recentSessions.insert(
      0,
      WashSession(
        sessionId: sessionId,
        boxNumber: pending.boxNumber,
        status: 'active',
        startedAt: now,
        runtimeMinutes: runtimeMinutes,
        amountEuro: pending.amountEuro,
      ),
    );
    if (_recentSessions.length > 200) {
      _recentSessions.removeRange(200, _recentSessions.length);
    }

    return ActivateBoxResponse(
      sessionId: sessionId,
      runtimeMinutes: runtimeMinutes,
    );
  }

  @override
  Future<ActivateBoxResponse> activateRewardBox(int boxNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _sequence++;
    _cleaningUntilByBoxNumber.remove(boxNumber);
    final now = DateTime.now();
    final sessionId = 'reward_$_sequence';
    _activeSessionByBoxNumber[boxNumber] = _ActiveSession(
      sessionId: sessionId,
      amountEuro: 0,
      activeUntil: now.add(const Duration(minutes: _rewardRuntimeMinutes)),
      startedAt: now,
      runtimeMinutes: _rewardRuntimeMinutes,
    );
    _recentSessions.insert(
      0,
      WashSession(
        sessionId: sessionId,
        boxNumber: boxNumber,
        status: 'active',
        startedAt: now,
        runtimeMinutes: _rewardRuntimeMinutes,
        amountEuro: 0,
      ),
    );
    if (_recentSessions.length > 200) {
      _recentSessions.removeRange(200, _recentSessions.length);
    }
    return ActivateBoxResponse(
      sessionId: sessionId,
      runtimeMinutes: _rewardRuntimeMinutes,
    );
  }

  @override
  Future<BoxStatusResponse> getBoxStatus(int boxNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final cleaningUntil = _cleaningUntilByBoxNumber[boxNumber];
    if (cleaningUntil != null) {
      final remaining = cleaningUntil.difference(DateTime.now()).inMinutes;
      if (remaining > 0) {
        return BoxStatusResponse(
          boxNumber: boxNumber,
          state: BoxState.cleaning,
          remainingMinutes: remaining,
          remainingSeconds: remaining * 60,
        );
      }
      _cleaningUntilByBoxNumber.remove(boxNumber);
    }

    final activeSession = _activeSessionByBoxNumber[boxNumber];
    if (activeSession == null) {
      return BoxStatusResponse(boxNumber: boxNumber, state: BoxState.available);
    }

    final remaining = activeSession.activeUntil
        .difference(DateTime.now())
        .inMinutes;
    if (remaining <= 0) {
      _activeSessionByBoxNumber.remove(boxNumber);
      _cleaningUntilByBoxNumber[boxNumber] = DateTime.now().add(
        _cleaningDuration,
      );
      _replaceSession(
        activeSession.sessionId,
        (previous) => WashSession(
          sessionId: previous.sessionId,
          boxNumber: previous.boxNumber,
          status: 'completed',
          startedAt: previous.startedAt,
          endedAt: DateTime.now(),
          runtimeMinutes: previous.runtimeMinutes,
          amountEuro: previous.amountEuro,
        ),
      );
      return BoxStatusResponse(
        boxNumber: boxNumber,
        state: BoxState.cleaning,
        remainingMinutes: _cleaningDuration.inMinutes,
        remainingSeconds: _cleaningDuration.inSeconds,
      );
    }

    return BoxStatusResponse(
      boxNumber: boxNumber,
      state: BoxState.active,
      remainingMinutes: remaining,
      remainingSeconds: remaining * 60,
    );
  }

  @override
  Future<void> cancelReservation(int boxNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final staleTokens = _pendingReservations.entries
        .where((entry) => entry.value.boxNumber == boxNumber)
        .map((entry) => entry.key)
        .toList();
    for (final token in staleTokens) {
      _pendingReservations.remove(token);
    }
  }

  @override
  Future<void> stopBoxSession(int boxNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final activeSession = _activeSessionByBoxNumber[boxNumber];
    if (activeSession == null) {
      throw const BackendGatewayException(
        code: BackendErrorCode.sessionNotActive,
        message: 'Keine aktive Session fuer diese Box.',
      );
    }
    _activeSessionByBoxNumber.remove(boxNumber);
    _cleaningUntilByBoxNumber[boxNumber] = DateTime.now().add(
      _cleaningDuration,
    );
    _replaceSession(
      activeSession.sessionId,
      (previous) => WashSession(
        sessionId: previous.sessionId,
        boxNumber: previous.boxNumber,
        status: 'stopped',
        startedAt: previous.startedAt,
        endedAt: DateTime.now(),
        runtimeMinutes: previous.runtimeMinutes,
        amountEuro: previous.amountEuro,
      ),
    );
  }

  @override
  Future<List<WashSession>> getRecentSessions({int limit = 30}) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (_recentSessions.length <= limit) {
      return List<WashSession>.from(_recentSessions);
    }
    return List<WashSession>.from(_recentSessions.take(limit));
  }

  void _replaceSession(
    String sessionId,
    WashSession Function(WashSession previous) update,
  ) {
    for (var i = 0; i < _recentSessions.length; i++) {
      final item = _recentSessions[i];
      if (item.sessionId == sessionId) {
        _recentSessions[i] = update(item);
        return;
      }
    }
  }
}

class _PendingReservation {
  final int boxNumber;
  final int amountEuro;

  const _PendingReservation({
    required this.boxNumber,
    required this.amountEuro,
  });
}

class _ActiveSession {
  final String sessionId;
  final int amountEuro;
  final int runtimeMinutes;
  final DateTime startedAt;
  final DateTime activeUntil;

  const _ActiveSession({
    required this.sessionId,
    required this.amountEuro,
    required this.runtimeMinutes,
    required this.startedAt,
    required this.activeUntil,
  });
}

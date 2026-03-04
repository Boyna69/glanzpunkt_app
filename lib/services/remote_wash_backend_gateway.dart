import '../models/box.dart';
import '../models/wash_session.dart';
import 'backend_http_client.dart';
import 'wash_backend_gateway.dart';

class RemoteWashBackendGateway implements WashBackendGateway {
  final String Function() baseUrlProvider;
  final BackendHttpClient client;
  final String? Function()? jwtProvider;
  final Map<String, _PendingActivation> _pendingActivations =
      <String, _PendingActivation>{};

  RemoteWashBackendGateway({
    required this.baseUrlProvider,
    required this.client,
    this.jwtProvider,
  });

  @override
  Future<List<BoxStatusResponse>> listBoxes() async {
    try {
      final uri = Uri.parse(
        '${baseUrlProvider()}/rest/v1/boxes'
        '?select=id,status,remaining_seconds'
        '&order=id.asc',
      );
      final response = await client.getJson(uri, headers: _authHeaders());
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw BackendGatewayException(
          code: BackendErrorCode.unknown,
          message: 'Boxen laden fehlgeschlagen (HTTP ${response.statusCode})',
        );
      }
      if (_hasUserJwt) {
        try {
          await _rpcPost(
            'expire_active_sessions',
            const <String, dynamic>{},
            'Ablauf-Sync',
            operation: 'expire_active_sessions',
          );
        } catch (_) {
          // Non-blocking best-effort maintenance.
        }
      }
      final items = _asList(response.body);
      final boxes = <BoxStatusResponse>[];
      for (final item in items) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final numberRaw = map['id'];
        final stateRaw = map['status'] as String?;
        if (numberRaw is! num || stateRaw == null) {
          continue;
        }
        final boxNumber = numberRaw.toInt();
        final remainingSecondsRaw = map['remaining_seconds'];
        var parsed = BoxStatusResponse(
          boxNumber: boxNumber,
          state: _parseState(stateRaw),
          remainingMinutes: remainingSecondsRaw is num
              ? (remainingSecondsRaw.toInt() / 60).ceil()
              : null,
          remainingSeconds: remainingSecondsRaw is num
              ? remainingSecondsRaw.toInt()
              : null,
        );

        // Pull the exact runtime state via RPC for authenticated users.
        if (_hasUserJwt) {
          try {
            parsed = await getBoxStatus(boxNumber);
          } catch (_) {
            // Keep readonly table fallback.
          }
        }
        boxes.add(parsed);
      }
      return boxes;
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<ReserveBoxResponse> reserveBox(ReserveBoxRequest request) async {
    try {
      Map<String, dynamic> body;
      try {
        body = await _rpcPost(
          'reserve',
          <String, dynamic>{'box_id': request.boxNumber},
          'Box reservieren',
          operation: 'reserve',
        );
      } on BackendGatewayException catch (e) {
        if (!_isRpcMissing(e)) {
          rethrow;
        }
        body = await _legacyFunctionPost(
          'reserve',
          <String, dynamic>{
            'boxNumber': request.boxNumber,
            'amountEuro': request.amountEuro,
            'identificationMethod': request.identificationMethod.name,
            if (request.boxSignature != null &&
                request.boxSignature!.isNotEmpty)
              'boxSignature': request.boxSignature,
          },
          'Box reservieren',
          operation: 'reserve',
        );
      }
      final reservationToken =
          body['reservationToken'] as String? ??
          body['reservation_token'] as String? ??
          'res_${request.boxNumber}_${DateTime.now().microsecondsSinceEpoch}';
      _pendingActivations[reservationToken] = _PendingActivation(
        boxNumber: request.boxNumber,
        amountEuro: request.amountEuro,
      );

      final reservedUntilRaw =
          body['reservedUntil'] as String? ?? body['reserved_until'] as String?;
      final reservedUntil = reservedUntilRaw == null
          ? DateTime.now().add(const Duration(minutes: 2))
          : DateTime.parse(reservedUntilRaw);

      return ReserveBoxResponse(
        reservationToken: reservationToken,
        reservedUntil: reservedUntil,
      );
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<ActivateBoxResponse> activateBox(ActivateBoxRequest request) async {
    _PendingActivation? pending;
    try {
      pending = _pendingActivations[request.reservationToken];
      if (pending == null) {
        throw StateError('Ungueltiger Reservierungs-Token');
      }

      Map<String, dynamic> body;
      try {
        body = await _rpcPost(
          'activate',
          <String, dynamic>{
            'box_id': pending.boxNumber,
            'amount': pending.amountEuro,
          },
          'Box aktivieren',
          operation: 'activate',
        );
      } on BackendGatewayException catch (e) {
        if (!_isRpcMissing(e)) {
          rethrow;
        }
        body = await _legacyFunctionPost(
          'activate',
          <String, dynamic>{'reservationToken': request.reservationToken},
          'Box aktivieren',
          operation: 'activate',
        );
      }

      final rawSessionId =
          body['sessionId'] ?? body['session_id'] ?? body['id'];
      final sessionId = rawSessionId?.toString();
      final runtimeRaw =
          body['runtimeMinutes'] ??
          body['runtime_minutes'] ??
          body['remainingMinutes'] ??
          body['remaining_minutes'] ??
          body['remainingSeconds'] ??
          body['remaining_seconds'];

      final runtimeMinutes = runtimeRaw is num
          ? (runtimeRaw.toInt() / 60).ceil()
          : null;
      if (sessionId == null || runtimeMinutes == null) {
        throw StateError('Ungueltige Activate-Response vom Backend');
      }

      _pendingActivations.remove(request.reservationToken);
      return ActivateBoxResponse(
        sessionId: sessionId,
        runtimeMinutes: runtimeMinutes,
      );
    } on BackendGatewayException catch (e) {
      if (pending != null &&
          e.code != BackendErrorCode.unknown &&
          e.code != BackendErrorCode.sessionNotActive) {
        await _bestEffortCancelReservation(pending.boxNumber);
        _pendingActivations.remove(request.reservationToken);
      }
      rethrow;
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<ActivateBoxResponse> activateRewardBox(int boxNumber) async {
    try {
      final body = await _rpcPost(
        'activate_reward',
        <String, dynamic>{'box_id': boxNumber},
        'Reward-Session aktivieren',
        operation: 'activate_reward',
      );

      final rawSessionId =
          body['sessionId'] ?? body['session_id'] ?? body['id'];
      final sessionId = rawSessionId?.toString();
      final runtimeRaw =
          body['runtimeMinutes'] ??
          body['runtime_minutes'] ??
          body['remainingMinutes'] ??
          body['remaining_minutes'] ??
          body['remainingSeconds'] ??
          body['remaining_seconds'];
      final runtimeMinutes = runtimeRaw is num
          ? (runtimeRaw.toInt() / 60).ceil()
          : null;
      if (sessionId == null || runtimeMinutes == null) {
        throw StateError('Ungueltige Reward-Response vom Backend');
      }
      return ActivateBoxResponse(
        sessionId: sessionId,
        runtimeMinutes: runtimeMinutes,
      );
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<BoxStatusResponse> getBoxStatus(int boxNumber) async {
    try {
      Map<String, dynamic> body;
      try {
        body = await _rpcPost(
          'status',
          <String, dynamic>{'box_id': boxNumber},
          'Box-Status laden',
          operation: 'status',
        );
      } on BackendGatewayException catch (e) {
        if (!_isRpcMissing(e)) {
          rethrow;
        }
        body = await _legacyFunctionPost(
          'status',
          <String, dynamic>{'boxNumber': boxNumber},
          'Box-Status laden',
          operation: 'status',
        );
      }

      final stateRaw = body['state'] as String? ?? body['status'] as String?;
      final state = _parseState(stateRaw);
      final remainingRaw =
          body['remainingSeconds'] ??
          body['remaining_seconds'] ??
          body['remainingMinutes'] ??
          body['remaining_minutes'];
      final remainingSeconds = remainingRaw is num
          ? remainingRaw.toInt()
          : null;
      final remainingMinutes = remainingRaw is num
          ? (remainingRaw.toInt() / 60).ceil()
          : null;

      return BoxStatusResponse(
        boxNumber: boxNumber,
        state: state,
        remainingMinutes: remainingMinutes,
        remainingSeconds: remainingSeconds,
      );
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<void> cancelReservation(int boxNumber) async {
    try {
      try {
        await _rpcPost(
          'cancel_reservation',
          <String, dynamic>{'box_id': boxNumber},
          'Reservierung freigeben',
          operation: 'cancel_reservation',
        );
      } on BackendGatewayException catch (e) {
        if (_isRpcMissing(e)) {
          await _bestEffortStatusRefresh(boxNumber);
          return;
        }
        rethrow;
      }
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<void> stopBoxSession(int boxNumber) async {
    try {
      final activeSessionId = await _findActiveSessionId(boxNumber);
      if (activeSessionId == null) {
        throw const BackendGatewayException(
          code: BackendErrorCode.sessionNotActive,
          message: 'Es gibt keine aktive Session zum Stoppen.',
        );
      }
      try {
        await _rpcPost(
          'stop',
          <String, dynamic>{'session_id': activeSessionId},
          'Session stoppen',
          operation: 'stop',
        );
      } on BackendGatewayException catch (e) {
        if (!_isRpcMissing(e)) {
          rethrow;
        }
        await _legacyFunctionPost(
          'stop',
          <String, dynamic>{'boxNumber': boxNumber},
          'Session stoppen',
          operation: 'stop',
        );
      }
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  @override
  Future<List<WashSession>> getRecentSessions({int limit = 30}) async {
    try {
      final items = await _getRecentSessionsFromPostgrest(limit);
      final sessions = <WashSession>[];
      for (final item in items) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final idRaw = map['id'];
        final boxIdRaw = map['box_id'];
        final startedAtRaw = map['started_at'];
        if (idRaw == null || boxIdRaw is! num || startedAtRaw is! String) {
          continue;
        }
        final startedAt = DateTime.tryParse(startedAtRaw);
        if (startedAt == null) {
          continue;
        }
        final sessionId = idRaw.toString();
        final boxNumber = boxIdRaw.toInt();
        final endedAtRaw = map['ends_at'];
        final endedAt = endedAtRaw is String
            ? DateTime.tryParse(endedAtRaw)
            : null;
        final amountRaw = map['amount'];
        final amountEuro = amountRaw is num ? amountRaw.toInt() : null;
        sessions.add(
          WashSession(
            sessionId: sessionId,
            boxNumber: boxNumber,
            status: endedAt == null ? 'active' : 'completed',
            startedAt: startedAt,
            endedAt: endedAt,
            amountEuro: amountEuro,
          ),
        );
      }
      sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return sessions;
    } on BackendHttpException catch (e) {
      throw _mapHttpException(e);
    }
  }

  Future<List> _getRecentSessionsFromPostgrest(int limit) async {
    final uri = Uri.parse(
      '${baseUrlProvider()}/rest/v1/wash_sessions'
      '?select=id,user_id,box_id,amount,started_at,ends_at'
      '&order=started_at.desc'
      '&limit=$limit',
    );
    final response = await client.getJson(uri, headers: _authHeaders());
    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body is Map
          ? Map<String, dynamic>.from(response.body as Map)
          : <String, dynamic>{};
      _assertOk(response.statusCode, body, 'Session-Historie laden');
    }
    return _asList(response.body);
  }

  Future<Map<String, dynamic>> _rpcPost(
    String fn,
    Map<String, dynamic> payload,
    String action, {
    String? operation,
  }) async {
    final uri = Uri.parse('${baseUrlProvider()}/rest/v1/rpc/$fn');
    final response = await client.postJson(
      uri,
      payload,
      headers: _authHeaders(),
    );
    final body = _asMap(response.body);
    _assertOk(response.statusCode, body, action, operation: operation);
    return body;
  }

  Future<Map<String, dynamic>> _legacyFunctionPost(
    String fn,
    Map<String, dynamic> payload,
    String action, {
    String? operation,
  }) async {
    final uri = Uri.parse('${baseUrlProvider()}/functions/v1/$fn');
    final response = await client.postJson(
      uri,
      payload,
      headers: _authHeaders(),
    );
    final body = _asMap(response.body);
    _assertOk(response.statusCode, body, action, operation: operation);
    return body;
  }

  Future<String?> _findActiveSessionId(int boxNumber) async {
    final uri = Uri.parse(
      '${baseUrlProvider()}/rest/v1/wash_sessions'
      '?select=id'
      '&box_id=eq.$boxNumber'
      '&ends_at=is.null'
      '&order=started_at.desc'
      '&limit=1',
    );
    final response = await client.getJson(uri, headers: _authHeaders());
    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body is Map
          ? Map<String, dynamic>.from(response.body as Map)
          : <String, dynamic>{};
      _assertOk(response.statusCode, body, 'Aktive Session laden');
    }
    final items = _asList(response.body);
    if (items.isEmpty || items.first is! Map) {
      return null;
    }
    final item = Map<String, dynamic>.from(items.first as Map);
    final idRaw = item['id'];
    return idRaw?.toString();
  }

  bool get _hasUserJwt {
    final jwt = jwtProvider?.call();
    return jwt != null && jwt.isNotEmpty;
  }

  bool _isRpcMissing(BackendGatewayException error) {
    return error.message.contains('Could not find the function public.') ||
        error.message.contains('in the schema cache');
  }

  Future<void> _bestEffortCancelReservation(int boxNumber) async {
    try {
      await cancelReservation(boxNumber);
    } catch (_) {
      // No-op: cleanup is best-effort on client side.
    }
  }

  Future<void> _bestEffortStatusRefresh(int boxNumber) async {
    try {
      await _rpcPost(
        'status',
        <String, dynamic>{'box_id': boxNumber},
        'Status',
        operation: 'status',
      );
    } catch (_) {
      // Ignore, optional fallback only.
    }
  }

  Map<String, String> _authHeaders() {
    final jwt = jwtProvider?.call();
    if (jwt == null || jwt.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{'Authorization': 'Bearer $jwt'};
  }

  Map<String, dynamic> _asMap(Object? body) {
    if (body is Map<String, dynamic>) {
      return body;
    }
    if (body is Map) {
      return Map<String, dynamic>.from(body);
    }
    throw const BackendHttpException(
      kind: BackendHttpErrorKind.invalidResponse,
      message: 'API-Response ist kein JSON-Objekt.',
    );
  }

  List _asList(Object? body) {
    if (body is List) {
      return body;
    }
    throw const BackendHttpException(
      kind: BackendHttpErrorKind.invalidResponse,
      message: 'API-Response ist kein JSON-Array.',
    );
  }

  void _assertOk(
    int statusCode,
    Map<String, dynamic> body,
    String action, {
    String? operation,
  }) {
    if (statusCode < 200 || statusCode > 299) {
      final rawCode = body['code']?.toString();
      final message =
          body['message'] as String? ??
          body['msg'] as String? ??
          body['error_description'] as String? ??
          body['error'] as String? ??
          '$action fehlgeschlagen';
      var code = _parseBackendErrorCode(
        rawCode,
        message,
        statusCode: statusCode,
      );
      if (code == BackendErrorCode.unknown && statusCode >= 500) {
        code = BackendErrorCode.backendUnavailable;
      }
      throw BackendGatewayException(
        code: code,
        message: '$action: $message (HTTP $statusCode)',
        operation: operation,
      );
    }
  }

  BackendErrorCode _parseBackendErrorCode(
    String? rawCode,
    String message, {
    required int statusCode,
  }) {
    final code = (rawCode ?? '').trim().toLowerCase();
    final msg = message.trim().toLowerCase();

    bool match(String needle) => code == needle || msg.contains(needle);

    if (statusCode == 401) {
      return BackendErrorCode.unauthorized;
    }
    if (statusCode == 403) {
      return BackendErrorCode.forbidden;
    }
    if (statusCode == 503) {
      return BackendErrorCode.backendUnavailable;
    }
    if (match('42501') || match('permission denied') || match('forbidden')) {
      return BackendErrorCode.forbidden;
    }
    if (match('unauthorized') || match('jwt')) {
      return BackendErrorCode.unauthorized;
    }
    if (match('invalid_signature')) {
      return BackendErrorCode.invalidSignature;
    }
    if (match('box_unavailable')) {
      return BackendErrorCode.boxUnavailable;
    }
    if (match('box_not_found')) {
      return BackendErrorCode.boxNotFound;
    }
    if (match('reservation_expired')) {
      return BackendErrorCode.reservationExpired;
    }
    if (match('invalid_amount')) {
      return BackendErrorCode.invalidAmount;
    }
    if (match('session_not_active')) {
      return BackendErrorCode.sessionNotActive;
    }
    if (match('invalid_session_id')) {
      return BackendErrorCode.invalidSessionId;
    }
    if (match('insufficient_balance')) {
      return BackendErrorCode.insufficientBalance;
    }
    if (match('no_reward_available')) {
      return BackendErrorCode.noRewardAvailable;
    }
    if (match('timeout') || match('network') || match('unavailable')) {
      return BackendErrorCode.backendUnavailable;
    }
    return BackendErrorCode.unknown;
  }

  BoxState _parseState(String? raw) {
    if (raw == null) {
      throw StateError('Box-Status ohne state');
    }

    final normalized = raw.trim();
    if (normalized == 'out_of_service') {
      return BoxState.outOfService;
    }
    if (normalized == 'occupied') {
      return BoxState.active;
    }
    for (final value in BoxState.values) {
      if (value.name == normalized) {
        return value;
      }
    }
    throw StateError('Unbekannter state vom Backend: $raw');
  }

  BackendGatewayException _mapHttpException(BackendHttpException e) {
    switch (e.kind) {
      case BackendHttpErrorKind.timeout:
        return const BackendGatewayException(
          code: BackendErrorCode.backendUnavailable,
          message: 'Backend-Timeout. Bitte erneut versuchen.',
        );
      case BackendHttpErrorKind.network:
        return const BackendGatewayException(
          code: BackendErrorCode.backendUnavailable,
          message: 'Netzwerkfehler. Bitte Internetverbindung pruefen.',
        );
      case BackendHttpErrorKind.invalidResponse:
        return const BackendGatewayException(
          code: BackendErrorCode.unknown,
          message: 'Ungueltige Backend-Antwort erhalten.',
        );
    }
  }
}

class _PendingActivation {
  final int boxNumber;
  final int amountEuro;

  const _PendingActivation({required this.boxNumber, required this.amountEuro});
}

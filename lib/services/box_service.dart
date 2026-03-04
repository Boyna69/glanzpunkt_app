import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/box.dart';
import '../models/wash_session.dart';
import 'analytics_service.dart';
import 'wash_backend_gateway.dart';

enum PaymentStatus { idle, pending, success, failed }

typedef PaymentStatusCallback = void Function(PaymentStatus status);

class BoxTimelineEvent {
  final int boxNumber;
  final DateTime timestamp;
  final String title;
  final String? details;

  const BoxTimelineEvent({
    required this.boxNumber,
    required this.timestamp,
    required this.title,
    this.details,
  });
}

class BoxSyncIssue {
  final DateTime timestamp;
  final String source;
  final String message;
  final int? boxNumber;

  const BoxSyncIssue({
    required this.timestamp,
    required this.source,
    required this.message,
    this.boxNumber,
  });
}

class BoxService extends ChangeNotifier {
  static const String _prefLastBoxNumber = 'wash.last_box_number';
  static const String _prefLastAmount = 'wash.last_amount';
  static const String _prefLastIdentification = 'wash.last_identification';
  static const String _prefTimeline = 'wash.timeline_v1';
  static const Duration _timelineRetention = Duration(days: 7);
  static const int _maxTimelineEventsPerBox = 30;
  static const int _maxSyncIssueEvents = 40;
  static const Duration _cleaningDuration = Duration(minutes: 2);
  static const Duration _realtimeFreshness = Duration(seconds: 30);
  static const int rewardRuntimeMinutes = 10;

  final WashBackendGateway _backend;
  final AnalyticsService _analytics;
  final Stream<BoxStatusResponse>? _realtimeUpdates;
  static const Duration _syncInterval = Duration(seconds: 5);

  final List<WashBox> _boxes = [
    WashBox(number: 1, state: BoxState.available),
    WashBox(number: 2, state: BoxState.active, remainingMinutes: 3),
    WashBox(number: 3, state: BoxState.cleaning, remainingMinutes: 2),
    WashBox(number: 4, state: BoxState.available),
    WashBox(number: 5, state: BoxState.active, remainingMinutes: 7),
    WashBox(number: 6, state: BoxState.available),
  ];

  List<WashBox> get boxes => _boxes;
  List<WashBox> get selectableBoxes =>
      _boxes.where((box) => box.state == BoxState.available).toList();
  int get totalBoxCount => _boxes.length;
  int get availableBoxCount =>
      _boxes.where((box) => box.state == BoxState.available).length;
  int get activeBoxCount =>
      _boxes.where((box) => box.state == BoxState.active).length;
  int get cleaningBoxCount =>
      _boxes.where((box) => box.state == BoxState.cleaning).length;
  int get occupancyPercent {
    if (_boxes.isEmpty) {
      return 0;
    }
    return ((activeBoxCount / _boxes.length) * 100).round();
  }

  Timer? _timer;
  Timer? _syncTimer;
  StreamSubscription<BoxStatusResponse>? _realtimeSubscription;
  bool _isDisposed = false;
  bool _isSyncingCatalog = false;
  DateTime? _lastSuccessfulSyncAt;
  String? _lastSyncErrorMessage;
  DateTime? _lastRealtimeEventAt;
  String? _lastRealtimeErrorMessage;
  DateTime? _lastHistorySyncAt;
  String? _lastHistorySyncErrorMessage;
  final Map<int, List<BoxTimelineEvent>> _timelineByBoxNumber = {};
  final List<BoxSyncIssue> _syncIssues = <BoxSyncIssue>[];
  List<WashSession> _backendRecentSessions = const <WashSession>[];
  int? _lastSelectedBoxNumber;
  int? _lastSelectedAmountEuro;
  BoxIdentificationMethod _lastIdentificationMethod =
      BoxIdentificationMethod.manual;
  bool _startSelectionTouched = false;

  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastSyncErrorMessage => _lastSyncErrorMessage;
  bool get hasRealtimeStream => _realtimeUpdates != null;
  DateTime? get lastRealtimeEventAt => _lastRealtimeEventAt;
  String? get lastRealtimeErrorMessage => _lastRealtimeErrorMessage;
  bool get isRealtimeLive {
    if (!hasRealtimeStream || _lastRealtimeErrorMessage != null) {
      return false;
    }
    final eventAt = _lastRealtimeEventAt;
    if (eventAt == null) {
      return false;
    }
    return DateTime.now().difference(eventAt) <= _realtimeFreshness;
  }

  DateTime? get lastHistorySyncAt => _lastHistorySyncAt;
  String? get lastHistorySyncErrorMessage => _lastHistorySyncErrorMessage;
  List<WashSession> get backendRecentSessions =>
      List<WashSession>.unmodifiable(_backendRecentSessions);
  List<BoxSyncIssue> recentSyncIssues({int limit = 6}) {
    if (_syncIssues.length <= limit) {
      return List<BoxSyncIssue>.unmodifiable(_syncIssues);
    }
    return List<BoxSyncIssue>.unmodifiable(_syncIssues.take(limit));
  }

  bool get isSyncInProgress => _isSyncingCatalog;
  int? get lastSelectedBoxNumber => _lastSelectedBoxNumber;
  int? get lastSelectedAmountEuro => _lastSelectedAmountEuro;
  BoxIdentificationMethod get lastIdentificationMethod =>
      _lastIdentificationMethod;
  List<BoxTimelineEvent> timelineForBox(int boxNumber) {
    final events =
        _timelineByBoxNumber[boxNumber] ?? const <BoxTimelineEvent>[];
    return List<BoxTimelineEvent>.unmodifiable(events);
  }

  List<BoxTimelineEvent> recentTimelineEvents({int limit = 3}) {
    final events = _timelineByBoxNumber.values.expand((list) => list).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (events.length <= limit) {
      return List<BoxTimelineEvent>.unmodifiable(events);
    }
    return List<BoxTimelineEvent>.unmodifiable(events.take(limit));
  }

  List<BoxTimelineEvent> allTimelineEvents() {
    final events = _timelineByBoxNumber.values.expand((list) => list).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List<BoxTimelineEvent>.unmodifiable(events);
  }

  BoxService({
    WashBackendGateway? backend,
    AnalyticsService? analytics,
    Stream<BoxStatusResponse>? realtimeUpdates,
  }) : _realtimeUpdates = realtimeUpdates,
       _backend = backend ?? MockWashBackendGateway(),
       _analytics = analytics ?? AnalyticsService() {
    _restorePersistedState();
    _startTimer();
    _startSyncTimer();
    _startRealtimeUpdatesListener();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimers();
    });
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _runPeriodicBackendSync();
    });
  }

  Future<void> _runPeriodicBackendSync() async {
    await _syncBoxCatalog();
  }

  void _startRealtimeUpdatesListener() {
    final updates = _realtimeUpdates;
    if (updates == null) {
      return;
    }
    _realtimeSubscription = updates.listen(
      _applyRealtimeStatusUpdate,
      onError: (Object error) {
        _lastSyncErrorMessage = '$error';
        _lastRealtimeErrorMessage = '$error';
        _recordSyncIssue(source: 'realtime', message: '$error');
        _notifyListenersSafely();
      },
    );
  }

  void _applyRealtimeStatusUpdate(BoxStatusResponse status) {
    final box = getBoxByNumber(status.boxNumber);
    if (box == null) {
      return;
    }
    final previousState = box.state;
    final previousSeconds = box.remainingSeconds;

    _lastRealtimeEventAt = DateTime.now();
    _lastRealtimeErrorMessage = null;

    box.state = status.state;
    box.remainingMinutes = status.remainingMinutes;
    box.remainingSeconds =
        status.remainingSeconds ??
        (status.remainingMinutes == null
            ? null
            : status.remainingMinutes! * 60);
    box.lastBackendUpdateAt = DateTime.now();
    if (status.state != BoxState.active) {
      box.sessionStartedAt = null;
    }

    if (previousState != status.state) {
      _addTimelineEvent(
        status.boxNumber,
        title: 'Realtime-Update',
        details: '${previousState.label} -> ${status.state.label}',
      );
    }

    _lastSuccessfulSyncAt = DateTime.now();
    _lastSyncErrorMessage = null;

    if (previousState != status.state ||
        previousSeconds != box.remainingSeconds) {
      _notifyListenersSafely();
    }
  }

  void _updateTimers() {
    bool changed = false;

    for (var box in _boxes) {
      if (box.state == BoxState.active || box.state == BoxState.cleaning) {
        if (_tickDown(box)) {
          changed = true;
        }
        if (box.state == BoxState.cleaning && box.remainingMinutes == 0) {
          box.state = BoxState.available;
          box.remainingMinutes = null;
          box.remainingSeconds = null;
          _addTimelineEvent(box.number, title: 'Reinigung beendet');
          changed = true;
        }
      }
    }

    if (changed) {
      _notifyListenersSafely();
    }
  }

  bool _tickDown(WashBox box) {
    final remainingSeconds = box.remainingSeconds;
    if (remainingSeconds != null) {
      if (remainingSeconds <= 0) {
        box.remainingSeconds = 0;
        box.remainingMinutes = 0;
        return false;
      }
      final nextSeconds = remainingSeconds - 1;
      box.remainingSeconds = nextSeconds;
      box.remainingMinutes = (nextSeconds / 60).ceil();
      return true;
    }
    final remaining = box.remainingMinutes;
    if (remaining == null || remaining <= 0) {
      return false;
    }
    box.remainingMinutes = remaining - 1;
    box.remainingSeconds = box.remainingMinutes! * 60;
    return true;
  }

  void _notifyListenersSafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  void _recordSyncIssue({
    required String source,
    required String message,
    int? boxNumber,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _syncIssues.insert(
      0,
      BoxSyncIssue(
        timestamp: DateTime.now(),
        source: source,
        message: trimmed,
        boxNumber: boxNumber,
      ),
    );
    if (_syncIssues.length > _maxSyncIssueEvents) {
      _syncIssues.removeRange(_maxSyncIssueEvents, _syncIssues.length);
    }
  }

  void _enterCleaningPhase(
    WashBox box, {
    required String title,
    String? details,
  }) {
    box.state = BoxState.cleaning;
    box.remainingMinutes = _cleaningDuration.inMinutes;
    box.remainingSeconds = _cleaningDuration.inSeconds;
    box.sessionStartedAt = null;
    _addTimelineEvent(box.number, title: title, details: details);
  }

  void _seedInitialTimeline() {
    if (_timelineByBoxNumber.isNotEmpty) {
      return;
    }
    for (final box in _boxes) {
      _addTimelineEvent(
        box.number,
        title: 'Initialer Zustand',
        details: box.state.label,
      );
    }
  }

  void _addTimelineEvent(
    int boxNumber, {
    required String title,
    String? details,
  }) {
    final list = _timelineByBoxNumber.putIfAbsent(
      boxNumber,
      () => <BoxTimelineEvent>[],
    );
    list.insert(
      0,
      BoxTimelineEvent(
        boxNumber: boxNumber,
        timestamp: DateTime.now(),
        title: title,
        details: details,
      ),
    );
    _pruneEventsForBox(boxNumber);
    _persistTimeline();
  }

  Future<void> clearTimelineForBox(int boxNumber) async {
    final removed = _timelineByBoxNumber.remove(boxNumber) != null;
    if (!removed) {
      return;
    }
    await _persistTimeline();
    _notifyListenersSafely();
  }

  WashBox? getBoxByNumber(int number) {
    for (final box in _boxes) {
      if (box.number == number) {
        return box;
      }
    }
    return null;
  }

  bool canStartForBox(int boxNumber) {
    final box = getBoxByNumber(boxNumber);
    return box != null && box.state == BoxState.available;
  }

  int? estimatedMinutesUntilAvailable(int boxNumber) {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      return null;
    }
    switch (box.state) {
      case BoxState.available:
        return 0;
      case BoxState.active:
      case BoxState.cleaning:
        return box.remainingMinutes;
      case BoxState.reserved:
      case BoxState.outOfService:
        return null;
    }
  }

  String? startBlockReasonForBox(int boxNumber) {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      return 'Box nicht gefunden.';
    }
    switch (box.state) {
      case BoxState.available:
        return null;
      case BoxState.reserved:
        return 'Box ist aktuell reserviert.';
      case BoxState.active:
        final minutes = estimatedMinutesUntilAvailable(boxNumber);
        if (minutes != null) {
          return 'Box ist aktuell in Benutzung (noch $minutes min).';
        }
        return 'Box ist aktuell in Benutzung.';
      case BoxState.cleaning:
        final minutes = estimatedMinutesUntilAvailable(boxNumber);
        if (minutes != null) {
          return 'Reinigung laeuft (noch $minutes min).';
        }
        return 'Box wird aktuell gereinigt.';
      case BoxState.outOfService:
        return 'Box ist ausser Betrieb.';
    }
  }

  int amountToMinutes(int euroAmount) {
    return euroAmount * 2;
  }

  Future<void> rememberStartSelection({
    int? boxNumber,
    int? amountEuro,
    BoxIdentificationMethod? identificationMethod,
  }) async {
    _startSelectionTouched = true;
    final nextBoxNumber = boxNumber ?? _lastSelectedBoxNumber;
    final nextAmountEuro = amountEuro ?? _lastSelectedAmountEuro;
    final nextIdentificationMethod =
        identificationMethod ?? _lastIdentificationMethod;

    _lastSelectedBoxNumber = nextBoxNumber;
    _lastSelectedAmountEuro = nextAmountEuro;
    _lastIdentificationMethod = nextIdentificationMethod;
    await _persistStartSelection(
      boxNumber: nextBoxNumber,
      amountEuro: nextAmountEuro,
      identificationMethod: nextIdentificationMethod,
    );
  }

  void clearLastSyncError() {
    _lastSyncErrorMessage = null;
    _notifyListenersSafely();
  }

  void clearLastHistorySyncError() {
    _lastHistorySyncErrorMessage = null;
    _notifyListenersSafely();
  }

  Future<void> _restorePersistedState() async {
    await _restoreTimeline();
    _seedInitialTimeline();
    await _restoreStartSelection();
  }

  Future<void> _restoreStartSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (_startSelectionTouched) {
      return;
    }
    _lastSelectedBoxNumber = prefs.getInt(_prefLastBoxNumber);
    _lastSelectedAmountEuro = prefs.getInt(_prefLastAmount);
    final methodRaw = prefs.getString(_prefLastIdentification);
    _lastIdentificationMethod = methodRaw == BoxIdentificationMethod.qr.name
        ? BoxIdentificationMethod.qr
        : BoxIdentificationMethod.manual;
    _notifyListenersSafely();
  }

  Future<void> _persistStartSelection({
    required int? boxNumber,
    required int? amountEuro,
    required BoxIdentificationMethod identificationMethod,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (boxNumber == null) {
      await prefs.remove(_prefLastBoxNumber);
    } else {
      await prefs.setInt(_prefLastBoxNumber, boxNumber);
    }
    if (amountEuro == null) {
      await prefs.remove(_prefLastAmount);
    } else {
      await prefs.setInt(_prefLastAmount, amountEuro);
    }
    await prefs.setString(_prefLastIdentification, identificationMethod.name);
  }

  Future<void> _restoreTimeline() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefTimeline);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      _timelineByBoxNumber.clear();
      final cutoff = DateTime.now().subtract(_timelineRetention);
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }

        final boxNumber = entry['boxNumber'];
        final timestampRaw = entry['timestamp'];
        final title = entry['title'];
        final details = entry['details'];
        if (boxNumber is! int || timestampRaw is! String || title is! String) {
          continue;
        }

        final timestamp = DateTime.tryParse(timestampRaw);
        if (timestamp == null) {
          continue;
        }
        if (timestamp.isBefore(cutoff)) {
          continue;
        }

        final list = _timelineByBoxNumber.putIfAbsent(
          boxNumber,
          () => <BoxTimelineEvent>[],
        );
        list.add(
          BoxTimelineEvent(
            boxNumber: boxNumber,
            timestamp: timestamp,
            title: title,
            details: details is String ? details : null,
          ),
        );
      }

      _pruneAllTimelineEvents();
      _notifyListenersSafely();
    } catch (_) {
      // Ignore malformed persisted payload; timeline will be re-seeded.
    }
  }

  Future<void> _persistTimeline() async {
    final prefs = await SharedPreferences.getInstance();
    final flattened = _timelineByBoxNumber.values.expand((x) => x).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final encoded = flattened.take(200).map((event) {
      return <String, dynamic>{
        'boxNumber': event.boxNumber,
        'timestamp': event.timestamp.toIso8601String(),
        'title': event.title,
        'details': event.details,
      };
    }).toList();

    await prefs.setString(_prefTimeline, jsonEncode(encoded));
  }

  void _pruneEventsForBox(int boxNumber) {
    final list = _timelineByBoxNumber[boxNumber];
    if (list == null) {
      return;
    }
    final cutoff = DateTime.now().subtract(_timelineRetention);
    list.removeWhere((event) => event.timestamp.isBefore(cutoff));
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (list.length > _maxTimelineEventsPerBox) {
      list.removeRange(_maxTimelineEventsPerBox, list.length);
    }
    if (list.isEmpty) {
      _timelineByBoxNumber.remove(boxNumber);
    }
  }

  void _pruneAllTimelineEvents() {
    final keys = _timelineByBoxNumber.keys.toList();
    for (final boxNumber in keys) {
      _pruneEventsForBox(boxNumber);
    }
  }

  Future<void> startWashFlow({
    required int boxNumber,
    required int euroAmount,
    required BoxIdentificationMethod identificationMethod,
    String? qrSignature,
    PaymentStatusCallback? onPaymentStatusChanged,
  }) async {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      throw StateError('Box nicht gefunden');
    }
    if (box.state != BoxState.available) {
      throw StateError('Box ist nicht verfuegbar');
    }

    box.state = BoxState.reserved;
    await rememberStartSelection(
      boxNumber: boxNumber,
      amountEuro: euroAmount,
      identificationMethod: identificationMethod,
    );
    _addTimelineEvent(
      boxNumber,
      title: 'Reservierung gestartet',
      details: 'Betrag: $euroAmount EUR',
    );
    _notifyListenersSafely();
    onPaymentStatusChanged?.call(PaymentStatus.pending);

    try {
      final reserveResponse = await _callWithRetry(() async {
        try {
          return await _backend.reserveBox(
            ReserveBoxRequest(
              boxNumber: boxNumber,
              amountEuro: euroAmount,
              identificationMethod: identificationMethod,
              boxSignature: qrSignature,
            ),
          );
        } on BackendGatewayException catch (e) {
          throw BackendGatewayException(
            code: e.code,
            message: e.message,
            operation: e.operation ?? 'reserve',
          );
        }
      });

      if (DateTime.now().isAfter(reserveResponse.reservedUntil)) {
        throw const BackendGatewayException(
          code: BackendErrorCode.reservationExpired,
          message: 'Reservierung abgelaufen',
          operation: 'activate',
        );
      }

      final activateResponse = await _callWithRetry(() async {
        try {
          return await _backend.activateBox(
            ActivateBoxRequest(
              reservationToken: reserveResponse.reservationToken,
            ),
          );
        } on BackendGatewayException catch (e) {
          throw BackendGatewayException(
            code: e.code,
            message: e.message,
            operation: e.operation ?? 'activate',
          );
        }
      });

      box.state = BoxState.active;
      box.remainingMinutes = activateResponse.runtimeMinutes;
      box.remainingSeconds = activateResponse.runtimeMinutes * 60;
      box.sessionStartedAt = DateTime.now();
      _addTimelineEvent(
        boxNumber,
        title: 'Session aktiv',
        details: '${activateResponse.runtimeMinutes} min',
      );
      _notifyListenersSafely();
      onPaymentStatusChanged?.call(PaymentStatus.success);
      _analytics.track(
        'wash_start_success',
        properties: {
          'box': '$boxNumber',
          'amount_eur': '$euroAmount',
          'ident_method': identificationMethod.name,
        },
      );
    } catch (e) {
      await _bestEffortCancelReservation(boxNumber);
      box.state = BoxState.available;
      box.remainingMinutes = null;
      box.remainingSeconds = null;
      box.sessionStartedAt = null;
      _addTimelineEvent(
        boxNumber,
        title: 'Start fehlgeschlagen',
        details: '$e',
      );
      _notifyListenersSafely();
      onPaymentStatusChanged?.call(PaymentStatus.failed);
      _analytics.track(
        'wash_start_failed',
        properties: {'box': '$boxNumber', 'error': '$e'},
      );
      rethrow;
    }
  }

  Future<void> startRewardWashFlow({
    required int boxNumber,
    required BoxIdentificationMethod identificationMethod,
  }) async {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      throw StateError('Box nicht gefunden');
    }
    if (box.state != BoxState.available) {
      throw StateError('Box ist nicht verfuegbar');
    }

    box.state = BoxState.reserved;
    await rememberStartSelection(
      boxNumber: boxNumber,
      amountEuro: null,
      identificationMethod: identificationMethod,
    );
    _addTimelineEvent(
      boxNumber,
      title: 'Reward eingeloest',
      details: '$rewardRuntimeMinutes min Slot',
    );
    _notifyListenersSafely();

    try {
      final activateResponse = await _callWithRetry(() async {
        try {
          return await _backend.activateRewardBox(boxNumber);
        } on BackendGatewayException catch (e) {
          throw BackendGatewayException(
            code: e.code,
            message: e.message,
            operation: e.operation ?? 'activate_reward',
          );
        }
      });
      box.state = BoxState.active;
      box.remainingMinutes = activateResponse.runtimeMinutes;
      box.remainingSeconds = activateResponse.runtimeMinutes * 60;
      box.sessionStartedAt = DateTime.now();
      _addTimelineEvent(
        boxNumber,
        title: 'Reward-Session aktiv',
        details: '${activateResponse.runtimeMinutes} min',
      );
      _notifyListenersSafely();
      _analytics.track(
        'reward_session_started',
        properties: {
          'box': '$boxNumber',
          'ident_method': identificationMethod.name,
        },
      );
    } catch (e) {
      await _bestEffortCancelReservation(boxNumber);
      box.state = BoxState.available;
      box.remainingMinutes = null;
      box.remainingSeconds = null;
      box.sessionStartedAt = null;
      _addTimelineEvent(
        boxNumber,
        title: 'Reward-Start fehlgeschlagen',
        details: '$e',
      );
      _notifyListenersSafely();
      _analytics.track(
        'reward_session_failed',
        properties: {
          'box': '$boxNumber',
          'ident_method': identificationMethod.name,
          'error': '$e',
        },
      );
      rethrow;
    }
  }

  Future<void> stopActiveSession(int boxNumber) async {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      throw StateError('Box nicht gefunden');
    }
    if (box.state != BoxState.active) {
      throw const BackendGatewayException(
        code: BackendErrorCode.sessionNotActive,
        message: 'Es gibt keine aktive Session zum Stoppen.',
      );
    }

    try {
      await _backend.stopBoxSession(boxNumber);
      try {
        final refreshed = await _backend.getBoxStatus(boxNumber);
        box.state = refreshed.state;
        if (refreshed.state == BoxState.cleaning) {
          box.remainingMinutes = _cleaningDuration.inMinutes;
          box.remainingSeconds = _cleaningDuration.inSeconds;
        } else {
          box.remainingMinutes = refreshed.remainingMinutes;
          box.remainingSeconds = refreshed.remainingSeconds;
        }
        box.lastBackendUpdateAt = DateTime.now();
        if (refreshed.state != BoxState.active) {
          box.sessionStartedAt = null;
        }
        _addTimelineEvent(
          boxNumber,
          title: 'Session manuell gestoppt',
          details: 'Backend: ${refreshed.state.label}',
        );
      } catch (_) {
        _enterCleaningPhase(
          box,
          title: 'Session manuell gestoppt',
          details: 'Reinigung gestartet',
        );
      }
      _notifyListenersSafely();
      _analytics.track('wash_stop_success', properties: {'box': '$boxNumber'});
    } catch (e) {
      _addTimelineEvent(boxNumber, title: 'Stop fehlgeschlagen', details: '$e');
      _analytics.track(
        'wash_stop_failed',
        properties: {'box': '$boxNumber', 'error': '$e'},
      );
      rethrow;
    }
  }

  Future<void> refreshBoxStatus(int boxNumber) async {
    final box = getBoxByNumber(boxNumber);
    if (box == null) {
      return;
    }

    try {
      final previousState = box.state;
      final previousMinutes = box.remainingMinutes;
      final status = await _backend.getBoxStatus(boxNumber);
      box.state = status.state;
      box.remainingMinutes = status.remainingMinutes;
      box.remainingSeconds = status.remainingSeconds;
      box.lastBackendUpdateAt = DateTime.now();
      if (status.state != BoxState.active) {
        box.sessionStartedAt = null;
      }

      if (previousState != status.state ||
          previousMinutes != status.remainingMinutes) {
        _addTimelineEvent(
          boxNumber,
          title: 'Backend-Status aktualisiert',
          details:
              '${previousState.label} -> ${status.state.label}'
              '${status.remainingMinutes != null ? ' (${status.remainingMinutes} min)' : ''}',
        );
      }

      _lastSuccessfulSyncAt = DateTime.now();
      _lastSyncErrorMessage = null;
      _notifyListenersSafely();
    } catch (e) {
      _lastSyncErrorMessage = '$e';
      _addTimelineEvent(boxNumber, title: 'Sync-Fehler', details: '$e');
      _recordSyncIssue(source: 'status', message: '$e', boxNumber: boxNumber);
      _analytics.track(
        'box_sync_error',
        properties: {'box': '$boxNumber', 'error': '$e'},
      );
      _notifyListenersSafely();
      rethrow;
    }
  }

  Future<T> _callWithRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await action();
      } on BackendGatewayException catch (e) {
        final retryable = _isRetryableError(e);
        if (!retryable || attempt >= maxAttempts) {
          rethrow;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
    }
  }

  bool _isRetryableError(BackendGatewayException error) {
    switch (error.code) {
      case BackendErrorCode.backendUnavailable:
      case BackendErrorCode.unknown:
        return true;
      case BackendErrorCode.invalidSignature:
      case BackendErrorCode.boxUnavailable:
      case BackendErrorCode.boxNotFound:
      case BackendErrorCode.reservationExpired:
      case BackendErrorCode.invalidAmount:
      case BackendErrorCode.sessionNotActive:
      case BackendErrorCode.invalidSessionId:
      case BackendErrorCode.insufficientBalance:
      case BackendErrorCode.noRewardAvailable:
      case BackendErrorCode.unauthorized:
      case BackendErrorCode.forbidden:
        return false;
    }
  }

  Future<void> _bestEffortCancelReservation(int boxNumber) async {
    try {
      await _backend.cancelReservation(boxNumber);
    } catch (_) {
      // Backend cleanup is best-effort to avoid blocking user flow.
    }
  }

  Future<void> forceSyncAllBoxes() async {
    await _syncBoxCatalog();
    final numbers = _boxes.map((box) => box.number).toList();
    for (final boxNumber in numbers) {
      try {
        await refreshBoxStatus(boxNumber);
      } catch (_) {
        // Keep going, a single box failure should not block the full sync.
      }
    }
    await syncRecentSessions();
  }

  Future<void> refreshBoxesReadOnly() async {
    await _syncBoxCatalog();
  }

  Future<void> _syncBoxCatalog() async {
    if (_isSyncingCatalog) {
      return;
    }
    _isSyncingCatalog = true;
    try {
      final remoteBoxes = await _backend.listBoxes();
      if (remoteBoxes.isEmpty) {
        return;
      }
      final next =
          remoteBoxes
              .map(
                (item) => WashBox(
                  number: item.boxNumber,
                  state: item.state,
                  remainingMinutes: item.remainingMinutes,
                  remainingSeconds:
                      item.remainingSeconds ??
                      (item.remainingMinutes == null
                          ? null
                          : item.remainingMinutes! * 60),
                ),
              )
              .toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      _boxes
        ..clear()
        ..addAll(next);
      _notifyListenersSafely();
    } on BackendGatewayException catch (e) {
      final isAuthError =
          e.message.contains('HTTP 401') || e.message.contains('HTTP 403');
      if (isAuthError) {
        // Guest sessions may not be allowed to read live boxes.
        _lastSyncErrorMessage = null;
        return;
      }
      _lastSyncErrorMessage = e.message;
      _recordSyncIssue(source: 'catalog', message: e.message);
      _analytics.track(
        'box_catalog_sync_error',
        properties: {'error': e.message},
      );
    } catch (e) {
      _lastSyncErrorMessage = '$e';
      _recordSyncIssue(source: 'catalog', message: '$e');
      _analytics.track('box_catalog_sync_error', properties: {'error': '$e'});
    } finally {
      _isSyncingCatalog = false;
    }
  }

  Future<void> syncRecentSessions({int limit = 30}) async {
    try {
      final sessions = await _backend.getRecentSessions(limit: limit);
      _backendRecentSessions = sessions;
      _lastHistorySyncAt = DateTime.now();
      _lastHistorySyncErrorMessage = null;
      _notifyListenersSafely();
    } catch (e) {
      _lastHistorySyncErrorMessage = '$e';
      _recordSyncIssue(source: 'history', message: '$e');
      _analytics.track('history_sync_error', properties: {'error': '$e'});
      _notifyListenersSafely();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _syncTimer?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }
}

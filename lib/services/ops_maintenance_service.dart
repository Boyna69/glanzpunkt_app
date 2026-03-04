import 'backend_http_client.dart';

class OpsQuickFixResult {
  final int expiredSessions;
  final int updatedBoxes;
  final int expiredReservations;
  final int releasedReservedBoxes;

  const OpsQuickFixResult({
    required this.expiredSessions,
    required this.updatedBoxes,
    required this.expiredReservations,
    required this.releasedReservedBoxes,
  });
}

class OpsMonitoringSnapshot {
  final int totalBoxes;
  final int availableBoxes;
  final int reservedBoxes;
  final int activeBoxes;
  final int cleaningBoxes;
  final int outOfServiceBoxes;
  final int activeSessions;
  final int sessionsNext5m;
  final int openReservations;
  final int staleReservations;
  final int sessionsWithNullBox;
  final int sessionsLast24h;
  final int expiredSessionsSinceLastRun;
  final double washRevenue24hEur;
  final double washRevenueTodayEur;
  final double topUp24hEur;
  final double topUpTodayEur;
  final DateTime? reconcileLastRunAt;
  final DateTime? timestamp;

  const OpsMonitoringSnapshot({
    required this.totalBoxes,
    required this.availableBoxes,
    required this.reservedBoxes,
    required this.activeBoxes,
    required this.cleaningBoxes,
    required this.outOfServiceBoxes,
    required this.activeSessions,
    required this.sessionsNext5m,
    required this.openReservations,
    required this.staleReservations,
    required this.sessionsWithNullBox,
    required this.sessionsLast24h,
    required this.expiredSessionsSinceLastRun,
    required this.washRevenue24hEur,
    required this.washRevenueTodayEur,
    required this.topUp24hEur,
    required this.topUpTodayEur,
    required this.reconcileLastRunAt,
    required this.timestamp,
  });

  factory OpsMonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    final boxesRaw = json['boxes'];
    final boxes = boxesRaw is Map
        ? Map<String, dynamic>.from(boxesRaw)
        : <String, dynamic>{};

    int readInt(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    double readDouble(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value.trim()) ?? 0;
      }
      return 0;
    }

    DateTime? readDateTime(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim())?.toLocal();
      }
      return null;
    }

    return OpsMonitoringSnapshot(
      totalBoxes: readInt(boxes, 'total'),
      availableBoxes: readInt(boxes, 'available'),
      reservedBoxes: readInt(boxes, 'reserved'),
      activeBoxes: readInt(boxes, 'active'),
      cleaningBoxes: readInt(boxes, 'cleaning'),
      outOfServiceBoxes: readInt(boxes, 'out_of_service'),
      activeSessions: readInt(json, 'activeSessions'),
      sessionsNext5m: readInt(json, 'sessionsNext5m'),
      openReservations: readInt(json, 'openReservations'),
      staleReservations: readInt(json, 'staleReservations'),
      sessionsWithNullBox: readInt(json, 'sessionsWithNullBox'),
      sessionsLast24h: readInt(json, 'sessionsLast24h'),
      expiredSessionsSinceLastRun: readInt(json, 'expiredSessionsSinceLastRun'),
      washRevenue24hEur: readDouble(json, 'washRevenue24hEur'),
      washRevenueTodayEur: readDouble(json, 'washRevenueTodayEur'),
      topUp24hEur: readDouble(json, 'topUp24hEur'),
      topUpTodayEur: readDouble(json, 'topUpTodayEur'),
      reconcileLastRunAt: readDateTime(json, 'reconcileLastRunAt'),
      timestamp: readDateTime(json, 'timestamp'),
    );
  }
}

class OpsBoxCleaningPlanItem {
  final int boxId;
  final DateTime? lastCleanedAt;
  final int washesSinceCleaning;
  final int washesUntilNextCleaning;
  final bool isDue;

  const OpsBoxCleaningPlanItem({
    required this.boxId,
    required this.lastCleanedAt,
    required this.washesSinceCleaning,
    required this.washesUntilNextCleaning,
    required this.isDue,
  });
}

class OpsBoxCleaningHistoryItem {
  final int id;
  final int boxId;
  final String performedBy;
  final String? performedByEmail;
  final DateTime cleanedAt;
  final int washesBefore;
  final String? note;

  const OpsBoxCleaningHistoryItem({
    required this.id,
    required this.boxId,
    required this.performedBy,
    required this.performedByEmail,
    required this.cleanedAt,
    required this.washesBefore,
    required this.note,
  });
}

class OpsOperatorActionItem {
  final int id;
  final String actorId;
  final String? actorEmail;
  final String actionName;
  final String actionStatus;
  final int? boxId;
  final String source;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  const OpsOperatorActionItem({
    required this.id,
    required this.actorId,
    required this.actorEmail,
    required this.actionName,
    required this.actionStatus,
    required this.boxId,
    required this.source,
    required this.details,
    required this.createdAt,
  });
}

class OpsKpiExportSnapshot {
  final String period;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime? previousWindowStart;
  final DateTime? previousWindowEnd;
  final DateTime generatedAt;
  final int totalBoxes;
  final int availableBoxes;
  final int reservedBoxes;
  final int activeBoxes;
  final int cleaningBoxes;
  final int outOfServiceBoxes;
  final int activeSessions;
  final int sessionsStarted;
  final int? previousSessionsStarted;
  final int? deltaSessionsStarted;
  final double? deltaSessionsStartedPct;
  final double washRevenueEur;
  final double? previousWashRevenueEur;
  final double? deltaWashRevenueEur;
  final double? deltaWashRevenuePct;
  final double topUpRevenueEur;
  final double? previousTopUpRevenueEur;
  final double? deltaTopUpRevenueEur;
  final double? deltaTopUpRevenuePct;
  final int quickFixes;
  final int cleaningActions;
  final int openReservations;
  final int staleReservations;

  const OpsKpiExportSnapshot({
    required this.period,
    required this.windowStart,
    required this.windowEnd,
    required this.previousWindowStart,
    required this.previousWindowEnd,
    required this.generatedAt,
    required this.totalBoxes,
    required this.availableBoxes,
    required this.reservedBoxes,
    required this.activeBoxes,
    required this.cleaningBoxes,
    required this.outOfServiceBoxes,
    required this.activeSessions,
    required this.sessionsStarted,
    required this.previousSessionsStarted,
    required this.deltaSessionsStarted,
    required this.deltaSessionsStartedPct,
    required this.washRevenueEur,
    required this.previousWashRevenueEur,
    required this.deltaWashRevenueEur,
    required this.deltaWashRevenuePct,
    required this.topUpRevenueEur,
    required this.previousTopUpRevenueEur,
    required this.deltaTopUpRevenueEur,
    required this.deltaTopUpRevenuePct,
    required this.quickFixes,
    required this.cleaningActions,
    required this.openReservations,
    required this.staleReservations,
  });
}

class OpsOperatorThresholdSettings {
  final int cleaningIntervalWashes;
  final int longActiveMinutes;
  final DateTime? updatedAt;

  const OpsOperatorThresholdSettings({
    required this.cleaningIntervalWashes,
    required this.longActiveMinutes,
    required this.updatedAt,
  });
}

class OpsMaintenanceService {
  final BackendHttpClient _httpClient;

  OpsMaintenanceService({BackendHttpClient? httpClient})
    : _httpClient = httpClient ?? createBackendHttpClient();

  Future<OpsQuickFixResult> runExpireActiveSessions({
    required String baseUrl,
    required String jwt,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/expire_active_sessions');
    final response = await _httpClient.postJson(
      uri,
      const <String, dynamic>{},
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ?? 'Quick-Fix fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Quick-Fix-Response ist kein JSON-Objekt.',
      );
    }

    final payload = Map<String, dynamic>.from(response.body as Map);
    int read(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return OpsQuickFixResult(
      expiredSessions: read('expiredSessions'),
      updatedBoxes: read('updatedBoxes'),
      expiredReservations: read('expiredReservations'),
      releasedReservedBoxes: read('releasedReservedBoxes'),
    );
  }

  Future<OpsMonitoringSnapshot> fetchMonitoringSnapshot({
    required String baseUrl,
    required String jwt,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/monitoring_snapshot');
    final response = await _httpClient.postJson(
      uri,
      const <String, dynamic>{},
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Monitoring-Snapshot fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Monitoring-Snapshot ist kein JSON-Objekt.',
      );
    }

    return OpsMonitoringSnapshot.fromJson(
      Map<String, dynamic>.from(response.body as Map),
    );
  }

  Future<OpsKpiExportSnapshot> fetchKpiExportSnapshot({
    required String baseUrl,
    required String jwt,
    required String period,
  }) async {
    final normalizedPeriod = period.trim().toLowerCase();
    if (normalizedPeriod != 'day' &&
        normalizedPeriod != 'week' &&
        normalizedPeriod != 'month') {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'KPI-Periode muss day/week/month sein.',
      );
    }

    final uri = Uri.parse('$baseUrl/rest/v1/rpc/kpi_export');
    BackendHttpResponse response;
    try {
      response = await _httpClient.postJson(
        uri,
        <String, dynamic>{'period': normalizedPeriod},
        headers: <String, String>{'Authorization': 'Bearer $jwt'},
      );
    } on BackendHttpException catch (e) {
      throw StateError(_mapKpiExportTransportError(e));
    }

    if (_isMissingRpc(response.body, rpcName: 'kpi_export')) {
      throw StateError(
        'KPI-Export RPC fehlt. Bitte supabase/operator_kpi_export.sql ausfuehren.',
      );
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ?? 'KPI-Export fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'KPI-Export-Response ist kein JSON-Objekt.',
      );
    }

    final payload = Map<String, dynamic>.from(response.body as Map);

    int readInt(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    double readDouble(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value.trim()) ?? 0;
      }
      return 0;
    }

    DateTime readDateTime(String key) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) {
          return parsed.toLocal();
        }
      }
      throw BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'KPI-Export-Response enthaelt ungueltiges Datum in $key.',
      );
    }

    DateTime? readOptionalDateTime(String key) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim())?.toLocal();
      }
      return null;
    }

    int? readOptionalInt(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value.trim());
      }
      return null;
    }

    double? readOptionalDouble(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value.trim());
      }
      return null;
    }

    return OpsKpiExportSnapshot(
      period:
          (payload['period'] as String?)?.trim().toLowerCase() ??
          normalizedPeriod,
      windowStart: readDateTime('window_start'),
      windowEnd: readDateTime('window_end'),
      previousWindowStart: readOptionalDateTime('previous_window_start'),
      previousWindowEnd: readOptionalDateTime('previous_window_end'),
      generatedAt: readDateTime('generated_at'),
      totalBoxes: readInt('boxes_total'),
      availableBoxes: readInt('boxes_available'),
      reservedBoxes: readInt('boxes_reserved'),
      activeBoxes: readInt('boxes_active'),
      cleaningBoxes: readInt('boxes_cleaning'),
      outOfServiceBoxes: readInt('boxes_out_of_service'),
      activeSessions: readInt('active_sessions'),
      sessionsStarted: readInt('sessions_started'),
      previousSessionsStarted: readOptionalInt('previous_sessions_started'),
      deltaSessionsStarted: readOptionalInt('delta_sessions_started'),
      deltaSessionsStartedPct: readOptionalDouble('delta_sessions_started_pct'),
      washRevenueEur: readDouble('wash_revenue_eur'),
      previousWashRevenueEur: readOptionalDouble('previous_wash_revenue_eur'),
      deltaWashRevenueEur: readOptionalDouble('delta_wash_revenue_eur'),
      deltaWashRevenuePct: readOptionalDouble('delta_wash_revenue_pct'),
      topUpRevenueEur: readDouble('top_up_revenue_eur'),
      previousTopUpRevenueEur: readOptionalDouble(
        'previous_top_up_revenue_eur',
      ),
      deltaTopUpRevenueEur: readOptionalDouble('delta_top_up_revenue_eur'),
      deltaTopUpRevenuePct: readOptionalDouble('delta_top_up_revenue_pct'),
      quickFixes: readInt('quick_fixes'),
      cleaningActions: readInt('cleaning_actions'),
      openReservations: readInt('open_reservations'),
      staleReservations: readInt('stale_reservations'),
    );
  }

  Future<OpsOperatorThresholdSettings> fetchOperatorThresholdSettings({
    required String baseUrl,
    required String jwt,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/rest/v1/rpc/get_operator_threshold_settings',
    );
    final response = await _httpClient.postJson(
      uri,
      const <String, dynamic>{},
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (_isMissingRpc(
      response.body,
      rpcName: 'get_operator_threshold_settings',
    )) {
      throw StateError(
        'Threshold-Settings RPC fehlt. Bitte supabase/operator_threshold_settings.sql ausfuehren.',
      );
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Threshold-Settings laden fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    return _parseOperatorThresholdSettings(response.body);
  }

  Future<OpsOperatorThresholdSettings> updateOperatorThresholdSettings({
    required String baseUrl,
    required String jwt,
    int? cleaningIntervalWashes,
    int? longActiveMinutes,
  }) async {
    if (cleaningIntervalWashes == null && longActiveMinutes == null) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Mindestens ein Threshold-Wert muss gesetzt sein.',
      );
    }

    final uri = Uri.parse(
      '$baseUrl/rest/v1/rpc/set_operator_threshold_settings',
    );
    final payload = <String, dynamic>{};
    if (cleaningIntervalWashes != null) {
      payload['cleaning_interval_washes'] = cleaningIntervalWashes;
    }
    if (longActiveMinutes != null) {
      payload['long_active_minutes'] = longActiveMinutes;
    }

    final response = await _httpClient.postJson(
      uri,
      payload,
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (_isMissingRpc(
      response.body,
      rpcName: 'set_operator_threshold_settings',
    )) {
      throw StateError(
        'Threshold-Settings RPC fehlt. Bitte supabase/operator_threshold_settings.sql ausfuehren.',
      );
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Threshold-Settings speichern fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    return _parseOperatorThresholdSettings(response.body);
  }

  Future<List<OpsBoxCleaningPlanItem>> fetchBoxCleaningPlan({
    required String baseUrl,
    required String jwt,
    int intervalWashes = 75,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/get_box_cleaning_plan');
    final response = await _httpClient.postJson(
      uri,
      <String, dynamic>{'cleaning_interval': intervalWashes},
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Reinigungsplan fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! List) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Reinigungsplan-Response ist keine Liste.',
      );
    }

    DateTime? parseDateTime(Object? raw) {
      if (raw is! String || raw.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw.trim())?.toLocal();
    }

    int parseInt(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final list = <OpsBoxCleaningPlanItem>[];
    for (final item in response.body as List) {
      if (item is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(item);
      final boxId = parseInt(row, 'box_id');
      if (boxId <= 0) {
        continue;
      }
      list.add(
        OpsBoxCleaningPlanItem(
          boxId: boxId,
          lastCleanedAt: parseDateTime(row['last_cleaned_at']),
          washesSinceCleaning: parseInt(row, 'washes_since_cleaning'),
          washesUntilNextCleaning: parseInt(row, 'washes_until_next_cleaning'),
          isDue: row['is_due'] == true,
        ),
      );
    }
    list.sort((a, b) => a.boxId.compareTo(b.boxId));
    return list;
  }

  Future<void> markBoxCleaned({
    required String baseUrl,
    required String jwt,
    required int boxId,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/mark_box_cleaned');
    final payload = <String, dynamic>{'box_id': boxId};
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    if (hasNote) {
      payload['note'] = trimmedNote;
    }
    var response = await _httpClient.postJson(
      uri,
      payload,
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    // Compatibility fallback: older DB revisions only expose
    // mark_box_cleaned(box_id) without the optional note parameter.
    if (hasNote &&
        (response.statusCode < 200 || response.statusCode > 299) &&
        _isLegacyMarkBoxCleanedSignatureMissing(response.body)) {
      response = await _httpClient.postJson(
        uri,
        <String, dynamic>{'box_id': boxId},
        headers: <String, String>{'Authorization': 'Bearer $jwt'},
      );
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Reinigung quittieren fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Reinigung quittieren: Response ist kein JSON-Objekt.',
      );
    }
  }

  OpsOperatorThresholdSettings _parseOperatorThresholdSettings(Object? body) {
    if (body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Threshold-Settings-Response ist kein JSON-Objekt.',
      );
    }

    final payload = Map<String, dynamic>.from(body);

    int readInt(String key) {
      final value = payload[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value.trim()) ?? 0;
      }
      return 0;
    }

    DateTime? readOptionalDateTime(String key) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value.trim())?.toLocal();
      }
      return null;
    }

    final cleaningIntervalWashes = readInt('cleaning_interval_washes');
    final longActiveMinutes = readInt('long_active_minutes');
    if (cleaningIntervalWashes <= 0 || longActiveMinutes <= 0) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message:
            'Threshold-Settings-Response enthaelt ungueltige Schwellenwerte.',
      );
    }

    return OpsOperatorThresholdSettings(
      cleaningIntervalWashes: cleaningIntervalWashes,
      longActiveMinutes: longActiveMinutes,
      updatedAt: readOptionalDateTime('updated_at'),
    );
  }

  bool _isLegacyMarkBoxCleanedSignatureMissing(Object? body) {
    if (body is! Map) {
      return false;
    }
    final payload = Map<String, dynamic>.from(body);
    final code = payload['code']?.toString() ?? '';
    final details = payload['details']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    if (code != 'PGRST202') {
      return false;
    }
    final combined = '$details $message'.toLowerCase();
    return combined.contains('mark_box_cleaned') &&
        combined.contains('box_id') &&
        combined.contains('note');
  }

  Future<List<OpsBoxCleaningHistoryItem>> fetchCleaningHistory({
    required String baseUrl,
    required String jwt,
    int? boxId,
    int maxRows = 30,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/get_box_cleaning_history');
    final payload = <String, dynamic>{'max_rows': maxRows};
    if (boxId != null) {
      payload['box_id'] = boxId;
    }
    final response = await _httpClient.postJson(
      uri,
      payload,
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Reinigungsverlauf fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! List) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Reinigungsverlauf-Response ist keine Liste.',
      );
    }

    DateTime? parseDateTime(Object? raw) {
      if (raw is! String || raw.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw.trim())?.toLocal();
    }

    int parseInt(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final items = <OpsBoxCleaningHistoryItem>[];
    for (final rowRaw in response.body as List) {
      if (rowRaw is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(rowRaw);
      final id = parseInt(row, 'id');
      final entryBoxId = parseInt(row, 'box_id');
      final cleanedAt = parseDateTime(row['cleaned_at']);
      final performedBy = row['performed_by']?.toString() ?? '';
      if (id <= 0 ||
          entryBoxId <= 0 ||
          cleanedAt == null ||
          performedBy.isEmpty) {
        continue;
      }
      final noteRaw = row['note'];
      items.add(
        OpsBoxCleaningHistoryItem(
          id: id,
          boxId: entryBoxId,
          performedBy: performedBy,
          performedByEmail: (row['performed_by_email'] as String?)?.trim(),
          cleanedAt: cleanedAt,
          washesBefore: parseInt(row, 'washes_before'),
          note: noteRaw is String && noteRaw.trim().isNotEmpty
              ? noteRaw.trim()
              : null,
        ),
      );
    }
    items.sort((a, b) => b.cleanedAt.compareTo(a.cleanedAt));
    return items;
  }

  Future<List<OpsOperatorActionItem>> fetchOperatorActions({
    required String baseUrl,
    required String jwt,
    int maxRows = 50,
    int offsetRows = 0,
    String? filterStatus,
    int? filterBoxId,
    String? searchQuery,
    DateTime? fromAt,
    DateTime? untilAt,
  }) async {
    final normalizedMaxRows = maxRows < 1 ? 1 : maxRows;
    final normalizedOffsetRows = offsetRows < 0 ? 0 : offsetRows;
    final normalizedFilterStatus = filterStatus?.trim().toLowerCase();
    final normalizedSearchQuery = searchQuery?.trim();
    final payload = <String, dynamic>{'max_rows': normalizedMaxRows};
    if (normalizedOffsetRows > 0) {
      payload['offset_rows'] = normalizedOffsetRows;
    }
    if (normalizedFilterStatus != null && normalizedFilterStatus.isNotEmpty) {
      payload['filter_status'] = normalizedFilterStatus;
    }
    if (filterBoxId != null) {
      payload['filter_box_id'] = filterBoxId;
    }
    if (normalizedSearchQuery != null && normalizedSearchQuery.isNotEmpty) {
      payload['search_query'] = normalizedSearchQuery;
    }
    if (fromAt != null) {
      payload['from_ts'] = fromAt.toUtc().toIso8601String();
    }
    if (untilAt != null) {
      payload['until_ts'] = untilAt.toUtc().toIso8601String();
    }

    final filteredUri = Uri.parse(
      '$baseUrl/rest/v1/rpc/list_operator_actions_filtered',
    );
    var response = await _httpClient.postJson(
      filteredUri,
      payload,
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    final missingFilteredRpc = _isMissingRpc(
      response.body,
      rpcName: 'list_operator_actions_filtered',
    );
    if (missingFilteredRpc) {
      // Compatibility fallback for DBs that only expose list_operator_actions(max_rows).
      final legacyLimit = (normalizedMaxRows + normalizedOffsetRows)
          .clamp(1, 200)
          .toInt();
      final legacyUri = Uri.parse('$baseUrl/rest/v1/rpc/list_operator_actions');
      response = await _httpClient.postJson(
        legacyUri,
        <String, dynamic>{'max_rows': legacyLimit},
        headers: <String, String>{'Authorization': 'Bearer $jwt'},
      );
      if (response.statusCode < 200 || response.statusCode > 299) {
        final body = response.body;
        final message = body is Map ? body['message'] as String? : null;
        throw StateError(
          message ??
              'Operator-Aktionslog laden fehlgeschlagen (HTTP ${response.statusCode})',
        );
      }
      final rows = _parseOperatorActions(response.body);
      return _applyOperatorActionFilters(
        rows,
        offsetRows: normalizedOffsetRows,
        maxRows: normalizedMaxRows,
        filterStatus: normalizedFilterStatus,
        filterBoxId: filterBoxId,
        searchQuery: normalizedSearchQuery,
        fromAt: fromAt,
        untilAt: untilAt,
      );
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Operator-Aktionslog laden fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    return _parseOperatorActions(response.body);
  }

  bool _isMissingRpc(Object? body, {required String rpcName}) {
    if (body is! Map) {
      return false;
    }
    final payload = Map<String, dynamic>.from(body);
    final code = payload['code']?.toString() ?? '';
    if (code != 'PGRST202') {
      return false;
    }
    final details = payload['details']?.toString().toLowerCase() ?? '';
    final message = payload['message']?.toString().toLowerCase() ?? '';
    final needle = rpcName.toLowerCase();
    return details.contains(needle) || message.contains(needle);
  }

  String _mapKpiExportTransportError(BackendHttpException error) {
    switch (error.kind) {
      case BackendHttpErrorKind.timeout:
        return 'KPI-Export Zeitueberschreitung: Backend antwortet nicht.';
      case BackendHttpErrorKind.network:
        return 'KPI-Export Netzwerkfehler: Verbindung zum Backend fehlgeschlagen.';
      case BackendHttpErrorKind.invalidResponse:
        return 'KPI-Export-Response ungueltig: ${error.message}';
    }
  }

  List<OpsOperatorActionItem> _parseOperatorActions(Object? body) {
    if (body is! List) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Operator-Aktionslog-Response ist keine Liste.',
      );
    }

    int parseInt(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    int? parseNullableInt(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is num) {
        return value.toInt();
      }
      return null;
    }

    DateTime? parseDateTime(Object? raw) {
      if (raw is! String || raw.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(raw.trim())?.toLocal();
    }

    final items = <OpsOperatorActionItem>[];
    for (final rowRaw in body) {
      if (rowRaw is! Map) {
        continue;
      }
      final row = Map<String, dynamic>.from(rowRaw);
      final id = parseInt(row, 'id');
      final actorId = (row['actor_id'] as String?)?.trim() ?? '';
      final actionName = (row['action_name'] as String?)?.trim() ?? '';
      final actionStatus = (row['action_status'] as String?)?.trim() ?? '';
      final source = (row['source'] as String?)?.trim() ?? '';
      final createdAt = parseDateTime(row['created_at']);
      if (id <= 0 ||
          actorId.isEmpty ||
          actionName.isEmpty ||
          actionStatus.isEmpty ||
          source.isEmpty ||
          createdAt == null) {
        continue;
      }
      final detailsRaw = row['details'];
      final details = detailsRaw is Map
          ? Map<String, dynamic>.from(detailsRaw)
          : <String, dynamic>{};
      items.add(
        OpsOperatorActionItem(
          id: id,
          actorId: actorId,
          actorEmail: (row['actor_email'] as String?)?.trim(),
          actionName: actionName,
          actionStatus: actionStatus,
          boxId: parseNullableInt(row, 'box_id'),
          source: source,
          details: details,
          createdAt: createdAt,
        ),
      );
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<OpsOperatorActionItem> _applyOperatorActionFilters(
    List<OpsOperatorActionItem> rows, {
    required int offsetRows,
    required int maxRows,
    String? filterStatus,
    int? filterBoxId,
    String? searchQuery,
    DateTime? fromAt,
    DateTime? untilAt,
  }) {
    final query = searchQuery?.trim().toLowerCase() ?? '';
    final since = fromAt?.toUtc();
    final until = untilAt?.toUtc();
    final filtered = rows.where((row) {
      if (filterStatus != null &&
          filterStatus.isNotEmpty &&
          row.actionStatus != filterStatus) {
        return false;
      }
      if (filterBoxId != null && row.boxId != filterBoxId) {
        return false;
      }
      if (since != null && row.createdAt.toUtc().isBefore(since)) {
        return false;
      }
      if (until != null && row.createdAt.toUtc().isAfter(until)) {
        return false;
      }
      if (query.isNotEmpty) {
        final details = row.details.toString().toLowerCase();
        final matches = <String>[
          row.actionName.toLowerCase(),
          row.actionStatus.toLowerCase(),
          row.source.toLowerCase(),
          row.actorId.toLowerCase(),
          (row.actorEmail ?? '').toLowerCase(),
          if (row.boxId != null) 'box ${row.boxId}',
          details,
        ].any((entry) => entry.contains(query));
        if (!matches) {
          return false;
        }
      }
      return true;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (offsetRows >= filtered.length) {
      return <OpsOperatorActionItem>[];
    }
    final end = (offsetRows + maxRows).clamp(0, filtered.length).toInt();
    return filtered.sublist(offsetRows, end);
  }

  Future<void> logOperatorAction({
    required String baseUrl,
    required String jwt,
    required String actionName,
    String actionStatus = 'success',
    int? boxId,
    Map<String, dynamic>? details,
    String source = 'app',
  }) async {
    final trimmedActionName = actionName.trim();
    if (trimmedActionName.isEmpty) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'actionName darf nicht leer sein.',
      );
    }
    final uri = Uri.parse('$baseUrl/rest/v1/rpc/log_operator_action');
    final payload = <String, dynamic>{
      'action_name': trimmedActionName,
      'action_status': actionStatus.trim().isEmpty
          ? 'success'
          : actionStatus.trim(),
      'source': source.trim().isEmpty ? 'app' : source.trim(),
      'details': details ?? const <String, dynamic>{},
    };
    if (boxId != null) {
      payload['box_id'] = boxId;
    }
    final response = await _httpClient.postJson(
      uri,
      payload,
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
    );

    if (response.statusCode < 200 || response.statusCode > 299) {
      final body = response.body;
      final message = body is Map ? body['message'] as String? : null;
      throw StateError(
        message ??
            'Operator-Aktion speichern fehlgeschlagen (HTTP ${response.statusCode})',
      );
    }

    if (response.body is! Map) {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.invalidResponse,
        message: 'Operator-Aktionslog: Response ist kein JSON-Objekt.',
      );
    }
  }
}

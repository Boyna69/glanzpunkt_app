import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/services/backend_http_client.dart';
import 'package:glanzpunkt_app/services/ops_maintenance_service.dart';

class _FakeBackendHttpClient implements BackendHttpClient {
  BackendHttpResponse nextPostResponse = const BackendHttpResponse(
    statusCode: 200,
    body: <String, dynamic>{},
  );
  final List<BackendHttpResponse> queuedPostResponses = <BackendHttpResponse>[];
  Object? nextPostException;
  final List<Object> queuedPostExceptions = <Object>[];
  Uri? lastPostUri;
  Map<String, dynamic>? lastPostPayload;
  Map<String, String>? lastPostHeaders;
  final List<Uri> allPostUris = <Uri>[];
  final List<Map<String, dynamic>> allPostPayloads = <Map<String, dynamic>>[];

  @override
  Future<BackendHttpResponse> getJson(Uri uri, {Map<String, String>? headers}) {
    throw UnimplementedError();
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    lastPostUri = uri;
    lastPostPayload = payload;
    lastPostHeaders = headers;
    allPostUris.add(uri);
    allPostPayloads.add(Map<String, dynamic>.from(payload));
    if (queuedPostExceptions.isNotEmpty) {
      throw queuedPostExceptions.removeAt(0);
    }
    if (nextPostException != null) {
      final error = nextPostException!;
      nextPostException = null;
      throw error;
    }
    if (queuedPostResponses.isNotEmpty) {
      return queuedPostResponses.removeAt(0);
    }
    return nextPostResponse;
  }
}

void main() {
  test('runExpireActiveSessions returns parsed counters', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'expiredSessions': 7,
          'updatedBoxes': 2,
          'expiredReservations': 3,
          'releasedReservedBoxes': 4,
        },
      );
    final service = OpsMaintenanceService(httpClient: client);

    final result = await service.runExpireActiveSessions(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/expire_active_sessions',
    );
    expect(client.lastPostPayload, isEmpty);
    expect(client.lastPostHeaders?['Authorization'], 'Bearer jwt-token');
    expect(result.expiredSessions, 7);
    expect(result.updatedBoxes, 2);
    expect(result.expiredReservations, 3);
    expect(result.releasedReservedBoxes, 4);
  });

  test('runExpireActiveSessions throws StateError on non-2xx', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 500,
        body: <String, dynamic>{'message': 'db_failed'},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.runExpireActiveSessions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(predicate((e) => e is StateError && '$e'.contains('db_failed'))),
    );
  });

  test('runExpireActiveSessions throws on invalid response body', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <dynamic>[],
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.runExpireActiveSessions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('fetchMonitoringSnapshot parses counters and revenue fields', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'boxes': <String, dynamic>{
            'total': 6,
            'available': 3,
            'reserved': 1,
            'active': 2,
            'cleaning': 0,
            'out_of_service': 0,
          },
          'activeSessions': 2,
          'sessionsNext5m': 1,
          'openReservations': 1,
          'staleReservations': 0,
          'sessionsWithNullBox': 0,
          'sessionsLast24h': 33,
          'expiredSessionsSinceLastRun': 4,
          'washRevenue24hEur': 54.5,
          'washRevenueTodayEur': 12,
          'topUp24hEur': 80,
          'topUpTodayEur': 20.75,
          'timestamp': '2026-02-22T19:00:00Z',
          'reconcileLastRunAt': '2026-02-22T18:55:00Z',
        },
      );
    final service = OpsMaintenanceService(httpClient: client);

    final result = await service.fetchMonitoringSnapshot(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/monitoring_snapshot',
    );
    expect(client.lastPostPayload, isEmpty);
    expect(client.lastPostHeaders?['Authorization'], 'Bearer jwt-token');
    expect(result.totalBoxes, 6);
    expect(result.activeBoxes, 2);
    expect(result.sessionsLast24h, 33);
    expect(result.washRevenue24hEur, 54.5);
    expect(result.washRevenueTodayEur, 12);
    expect(result.topUpTodayEur, 20.75);
    expect(result.timestamp, isNotNull);
    expect(result.reconcileLastRunAt, isNotNull);
  });

  test('fetchMonitoringSnapshot throws on non-map body', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <dynamic>[],
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.fetchMonitoringSnapshot(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('fetchKpiExportSnapshot parses kpi_export payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'period': 'week',
          'window_start': '2026-02-23T00:00:00Z',
          'window_end': '2026-02-28T23:00:00Z',
          'previous_window_start': '2026-02-16T00:00:00Z',
          'previous_window_end': '2026-02-21T23:00:00Z',
          'generated_at': '2026-02-28T23:00:05Z',
          'boxes_total': 6,
          'boxes_available': 4,
          'boxes_reserved': 1,
          'boxes_active': 1,
          'boxes_cleaning': 0,
          'boxes_out_of_service': 0,
          'active_sessions': 1,
          'sessions_started': 42,
          'previous_sessions_started': 38,
          'delta_sessions_started': 4,
          'delta_sessions_started_pct': 10.53,
          'wash_revenue_eur': 123.5,
          'previous_wash_revenue_eur': 110.0,
          'delta_wash_revenue_eur': 13.5,
          'delta_wash_revenue_pct': 12.27,
          'top_up_revenue_eur': 60,
          'previous_top_up_revenue_eur': 55.0,
          'delta_top_up_revenue_eur': 5.0,
          'delta_top_up_revenue_pct': 9.09,
          'quick_fixes': 3,
          'cleaning_actions': 5,
          'open_reservations': 1,
          'stale_reservations': 0,
        },
      );
    final service = OpsMaintenanceService(httpClient: client);

    final snapshot = await service.fetchKpiExportSnapshot(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      period: 'week',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/kpi_export',
    );
    expect(client.lastPostPayload, <String, dynamic>{'period': 'week'});
    expect(snapshot.period, 'week');
    expect(snapshot.totalBoxes, 6);
    expect(snapshot.sessionsStarted, 42);
    expect(snapshot.previousSessionsStarted, 38);
    expect(snapshot.deltaSessionsStarted, 4);
    expect(snapshot.deltaSessionsStartedPct, 10.53);
    expect(snapshot.washRevenueEur, 123.5);
    expect(snapshot.previousWashRevenueEur, 110.0);
    expect(snapshot.deltaWashRevenueEur, 13.5);
    expect(snapshot.deltaWashRevenuePct, 12.27);
    expect(snapshot.topUpRevenueEur, 60);
    expect(snapshot.previousTopUpRevenueEur, 55.0);
    expect(snapshot.deltaTopUpRevenueEur, 5.0);
    expect(snapshot.deltaTopUpRevenuePct, 9.09);
    expect(snapshot.quickFixes, 3);
  });

  test(
    'fetchKpiExportSnapshot throws clear error when rpc is missing',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 404,
          body: <String, dynamic>{
            'code': 'PGRST202',
            'details': 'Searched for the function public.kpi_export',
            'message': 'Could not find the function public.kpi_export',
          },
        );
      final service = OpsMaintenanceService(httpClient: client);

      await expectLater(
        () => service.fetchKpiExportSnapshot(
          baseUrl: 'https://example.supabase.co',
          jwt: 'jwt-token',
          period: 'day',
        ),
        throwsA(
          predicate(
            (e) => e is StateError && '$e'.contains('KPI-Export RPC fehlt'),
          ),
        ),
      );
    },
  );

  test('fetchKpiExportSnapshot validates period parameter', () async {
    final service = OpsMaintenanceService(httpClient: _FakeBackendHttpClient());

    await expectLater(
      () => service.fetchKpiExportSnapshot(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        period: 'year',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'fetchKpiExportSnapshot maps timeout transport errors to readable StateError',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostException = const BackendHttpException(
          kind: BackendHttpErrorKind.timeout,
          message: 'timeout',
        );
      final service = OpsMaintenanceService(httpClient: client);

      await expectLater(
        () => service.fetchKpiExportSnapshot(
          baseUrl: 'https://example.supabase.co',
          jwt: 'jwt-token',
          period: 'day',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                '$e'.contains('KPI-Export Zeitueberschreitung'),
          ),
        ),
      );
    },
  );

  test(
    'fetchKpiExportSnapshot maps network transport errors to readable StateError',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostException = const BackendHttpException(
          kind: BackendHttpErrorKind.network,
          message: 'SocketException',
        );
      final service = OpsMaintenanceService(httpClient: client);

      await expectLater(
        () => service.fetchKpiExportSnapshot(
          baseUrl: 'https://example.supabase.co',
          jwt: 'jwt-token',
          period: 'week',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError && '$e'.contains('KPI-Export Netzwerkfehler'),
          ),
        ),
      );
    },
  );

  test(
    'fetchKpiExportSnapshot handles missing optional delta fields',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'period': 'day',
            'window_start': '2026-03-01T00:00:00Z',
            'window_end': '2026-03-01T08:00:00Z',
            'generated_at': '2026-03-01T08:00:00Z',
            'boxes_total': 6,
            'boxes_available': 6,
            'boxes_reserved': 0,
            'boxes_active': 0,
            'boxes_cleaning': 0,
            'boxes_out_of_service': 0,
            'active_sessions': 0,
            'sessions_started': 3,
            'wash_revenue_eur': 3,
            'top_up_revenue_eur': 0,
            'quick_fixes': 0,
            'cleaning_actions': 0,
            'open_reservations': 0,
            'stale_reservations': 0,
          },
        );
      final service = OpsMaintenanceService(httpClient: client);

      final snapshot = await service.fetchKpiExportSnapshot(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        period: 'day',
      );

      expect(snapshot.previousWindowStart, isNull);
      expect(snapshot.previousWindowEnd, isNull);
      expect(snapshot.previousSessionsStarted, isNull);
      expect(snapshot.deltaSessionsStarted, isNull);
      expect(snapshot.deltaSessionsStartedPct, isNull);
      expect(snapshot.previousWashRevenueEur, isNull);
      expect(snapshot.deltaWashRevenueEur, isNull);
      expect(snapshot.deltaWashRevenuePct, isNull);
      expect(snapshot.previousTopUpRevenueEur, isNull);
      expect(snapshot.deltaTopUpRevenueEur, isNull);
      expect(snapshot.deltaTopUpRevenuePct, isNull);
    },
  );

  test('fetchOperatorThresholdSettings parses settings payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{
          'cleaning_interval_washes': 90,
          'long_active_minutes': 35,
          'updated_at': '2026-03-01T10:00:00Z',
          'updated_by': '86face94-676d-420a-90fe-13de7f3dcbfd',
        },
      );
    final service = OpsMaintenanceService(httpClient: client);

    final settings = await service.fetchOperatorThresholdSettings(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/get_operator_threshold_settings',
    );
    expect(client.lastPostPayload, isEmpty);
    expect(settings.cleaningIntervalWashes, 90);
    expect(settings.longActiveMinutes, 35);
    expect(settings.updatedAt, isNotNull);
  });

  test(
    'fetchOperatorThresholdSettings throws clear error when rpc is missing',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 404,
          body: <String, dynamic>{
            'code': 'PGRST202',
            'details':
                'Searched for the function public.get_operator_threshold_settings',
            'message':
                'Could not find the function public.get_operator_threshold_settings',
          },
        );
      final service = OpsMaintenanceService(httpClient: client);

      await expectLater(
        () => service.fetchOperatorThresholdSettings(
          baseUrl: 'https://example.supabase.co',
          jwt: 'jwt-token',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                '$e'.contains('Threshold-Settings RPC fehlt'),
          ),
        ),
      );
    },
  );

  test(
    'updateOperatorThresholdSettings posts payload and parses response',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'cleaning_interval_washes': 100,
            'long_active_minutes': 25,
            'updated_at': '2026-03-01T10:30:00Z',
            'updated_by': '86face94-676d-420a-90fe-13de7f3dcbfd',
          },
        );
      final service = OpsMaintenanceService(httpClient: client);

      final settings = await service.updateOperatorThresholdSettings(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        cleaningIntervalWashes: 100,
        longActiveMinutes: 25,
      );

      expect(
        client.lastPostUri.toString(),
        'https://example.supabase.co/rest/v1/rpc/set_operator_threshold_settings',
      );
      expect(client.lastPostPayload, <String, dynamic>{
        'cleaning_interval_washes': 100,
        'long_active_minutes': 25,
      });
      expect(settings.cleaningIntervalWashes, 100);
      expect(settings.longActiveMinutes, 25);
    },
  );

  test('updateOperatorThresholdSettings rejects empty payload', () async {
    final service = OpsMaintenanceService(httpClient: _FakeBackendHttpClient());

    await expectLater(
      () => service.updateOperatorThresholdSettings(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('fetchBoxCleaningPlan parses plan rows and sorts by box', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <Map<String, dynamic>>[
          <String, dynamic>{
            'box_id': 2,
            'last_cleaned_at': '2026-02-22T10:00:00Z',
            'washes_since_cleaning': 80,
            'washes_until_next_cleaning': 0,
            'is_due': true,
          },
          <String, dynamic>{
            'box_id': 1,
            'last_cleaned_at': null,
            'washes_since_cleaning': 5,
            'washes_until_next_cleaning': 70,
            'is_due': false,
          },
        ],
      );
    final service = OpsMaintenanceService(httpClient: client);

    final rows = await service.fetchBoxCleaningPlan(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      intervalWashes: 75,
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/get_box_cleaning_plan',
    );
    expect(client.lastPostPayload, <String, dynamic>{'cleaning_interval': 75});
    expect(rows.length, 2);
    expect(rows.first.boxId, 1);
    expect(rows.first.washesSinceCleaning, 5);
    expect(rows.first.washesUntilNextCleaning, 70);
    expect(rows.first.isDue, isFalse);
    expect(rows.first.lastCleanedAt, isNull);
    expect(rows.last.boxId, 2);
    expect(rows.last.isDue, isTrue);
    expect(rows.last.lastCleanedAt, isNotNull);
  });

  test('fetchBoxCleaningPlan throws on non-list body', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'ok': true},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.fetchBoxCleaningPlan(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('markBoxCleaned posts rpc payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'ok': true},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.markBoxCleaned(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      boxId: 3,
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/mark_box_cleaned',
    );
    expect(client.lastPostPayload, <String, dynamic>{'box_id': 3});
    expect(client.lastPostHeaders?['Authorization'], 'Bearer jwt-token');
  });

  test('markBoxCleaned includes optional note payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'ok': true},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.markBoxCleaned(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      boxId: 4,
      note: 'Duesen geprueft',
    );

    expect(client.lastPostPayload, <String, dynamic>{
      'box_id': 4,
      'note': 'Duesen geprueft',
    });
  });

  test(
    'markBoxCleaned retries without note payload on legacy rpc signature',
    () async {
      final client = _FakeBackendHttpClient()
        ..queuedPostResponses.addAll([
          const BackendHttpResponse(
            statusCode: 404,
            body: <String, dynamic>{
              'code': 'PGRST202',
              'details':
                  'Searched for the function public.mark_box_cleaned with parameters box_id, note',
              'message':
                  'Could not find the function public.mark_box_cleaned(box_id, note) in the schema cache',
            },
          ),
          const BackendHttpResponse(
            statusCode: 200,
            body: <String, dynamic>{'ok': true},
          ),
        ]);
      final service = OpsMaintenanceService(httpClient: client);

      await service.markBoxCleaned(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        boxId: 4,
        note: 'Legacy fallback',
      );

      expect(client.allPostPayloads.length, 2);
      expect(client.allPostPayloads.first, <String, dynamic>{
        'box_id': 4,
        'note': 'Legacy fallback',
      });
      expect(client.allPostPayloads.last, <String, dynamic>{'box_id': 4});
      expect(client.lastPostHeaders?['Authorization'], 'Bearer jwt-token');
    },
  );

  test('fetchCleaningHistory parses and sorts events', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 2,
            'box_id': 1,
            'performed_by': 'uid-a',
            'performed_by_email': 'ops@example.com',
            'cleaned_at': '2026-02-22T09:00:00Z',
            'washes_before': 75,
            'note': 'Foam refill',
          },
          <String, dynamic>{
            'id': 1,
            'box_id': 1,
            'performed_by': 'uid-a',
            'performed_by_email': 'ops@example.com',
            'cleaned_at': '2026-02-22T08:00:00Z',
            'washes_before': 70,
            'note': null,
          },
        ],
      );
    final service = OpsMaintenanceService(httpClient: client);

    final rows = await service.fetchCleaningHistory(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      boxId: 1,
      maxRows: 20,
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/get_box_cleaning_history',
    );
    expect(client.lastPostPayload, <String, dynamic>{
      'box_id': 1,
      'max_rows': 20,
    });
    expect(rows.length, 2);
    expect(rows.first.id, 2);
    expect(rows.first.note, 'Foam refill');
    expect(rows.first.performedByEmail, 'ops@example.com');
    expect(rows.last.id, 1);
    expect(rows.last.note, isNull);
  });

  test('fetchCleaningHistory throws on non-list body', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'ok': true},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.fetchCleaningHistory(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'fetchOperatorActions parses rows and sorts by created_at desc',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 200,
          body: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'actor_id': 'uid-a',
              'actor_email': 'ops@example.com',
              'action_name': 'status_refresh',
              'action_status': 'success',
              'box_id': null,
              'source': 'app',
              'details': <String, dynamic>{'warning': 'none'},
              'created_at': '2026-02-28T20:00:00Z',
            },
            <String, dynamic>{
              'id': 2,
              'actor_id': 'uid-a',
              'actor_email': 'ops@example.com',
              'action_name': 'quick_fix',
              'action_status': 'failed',
              'box_id': 3,
              'source': 'app',
              'details': <String, dynamic>{'error': 'boom'},
              'created_at': '2026-02-28T21:00:00Z',
            },
          ],
        );
      final service = OpsMaintenanceService(httpClient: client);

      final rows = await service.fetchOperatorActions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        maxRows: 25,
      );

      expect(
        client.lastPostUri.toString(),
        'https://example.supabase.co/rest/v1/rpc/list_operator_actions_filtered',
      );
      expect(client.lastPostPayload, <String, dynamic>{'max_rows': 25});
      expect(rows.length, 2);
      expect(rows.first.id, 2);
      expect(rows.first.actionName, 'quick_fix');
      expect(rows.first.actionStatus, 'failed');
      expect(rows.first.boxId, 3);
      expect(rows.first.details['error'], 'boom');
      expect(rows.last.id, 1);
    },
  );

  test(
    'fetchOperatorActions sends server-side filters and pagination',
    () async {
      final client = _FakeBackendHttpClient()
        ..nextPostResponse = const BackendHttpResponse(
          statusCode: 200,
          body: <Map<String, dynamic>>[],
        );
      final service = OpsMaintenanceService(httpClient: client);

      final fromAt = DateTime.utc(2026, 2, 1, 0, 0, 0);
      final untilAt = DateTime.utc(2026, 2, 28, 23, 59, 59);

      await service.fetchOperatorActions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        maxRows: 20,
        offsetRows: 40,
        filterStatus: 'failed',
        filterBoxId: 3,
        searchQuery: 'quick_fix',
        fromAt: fromAt,
        untilAt: untilAt,
      );

      expect(
        client.lastPostUri.toString(),
        'https://example.supabase.co/rest/v1/rpc/list_operator_actions_filtered',
      );
      expect(client.lastPostPayload, <String, dynamic>{
        'max_rows': 20,
        'offset_rows': 40,
        'filter_status': 'failed',
        'filter_box_id': 3,
        'search_query': 'quick_fix',
        'from_ts': fromAt.toIso8601String(),
        'until_ts': untilAt.toIso8601String(),
      });
    },
  );

  test(
    'fetchOperatorActions falls back to legacy rpc when filtered rpc is missing',
    () async {
      final client = _FakeBackendHttpClient()
        ..queuedPostResponses.addAll([
          const BackendHttpResponse(
            statusCode: 404,
            body: <String, dynamic>{
              'code': 'PGRST202',
              'details':
                  'Searched for the function public.list_operator_actions_filtered',
              'message':
                  'Could not find the function public.list_operator_actions_filtered',
            },
          ),
          const BackendHttpResponse(
            statusCode: 200,
            body: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 10,
                'actor_id': 'uid-a',
                'actor_email': 'ops@example.com',
                'action_name': 'quick_fix',
                'action_status': 'success',
                'box_id': 1,
                'source': 'app',
                'details': <String, dynamic>{'ok': true},
                'created_at': '2026-02-28T21:00:00Z',
              },
              <String, dynamic>{
                'id': 9,
                'actor_id': 'uid-a',
                'actor_email': 'ops@example.com',
                'action_name': 'status_refresh',
                'action_status': 'failed',
                'box_id': 2,
                'source': 'app',
                'details': <String, dynamic>{'error': 'boom'},
                'created_at': '2026-02-28T20:00:00Z',
              },
            ],
          ),
        ]);
      final service = OpsMaintenanceService(httpClient: client);

      final rows = await service.fetchOperatorActions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        maxRows: 20,
        offsetRows: 0,
        filterStatus: 'success',
        filterBoxId: 1,
      );

      expect(client.allPostUris.length, 2);
      expect(
        client.allPostUris.first.toString(),
        'https://example.supabase.co/rest/v1/rpc/list_operator_actions_filtered',
      );
      expect(
        client.allPostUris.last.toString(),
        'https://example.supabase.co/rest/v1/rpc/list_operator_actions',
      );
      expect(rows.length, 1);
      expect(rows.first.id, 10);
      expect(rows.first.actionStatus, 'success');
      expect(rows.first.boxId, 1);
    },
  );

  test('fetchOperatorActions throws on non-list body', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'ok': true},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.fetchOperatorActions(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
      ),
      throwsA(
        predicate(
          (e) =>
              e is BackendHttpException &&
              e.kind == BackendHttpErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('logOperatorAction posts rpc payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'id': 12},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.logOperatorAction(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      actionName: 'quick_fix',
      actionStatus: 'success',
      boxId: 4,
      details: <String, dynamic>{'updatedBoxes': 6},
      source: 'app',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/log_operator_action',
    );
    expect(client.lastPostPayload, <String, dynamic>{
      'action_name': 'quick_fix',
      'action_status': 'success',
      'source': 'app',
      'details': <String, dynamic>{'updatedBoxes': 6},
      'box_id': 4,
    });
    expect(client.lastPostHeaders?['Authorization'], 'Bearer jwt-token');
  });

  test('logOperatorAction throws StateError on non-2xx', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 403,
        body: <String, dynamic>{'message': 'forbidden'},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.logOperatorAction(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        actionName: 'quick_fix',
      ),
      throwsA(predicate((e) => e is StateError && '$e'.contains('forbidden'))),
    );
  });

  test('logUatAction posts standardized uat details payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'id': 99},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.logUatAction(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      actionName: 'status_refresh',
      actionStatus: 'failed',
      summary: 'Status-Refresh fehlgeschlagen',
      area: 'operator_dashboard',
      uatStatus: OpsUatStatus.open,
      severity: OpsUatSeverity.high,
      targetBuild: '1.0.3+4',
      boxId: 2,
      details: <String, dynamic>{'error': 'timeout'},
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/log_operator_action',
    );
    expect(client.lastPostPayload?['action_name'], 'status_refresh');
    expect(client.lastPostPayload?['action_status'], 'failed');
    expect(client.lastPostPayload?['source'], 'app');
    expect(client.lastPostPayload?['box_id'], 2);
    expect(client.lastPostPayload?['details'], <String, dynamic>{
      'error': 'timeout',
      'summary': 'Status-Refresh fehlgeschlagen',
      'area': 'operator_dashboard',
      'uat_status': 'open',
      'severity': 'high',
      'target_build': '1.0.3+4',
      'logged_via': 'app_uat_helper',
    });
  });

  test('logUatAction applies safe defaults for area and build', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'id': 100},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.logUatAction(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      actionName: 'quick_fix',
      actionStatus: 'success',
      summary: 'Quick-Fix ausgefuehrt',
      area: '   ',
      details: <String, dynamic>{'updatedBoxes': 6},
    );

    final details = client.lastPostPayload?['details'] as Map<String, dynamic>;
    expect(details['summary'], 'Quick-Fix ausgefuehrt');
    expect(details['area'], 'operator');
    expect(details['target_build'], 'current');
    expect(details['uat_status'], 'open');
    expect(details['severity'], 'medium');
    expect(details['logged_via'], 'app_uat_helper');
    expect(details['updatedBoxes'], 6);
  });

  test('setUatTicketStatus posts rpc payload', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <String, dynamic>{'id': 200},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await service.setUatTicketStatus(
      baseUrl: 'https://example.supabase.co',
      jwt: 'jwt-token',
      ticketId: 42,
      uatStatus: OpsUatStatus.inProgress,
      note: 'Wird geprueft',
    );

    expect(
      client.lastPostUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/set_uat_ticket_status',
    );
    expect(client.lastPostPayload, <String, dynamic>{
      'ticket_id': 42,
      'uat_status': 'in_progress',
      'note': 'Wird geprueft',
    });
  });

  test(
    'assignUatTicketOwner posts rpc payload and allows clear owner',
    () async {
      final client = _FakeBackendHttpClient()
        ..queuedPostResponses.addAll(<BackendHttpResponse>[
          const BackendHttpResponse(
            statusCode: 200,
            body: <String, dynamic>{'id': 201},
          ),
          const BackendHttpResponse(
            statusCode: 200,
            body: <String, dynamic>{'id': 202},
          ),
        ]);
      final service = OpsMaintenanceService(httpClient: client);

      await service.assignUatTicketOwner(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        ticketId: 42,
        ownerEmail: 'ops@glanzpunkt.de',
        note: 'Owner gesetzt',
      );
      await service.assignUatTicketOwner(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        ticketId: 42,
        ownerEmail: '',
      );

      expect(
        client.allPostUris.first.toString(),
        'https://example.supabase.co/rest/v1/rpc/assign_uat_ticket_owner',
      );
      expect(client.allPostPayloads.first, <String, dynamic>{
        'ticket_id': 42,
        'owner_email': 'ops@glanzpunkt.de',
        'note': 'Owner gesetzt',
      });
      expect(client.allPostPayloads.last, <String, dynamic>{
        'ticket_id': 42,
        'owner_email': null,
      });
    },
  );

  test('setUatTicketStatus throws StateError on non-2xx', () async {
    final client = _FakeBackendHttpClient()
      ..nextPostResponse = const BackendHttpResponse(
        statusCode: 403,
        body: <String, dynamic>{'message': 'forbidden'},
      );
    final service = OpsMaintenanceService(httpClient: client);

    await expectLater(
      () => service.setUatTicketStatus(
        baseUrl: 'https://example.supabase.co',
        jwt: 'jwt-token',
        ticketId: 1,
        uatStatus: OpsUatStatus.open,
      ),
      throwsA(predicate((e) => e is StateError && '$e'.contains('forbidden'))),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/box.dart';
import 'package:glanzpunkt_app/services/backend_http_client.dart';
import 'package:glanzpunkt_app/services/remote_wash_backend_gateway.dart';
import 'package:glanzpunkt_app/services/wash_backend_gateway.dart';

class _FakeClient implements BackendHttpClient {
  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.endsWith('/rest/v1/wash_sessions')) {
      return const BackendHttpResponse(
        statusCode: 200,
        body: [
          {
            'id': 1,
            'box_id': 3,
            'started_at': '2026-02-20T12:00:00Z',
            'ends_at': '2026-02-20T12:20:00Z',
            'amount': 10,
          },
        ],
      );
    }
    if (uri.path.endsWith('/rest/v1/boxes')) {
      return const BackendHttpResponse(
        statusCode: 200,
        body: [
          {'id': 1, 'status': 'available', 'remaining_seconds': 0},
        ],
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    if (uri.path.endsWith('/rest/v1/rpc/status')) {
      return const BackendHttpResponse(
        statusCode: 200,
        body: {'state': 'active', 'remaining_seconds': 342},
      );
    }
    throw UnimplementedError();
  }
}

class _TimeoutClient implements BackendHttpClient {
  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    throw const BackendHttpException(
      kind: BackendHttpErrorKind.timeout,
      message: 'timeout',
    );
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    throw const BackendHttpException(
      kind: BackendHttpErrorKind.timeout,
      message: 'timeout',
    );
  }
}

class _CapturingClient implements BackendHttpClient {
  Map<String, String>? lastHeaders;

  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    lastHeaders = headers;
    return const BackendHttpResponse(
      statusCode: 200,
      body: [
        {'id': 1, 'status': 'available', 'remaining_seconds': 0},
      ],
    );
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    lastHeaders = headers;
    return const BackendHttpResponse(
      statusCode: 200,
      body: {'state': 'available', 'remainingMinutes': 0},
    );
  }
}

class _ErrorPostClient implements BackendHttpClient {
  final int statusCode;
  final Map<String, dynamic> body;

  const _ErrorPostClient({required this.statusCode, required this.body});

  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    return const BackendHttpResponse(
      statusCode: 200,
      body: [
        {'id': 1, 'status': 'available', 'remaining_seconds': 0},
      ],
    );
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    return BackendHttpResponse(statusCode: statusCode, body: body);
  }
}

void main() {
  test('getBoxStatus parses remainingMinutes from num', () async {
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: _FakeClient(),
    );

    final response = await gateway.getBoxStatus(3);
    expect(response.state, BoxState.active);
    expect(response.remainingMinutes, 6);
    expect(response.remainingSeconds, 342);
  });

  test('maps timeout http errors to gateway exception', () async {
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: _TimeoutClient(),
    );

    await expectLater(
      () => gateway.getBoxStatus(1),
      throwsA(isA<BackendGatewayException>()),
    );
  });

  test('getRecentSessions parses typed session items', () async {
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: _FakeClient(),
    );

    final items = await gateway.getRecentSessions(limit: 10);
    expect(items, hasLength(1));
    expect(items.first.sessionId, '1');
    expect(items.first.boxNumber, 3);
    expect(items.first.status, 'completed');
    expect(items.first.amountEuro, 10);
  });

  test('sends user jwt in post call headers', () async {
    final client = _CapturingClient();
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: client,
      jwtProvider: () => 'user-jwt-123',
    );

    await gateway.getBoxStatus(2);

    expect(client.lastHeaders?['Authorization'], 'Bearer user-jwt-123');
  });

  test('sends user jwt in get call headers', () async {
    final client = _CapturingClient();
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: client,
      jwtProvider: () => 'user-jwt-123',
    );

    await gateway.listBoxes();

    expect(client.lastHeaders?['Authorization'], 'Bearer user-jwt-123');
  });

  test('reserve maps 42501 to forbidden with reserve operation', () async {
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: const _ErrorPostClient(
        statusCode: 403,
        body: {
          'code': '42501',
          'message': 'permission denied for function reserve',
        },
      ),
      jwtProvider: () => 'user-jwt-123',
    );

    await expectLater(
      () => gateway.reserveBox(
        const ReserveBoxRequest(
          boxNumber: 1,
          amountEuro: 5,
          identificationMethod: BoxIdentificationMethod.manual,
        ),
      ),
      throwsA(
        isA<BackendGatewayException>()
            .having((e) => e.code, 'code', BackendErrorCode.forbidden)
            .having((e) => e.operation, 'operation', 'reserve'),
      ),
    );
  });

  test('reserve maps box_not_found payload to boxNotFound', () async {
    final gateway = RemoteWashBackendGateway(
      baseUrlProvider: () => 'http://localhost:8080',
      client: const _ErrorPostClient(
        statusCode: 400,
        body: {'code': 'box_not_found', 'message': 'box_not_found'},
      ),
      jwtProvider: () => 'user-jwt-123',
    );

    await expectLater(
      () => gateway.reserveBox(
        const ReserveBoxRequest(
          boxNumber: 99,
          amountEuro: 5,
          identificationMethod: BoxIdentificationMethod.manual,
        ),
      ),
      throwsA(
        isA<BackendGatewayException>().having(
          (e) => e.code,
          'code',
          BackendErrorCode.boxNotFound,
        ),
      ),
    );
  });
}

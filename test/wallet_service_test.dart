import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/wallet_transaction.dart';
import 'package:glanzpunkt_app/services/backend_http_client.dart';
import 'package:glanzpunkt_app/services/wallet_service.dart';

class _FakeClient implements BackendHttpClient {
  BackendHttpResponse getResponse = const BackendHttpResponse(
    statusCode: 200,
    body: <Map<String, dynamic>>[],
  );

  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    return getResponse;
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('refresh parses top-ups and charges', () async {
    final client = _FakeClient()
      ..getResponse = const BackendHttpResponse(
        statusCode: 200,
        body: <Map<String, dynamic>>[
          {
            'id': 1,
            'amount': 20,
            'created_at': '2026-02-22T12:00:00Z',
            'type': 'top_up',
          },
          {
            'id': 2,
            'amount': -5,
            'created_at': '2026-02-22T12:10:00Z',
            'type': 'wash_charge',
          },
        ],
      );
    final service = WalletService(
      httpClient: client,
      baseUrlProvider: () => 'https://example.test',
      supabaseApiKeyProvider: () => 'anon',
      jwtProvider: () => 'jwt',
    );

    await service.refresh();

    expect(service.transactions.length, 2);
    expect(service.topUps.length, 1);
    expect(service.charges.length, 1);
    expect(service.transactions.first.kind, WalletTransactionKind.charge);
    expect(service.transactions.last.kind, WalletTransactionKind.topUp);
    expect(service.lastErrorMessage, isNull);
    expect(service.lastSyncedAt, isNotNull);
  });

  test('refresh stores error on non-2xx', () async {
    final client = _FakeClient()
      ..getResponse = const BackendHttpResponse(
        statusCode: 500,
        body: <String, dynamic>{'message': 'boom'},
      );
    final service = WalletService(
      httpClient: client,
      baseUrlProvider: () => 'https://example.test',
      supabaseApiKeyProvider: () => 'anon',
      jwtProvider: () => 'jwt',
    );

    await service.refresh();

    expect(service.transactions, isEmpty);
    expect(service.lastErrorMessage, contains('boom'));
  });

  test('refresh without jwt clears state', () async {
    final service = WalletService(
      httpClient: _FakeClient(),
      baseUrlProvider: () => 'https://example.test',
      supabaseApiKeyProvider: () => 'anon',
      jwtProvider: () => null,
    );

    await service.refresh();

    expect(service.transactions, isEmpty);
    expect(service.lastErrorMessage, isNull);
    expect(service.lastSyncedAt, isNull);
  });
}

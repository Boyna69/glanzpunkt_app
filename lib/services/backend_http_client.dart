import 'backend_http_client_stub.dart'
    if (dart.library.io) 'backend_http_client_io.dart';

class BackendHttpResponse {
  final int statusCode;
  final Object? body;

  const BackendHttpResponse({required this.statusCode, required this.body});
}

enum BackendHttpErrorKind { network, timeout, invalidResponse }

class BackendHttpException implements Exception {
  final BackendHttpErrorKind kind;
  final String message;

  const BackendHttpException({required this.kind, required this.message});
}

abstract class BackendHttpClient {
  Future<BackendHttpResponse> getJson(Uri uri, {Map<String, String>? headers});

  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  });
}

BackendHttpClient createBackendHttpClient({
  Map<String, String>? defaultHeaders,
}) => createBackendHttpClientImpl(defaultHeaders: defaultHeaders);

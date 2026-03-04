import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend_http_client.dart';

class IoBackendHttpClient implements BackendHttpClient {
  final HttpClient _client = HttpClient();
  final Map<String, String> _defaultHeaders;
  static const Duration _requestTimeout = Duration(seconds: 8);

  IoBackendHttpClient({Map<String, String>? defaultHeaders})
    : _defaultHeaders = Map<String, String>.unmodifiable(
        defaultHeaders ?? const <String, String>{},
      );

  @override
  Future<BackendHttpResponse> getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      final request = await _client.getUrl(uri).timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      _applyHeaders(request, headers);
      final response = await request.close().timeout(_requestTimeout);
      final responseText = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final body = _decodeBody(responseText);
      return BackendHttpResponse(statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.timeout,
        message: 'Timeout bei API-Anfrage.',
      );
    } on SocketException {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.network,
        message: 'Netzwerk nicht erreichbar.',
      );
    } on HttpException catch (e) {
      throw BackendHttpException(
        kind: BackendHttpErrorKind.network,
        message: 'HTTP-Fehler: ${e.message}',
      );
    }
  }

  @override
  Future<BackendHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    try {
      final request = await _client.postUrl(uri).timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      _applyHeaders(request, headers);
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_requestTimeout);
      final responseText = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final body = _decodeBody(responseText);
      return BackendHttpResponse(statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.timeout,
        message: 'Timeout bei API-Anfrage.',
      );
    } on SocketException {
      throw const BackendHttpException(
        kind: BackendHttpErrorKind.network,
        message: 'Netzwerk nicht erreichbar.',
      );
    } on HttpException catch (e) {
      throw BackendHttpException(
        kind: BackendHttpErrorKind.network,
        message: 'HTTP-Fehler: ${e.message}',
      );
    }
  }

  Object? _decodeBody(String bodyText) {
    if (bodyText.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(bodyText);
    if (decoded is Map<String, dynamic> || decoded is List) {
      return decoded;
    }
    throw const BackendHttpException(
      kind: BackendHttpErrorKind.invalidResponse,
      message: 'API-Response ist kein JSON-Objekt.',
    );
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    _defaultHeaders.forEach(request.headers.set);
    if (headers != null) {
      headers.forEach(request.headers.set);
    }
  }
}

BackendHttpClient createBackendHttpClientImpl({
  Map<String, String>? defaultHeaders,
}) => IoBackendHttpClient(defaultHeaders: defaultHeaders);

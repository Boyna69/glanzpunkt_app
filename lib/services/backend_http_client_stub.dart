import 'backend_http_client.dart';

BackendHttpClient createBackendHttpClientImpl({
  Map<String, String>? defaultHeaders,
}) {
  throw UnsupportedError(
    'HTTP backend is on this platform not supported in this build.',
  );
}

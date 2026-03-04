import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/services/backend_error_message_service.dart';
import 'package:glanzpunkt_app/services/wash_backend_gateway.dart';

void main() {
  test('start flow maps reserve boxUnavailable with reserve hint', () {
    const error = BackendGatewayException(
      code: BackendErrorCode.boxUnavailable,
      message: 'box_unavailable',
      operation: 'reserve',
    );
    final message = BackendErrorMessageService.mapForStartFlow(error);
    expect(message, contains('gerade belegt'));
  });

  test('start flow maps activate boxUnavailable with activation hint', () {
    const error = BackendGatewayException(
      code: BackendErrorCode.boxUnavailable,
      message: 'box_unavailable',
      operation: 'activate',
    );
    final message = BackendErrorMessageService.mapForStartFlow(error);
    expect(message, contains('Aktivierung'));
  });

  test('start flow maps unauthorized and backend unavailable', () {
    const unauthorized = BackendGatewayException(
      code: BackendErrorCode.unauthorized,
      message: 'unauthorized',
    );
    const unavailable = BackendGatewayException(
      code: BackendErrorCode.backendUnavailable,
      message: 'timeout',
    );

    expect(
      BackendErrorMessageService.mapForStartFlow(unauthorized),
      contains('neu einloggen'),
    );
    expect(
      BackendErrorMessageService.mapForStartFlow(unavailable),
      contains('nicht erreichbar'),
    );
  });

  test('unknown start flow error falls back to original message', () {
    const error = BackendGatewayException(
      code: BackendErrorCode.unknown,
      message: 'custom backend failure',
    );
    final message = BackendErrorMessageService.mapForStartFlow(error);
    expect(message, 'custom backend failure');
  });
}

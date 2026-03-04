import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/box.dart';
import 'package:glanzpunkt_app/services/wash_backend_gateway.dart';

void main() {
  test(
    'mock gateway throws invalid_signature for invalid QR signature',
    () async {
      final gateway = MockWashBackendGateway();

      expect(
        () => gateway.reserveBox(
          const ReserveBoxRequest(
            boxNumber: 3,
            amountEuro: 10,
            identificationMethod: BoxIdentificationMethod.qr,
            boxSignature: 'invalid',
          ),
        ),
        throwsA(
          isA<BackendGatewayException>().having(
            (e) => e.code,
            'code',
            BackendErrorCode.invalidSignature,
          ),
        ),
      );
    },
  );

  test('mock gateway returns active status after activation', () async {
    final gateway = MockWashBackendGateway();
    final reserve = await gateway.reserveBox(
      const ReserveBoxRequest(
        boxNumber: 3,
        amountEuro: 5,
        identificationMethod: BoxIdentificationMethod.qr,
        boxSignature: 'ok',
      ),
    );

    await gateway.activateBox(
      ActivateBoxRequest(reservationToken: reserve.reservationToken),
    );

    final status = await gateway.getBoxStatus(3);
    expect(status.state, BoxState.active);
    expect(status.remainingMinutes, isNotNull);
    expect(status.remainingMinutes! >= 9, isTrue);
  });

  test('mock gateway stopBoxSession switches active box to cleaning', () async {
    final gateway = MockWashBackendGateway();
    final reserve = await gateway.reserveBox(
      const ReserveBoxRequest(
        boxNumber: 4,
        amountEuro: 5,
        identificationMethod: BoxIdentificationMethod.manual,
      ),
    );
    await gateway.activateBox(
      ActivateBoxRequest(reservationToken: reserve.reservationToken),
    );

    await gateway.stopBoxSession(4);
    final status = await gateway.getBoxStatus(4);
    expect(status.state, BoxState.cleaning);
    expect(status.remainingMinutes, isNotNull);
    expect(status.remainingMinutes! > 0, isTrue);
  });
}

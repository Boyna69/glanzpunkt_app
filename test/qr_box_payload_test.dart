import 'package:flutter_test/flutter_test.dart';
import 'package:glanzpunkt_app/models/qr_box_payload.dart';

void main() {
  test('parses plain numeric box id', () {
    final payload = QrBoxPayload.parse('3');
    expect(payload.boxNumber, 3);
    expect(payload.signature, isNull);
  });

  test('parses glanzpunkt URI payload with signature', () {
    final payload = QrBoxPayload.parse('glanzpunkt://box?box=5&sig=abc123');
    expect(payload.boxNumber, 5);
    expect(payload.signature, 'abc123');
  });

  test('throws on invalid payload', () {
    expect(
      () => QrBoxPayload.parse('https://example.com'),
      throwsFormatException,
    );
  });
}

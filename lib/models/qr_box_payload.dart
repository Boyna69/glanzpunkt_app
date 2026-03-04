class QrBoxPayload {
  final int boxNumber;
  final String? signature;

  const QrBoxPayload({required this.boxNumber, this.signature});

  static QrBoxPayload parse(String rawInput) {
    final raw = rawInput.trim();
    if (raw.isEmpty) {
      throw const FormatException('Leerer QR-Inhalt');
    }

    final justNumber = int.tryParse(raw);
    if (justNumber != null) {
      return QrBoxPayload(boxNumber: justNumber);
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'glanzpunkt') {
      throw const FormatException('Ungueltiges QR-Format');
    }

    final boxRaw = uri.queryParameters['box'];
    final boxNumber = int.tryParse(boxRaw ?? '');
    if (boxNumber == null) {
      throw const FormatException('QR enthaelt keine gueltige Box');
    }

    return QrBoxPayload(
      boxNumber: boxNumber,
      signature: uri.queryParameters['sig'],
    );
  }
}

// ISO 15765-2 парсер. Не блокирует кадры с байтом 7F внутри данных.
// Отсекает только реальный Negative Response (7F + код сервиса в начале).
class ObdParser {
  static List<int>? extractBytes(String resp, String expectedPrefix) {
    final upper = resp.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('ERROR') ||
        upper.contains('UNABLE') ||
        upper.contains('STOPPED') ||
        upper.contains('?')) {
      return null;
    }

    int? expectedTotalLen;
    final lines = upper.split(RegExp(r'[\r\n]+'));
    final cleanHexBuf = StringBuffer();

    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      var line = lines[lineIdx].trim();
      if (line.isEmpty || line.startsWith('SEARCHING')) continue;

      // 12-битный заголовок длины ISO-TP («01A», «024») идёт отдельной первой строкой
      if (lineIdx == 0 &&
          line.length == 3 &&
          RegExp(r'^[0-9A-F]{3}$').hasMatch(line)) {
        expectedTotalLen = int.tryParse(line, radix: 16);
        continue;
      }

      // Отрезаем префикс номера кадра ISO-TP ("0:", "1:", "2:", ...)
      final colonIdx = line.indexOf(':');
      if (colonIdx != -1 && colonIdx <= 2) {
        line = line.substring(colonIdx + 1).trim();
      }

      // Отрезаем CAN-ID заголовки вида 7E8
      if (line.startsWith('7E8')) {
        line = line.substring(3).trim();
      }

      final hexOnly = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      cleanHexBuf.write(hexOnly);
    }

    final clean = cleanHexBuf.toString();
    if (clean.isEmpty) return null;

    // Проверка Negative Response только в начале ответа
    final pref = expectedPrefix.toUpperCase();
    if (pref.length >= 2) {
      final respServiceByte = int.tryParse(pref.substring(0, 2), radix: 16);
      if (respServiceByte != null && respServiceByte >= 0x40) {
        final reqServiceHex = (respServiceByte - 0x40)
            .toRadixString(16)
            .padLeft(2, '0')
            .toUpperCase();
        if (clean.startsWith('7F$reqServiceHex') ||
            clean.startsWith('037F$reqServiceHex')) {
          return null;
        }
      }
    }

    final idx = clean.indexOf(pref);
    if (idx == -1) return null;

    final hexData = clean.substring(idx + pref.length);
    final bytes = <int>[];
    for (int i = 0; i + 1 < hexData.length; i += 2) {
      final b = int.tryParse(hexData.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }

    final payloadMaxLen = expectedTotalLen != null
        ? (expectedTotalLen - (pref.length ~/ 2))
        : null;
    if (payloadMaxLen != null &&
        payloadMaxLen > 0 &&
        bytes.length > payloadMaxLen) {
      return bytes.sublist(0, payloadMaxLen);
    }
    return bytes;
  }

  static int? tryParseMode06Counter(String resp, String expectedPrefix) {
    final b = extractBytes(resp, expectedPrefix);
    if (b == null || b.length < 4) return null;
    if (b.length >= 5) return (b[3] * 256) + b[4];
    return (b[2] * 256) + b[3];
  }
}

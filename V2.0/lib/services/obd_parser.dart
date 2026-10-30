// lib/services/obd_parser.dart — парсер ответов ELM327 → байты payload.
//
// extractBytes / tryParseMode06Counter — проверенный боем код рабочего проекта
// lada_vesta_scanner (v1.1.4-экстрактор), подтверждён полем: корректно собирает
// и одно-, и многокадровые ответы (0904 VIN: строка длины + '0:'/'1:' кадры).
//
// В V2.0 удалены мёртвые классы IsoTpAssembler/ParameterConfig/cleanResponse —
// их никто не вызывал, а декодирование значений выполняет EcuParameter.decode()
// из lib/data/models (схема m86_uds.json с width/multiplier/addend/offset).

/// Единый тип «отправка ELM-команды» для сервисов, вынесенных из провайдера.
typedef ElmSendCommand = Future<String> Function(String cmd,
    {int timeoutMs, int postDelayMs});

class ObdParser {
  /// Единственный путь формирования запроса ReadDataByIdentifier (service 0x22):
  /// DID — ЧИСЛО, команда = '22' + DID_HI + DID_LO.
  /// DID 0x0001 -> '220001'; DID 0x2001 -> '222001' — это РАЗНЫЕ DID!
  static String buildReadDidCommand(int did) =>
      '22${(did & 0xFFFF).toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Ожидаемый префикс положительного ответа: '62' + эхо DID (0x0001 -> '620001').
  static String positiveDidPrefix(int did) =>
      '62${(did & 0xFFFF).toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Проверенный ISO 15765-2 экстрактор байтов из ответа ELM327.
  /// [expectedPrefix] — префикс ответа, например '410C' или '62F190'.
  /// Возвращает payload ПОСЛЕ префикса либо null (ошибка/NRC/нет данных).
  static List<int>? extractBytes(String resp, String expectedPrefix) {
    final upper = resp.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('ERROR') ||
        upper.contains('UNABLE') ||
        upper.contains('STOPPED') ||
        upper.contains('ERR:') ||
        upper.contains('?')) {
      return null;
    }

    int? expectedTotalLen;
    final lines = upper.split(RegExp(r'[\r\n|]+'));
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

  /// Печатаемые ASCII-символы payload (32..126) с обрезкой пробелов:
  /// паспортные DID М86 (0904/220091/220097/22009A) отдают текст с паддингом.
  /// null — нечего декодировать (нет ответа/только паддинг).
  static String? decodeAscii(List<int>? payload) {
    if (payload == null || payload.isEmpty) return null;
    final chars = payload
        .where((b) => b >= 32 && b <= 126)
        .map(String.fromCharCode)
        .join()
        .trim();
    return chars.isEmpty ? null : chars;
  }

  /// Счётчик Mode 06 (пропуски/мониторы): двухбайтовое значение с учётом
  /// формата ответа (с MID-байтом или без).
  static int? tryParseMode06Counter(String resp, String expectedPrefix) {
    final b = extractBytes(resp, expectedPrefix);
    if (b == null || b.length < 4) return null;
    if (b.length >= 5) return (b[3] * 256) + b[4];
    return (b[2] * 256) + b[3];
  }
}

class ObdParser {
  /// Проверяет, является ли ответ отрицательным (NRC - Negative Response Code)
  static bool isNegativeResponse(String resp) {
    final upper = resp.toUpperCase().trim();
    if (upper.isEmpty || 
        upper.contains('NO DATA') || 
        upper.contains('ERROR') || 
        upper.contains('UNABLE') || 
        upper.contains('?')) {
      return true;
    }
    final clean = upper.replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (clean.isEmpty) return true;
    // 7F - маркер ошибки протокола (например, 7F 21 11)
    return RegExp(r'^(03)?7F[0-9A-F]{4}').hasMatch(clean);
  }

  /// Извлекает чистые байты из ответа ELM327, игнорируя эхо, заголовки и мусор.
  /// expectedPrefix - ожидаемый ответ (например, "620001" на запрос "220001")
  static List<int>? extractBytes(String resp, String expectedPrefix) {
    if (isNegativeResponse(resp)) return null;

    final lines = resp.toUpperCase().split(RegExp(r'[\r\n]+'));
    final cleanHexBuf = StringBuffer();

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('SEARCHING')) continue;
      
      // Очищаем от CAN-заголовков (например, 7E8 для двигателя)
      if (line.startsWith('7E8')) {
        line = line.substring(3).trim();
      }
      
      // Очищаем от нумерации строк многокадровых сообщений (0:, 1: и т.д.)
      final colonIdx = line.indexOf(':');
      if (colonIdx != -1 && colonIdx <= 2) {
        line = line.substring(colonIdx + 1).trim();
      }

      // Оставляем только HEX-символы
      final hexOnly = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      cleanHexBuf.write(hexOnly);
    }

    final clean = cleanHexBuf.toString();
    final pref = expectedPrefix.toUpperCase();
    
    // Ищем начало полезной нагрузки
    final idx = clean.indexOf(pref);
    if (idx == -1) return null; 

    // Достаем всё, что идет после префикса
    final hexData = clean.substring(idx + pref.length);
    final bytes = <int>[];
    
    // Переводим текст в массив байтов
    for (int i = 0; i + 1 < hexData.length; i += 2) {
      final b = int.tryParse(hexData.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }
    
    return bytes;
  }
}
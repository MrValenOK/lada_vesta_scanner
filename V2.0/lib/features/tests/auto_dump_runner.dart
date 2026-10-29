// lib/features/tests/auto_dump_runner.dart — цепочка АВТО-ДАМП М86.
// Вынесено из tests_screen.dart (лимит 400 строк/файл). Цепочка и формат
// ответов — по спеке заказчика; 0142 исключён (не поддерживается, 7F0112).
class AutoDumpRunner {
  AutoDumpRunner({required this.send, required this.log});

  /// Отправка команды (провайдерный sendCommandForSniffer).
  final Future<String> Function(String cmd, {int timeoutMs, int postDelayMs})
      send;
  final void Function(String line) log;

  Future<void> run() async {
    // 1. UDS extended session (1003)
    await _step('1003', 1200, 120);
    await _step('3E00', 800, 100);

    // 2. Заводские UDS DID (Сервис 22) - только в сессии 1003
    for (final did in [
      '220090', '220091', '220097', '22009A', // Инфо
      '220001', '220002', '220003', '220005', // Телеметрия
    ]) {
      await _step('3E00', 800, 100);
      await _step(did, 2000, 250);
    }

    // 3. Вернуться в default session
    await _step('1001', 1200, 120);

    // 4. Стандартный OBD-II (Mode 01, 03, 09)
    for (final cmd in [
      '0904', '0100', '010C', '010D',
      '0104', '0105', '0106', '0107',
      '0111', '0114', '0115',
    ]) {
      await _step(cmd, 2000, 250);
    }

    // 5. Тесты и пропуски (Mode 06)
    for (final cmd in ['0600', '0601', '0621']) {
      await _step(cmd, 2000, 250);
    }
  }

  Future<void> _step(String cmd, int timeoutMs, int postDelayMs) async {
    final r = await send(cmd, timeoutMs: timeoutMs, postDelayMs: postDelayMs);
    final nrc = decodeNrc(r);
    log('→ $cmd\n← ${r.replaceAll('\n', ' | ')}${nrc.isNotEmpty ? "  [$nrc]" : ""}');
  }

  /// NRC-расшифровка (таблица из спеки заказчика).
  static String decodeNrc(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\s|]+'), '').toUpperCase();
    final m = RegExp(r'(03)?7F([0-9A-F]{2})([0-9A-F]{2})').firstMatch(clean);
    if (m == null) return '';
    switch (m.group(3)!) {
      case '11': return 'NRC 11 ServiceNotSupported';
      case '12': return 'NRC 12 SubFunctionNotSupported/InvalidFormat';
      case '13': return 'NRC 13 IncorrectMessageLength';
      case '22': return 'NRC 22 ConditionsNotCorrect';
      case '31': return 'NRC 31 RequestOutOfRange (DID не существует)';
      case '33': return 'NRC 33 SecurityAccessDenied';
      case '7E': return 'NRC 7E SubFunctionNotSupportedInActiveSession';
      case '7F': return 'NRC 7F ServiceNotSupportedInActiveSession (нужна другая сессия)';
      default:   return 'NRC 0x${m.group(3)}';
    }
  }
}

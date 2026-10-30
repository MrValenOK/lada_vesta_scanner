// lib/features/tests/auto_dump_runner.dart — цепочка АВТО-ДАМП М86.
// Вынесено из tests_screen.dart (лимит 400 строк/файл). Цепочка и формат
// ответов — по спеке заказчика; 0142 исключён (не поддерживается, 7F0112);
// вендорские 2200xx читаются в DEFAULT SESSION (после 1001), не в extended.
class AutoDumpRunner {
  AutoDumpRunner({required this.send, required this.log});

  /// Отправка команды (провайдерный sendCommandForSniffer).
  final Future<String> Function(String cmd, {int timeoutMs, int postDelayMs})
      send;
  final void Function(String line) log;

  Future<void> run() async {
    // 1. UDS extended session
    await _step('1003', 1200, 120);
    await _step('3E00', 800, 100);

    // 2. Паспортные DID (проверка сервиса 0x22 в UDS)
    for (final did in ['22F190', '22F187', '22F188', '22F191', '22F195']) {
      await _step(did, 2000, 250);
    }

    // 3. Негативные кандидаты 0401 (перепроверка NRC по живому дампу)
    for (final did in ['220401', '220402', '220403']) {
      await _step('3E00', 800, 100);
      await _step(did, 2000, 250);
    }

    // 4. Вернуться в default session
    await _step('1001', 1200, 120);

    // 5. Вендорские пакеты М86 — ЧИТАЮТСЯ ТОЛЬКО В DEFAULT SESSION (контракт
    // 2200xx): 220001 (64 Б — тот же блок, что в опросе), 220002 (52 Б),
    // 220003 (25 Б), 220005 (80 Б). Прежние 222001..003 = DID 0x2001.. были
    // мёртвыми (7F 22 12) и давали ложную картину.
    for (final did in ['220001', '220002', '220003', '220005']) {
      await _step(did, 2000, 250);
    }

    // 6. OBD Mode 09 / Mode 01 (0142 исключён: 7F0112)
    for (final cmd in [
      '0904', '0100', '010C', '010D',
      '0104', '0105', '0106', '0107',
      '0111', '0114', '0115',
    ]) {
      await _step(cmd, 2000, 250);
    }

    // 7. Проверка KWP в default session
    await _step('1001', 1200, 120);
    await _step('2101', 2000, 250);
    await _step('2102', 2000, 250);
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
      case '12': return 'NRC 12 SubFunctionNotSupported';
      case '13': return 'NRC 13 IncorrectMessageLengthOrInvalidFormat';
      case '22': return 'NRC 22 ConditionsNotCorrect';
      case '31': return 'NRC 31 RequestOutOfRange (DID не существует)';
      case '33': return 'NRC 33 SecurityAccessDenied';
      case '7E': return 'NRC 7E SubFunctionNotSupportedInActiveSession';
      case '7F': return 'NRC 7F ServiceNotSupportedInActiveSession (нужна другая сессия)';
      default:   return 'NRC 0x${m.group(3)}';
    }
  }
}

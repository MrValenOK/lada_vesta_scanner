// lib/services/ecu_detector.dart — определение ЭБУ при подключении: калибровка
// 0904 (multi-frame → 2000/250), детекция протокола KWP (1081) / UDS (1003),
// тип ЭБУ по строке калибровки и паспорт ЭСУД (220091/220097/22009A — читаются
// в DEFAULT SESSION; 0x0090 VIN-подобный не читаем). Возвращает данные, не
// состояние. Вынесено из obd_provider (правило лимита 400 строк, AGENTS).
import 'bluetooth_service.dart';
import 'obd_parser.dart';

/// Результат определения: паспорт, протокол, тип (кэша нет — каждый коннект
/// читает заново, чтобы не показывать устаревшее).
class EcuDetection {
  final String ecuId;
  final bool isUds;
  final String ecuType;

  /// Паспорт ЭСУД: только реально прочитанное. Ключи:
  /// part — 220091 (номер применения), model — 220097 (модель/ДВС),
  /// sw_short — 22009A (укороченный ID ПО). Пусто — данные не ответили.
  final Map<String, String> passport;

  const EcuDetection({
    required this.ecuId,
    required this.isUds,
    required this.ecuType,
    this.passport = const {},
  });
}

class EcuDetector {
  /// 0904 → детекция 1081/1003.
  /// 2200xx (блок 220001) читаются в DEFAULT SESSION — из extended выходим
  /// сразу после детекции; 1003 перед чтением блоков НЕ отправлять.
  /// [fallbackEcuId] — что показать, если 0904 не ответил (прежнее значение).
  static Future<EcuDetection> detect(BluetoothService bt,
      {String fallbackEcuId = '---'}) async {
    String ecuId = fallbackEcuId;
    final id = ObdParser.decodeAscii(ObdParser.extractBytes(
        await bt.sendCommand('0904', timeoutMs: 2000, postDelayMs: 250),
        '4904'));
    if (id != null) ecuId = id;

    // Протокол: KWP (1081) или UDS (1003) — только детекция.
    bool isUds = false;
    final r81 = await bt.sendCommand('1081', timeoutMs: 800);
    if (!r81.replaceAll(' ', '').contains('5081')) {
      final r03 = await bt.sendCommand('1003', timeoutMs: 800);
      if (r03.replaceAll(' ', '').contains('5003')) isUds = true;
    }
    if (isUds) await bt.sendCommand('1001', timeoutMs: 800);

    // Паспорт ЭСУД — в DEFAULT SESSION (уже после 1001).
    // 0x0090 (VIN-подобный) НЕ читаем и не показываем — решение M1.
    final passport = <String, String>{};
    final part = await _readText(bt, 0x0091);
    if (part != null) passport['part'] = part;
    final model = await _readText(bt, 0x0097);
    if (model != null) passport['model'] = model;
    final swShort = await _readText(bt, 0x009A);
    if (swShort != null) passport['sw_short'] = swShort;

    return EcuDetection(
        ecuId: ecuId,
        isUds: isUds,
        ecuType: detectEcuType(ecuId),
        passport: passport);
  }

  /// Текстовый DID: запрос — только через buildReadDidCommand (контракт v2);
  /// ответ с паддингом → decodeAscii. null — не ответил/пусто.
  static Future<String?> _readText(BluetoothService bt, int did) async {
    final raw = await bt.sendCommand(ObdParser.buildReadDidCommand(did),
        timeoutMs: 2000, postDelayMs: 250);
    return ObdParser.decodeAscii(
        ObdParser.extractBytes(raw, ObdParser.positiveDidPrefix(did)));
  }

  /// Тип ЭБУ по строке калибровки (эвристика; «ЭБУ не определён» — честно).
  static String detectEcuType(String id) {
    final upper = id.toUpperCase();
    if (upper.contains('I785')) return 'Итэлма М86 (1.8л · UDS)';
    if (upper.contains('765') ||
        upper.contains('M86') ||
        upper.contains('I86')) {
      return 'Итэлма М86 (1.6л · UDS)';
    }
    if (upper.contains('M74')) return 'Итэлма М74';
    if (upper.contains('ME17')) return 'Bosch ME17.9.7';
    return 'ЭБУ не определён';
  }
}

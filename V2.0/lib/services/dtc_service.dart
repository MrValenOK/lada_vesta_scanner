// lib/services/dtc_service.dart — чтение/разбор DTC (Mode 03/07 + UDS 19 02 FF)
// и стоп-кадр (Mode 02). Send-функция — ElmSendCommand: сервис тестируем
// подменой транспорта (fake send), конкретный BluetoothService не требуется.
// Вынесено из obd_provider (лимит 400 строк/файл, AGENTS V2.0).
import 'obd_parser.dart';

class DtcService {
  DtcService._();

  /// Чтение кодов: Mode 03 (зафиксированные) + 07 (pending) + UDS 19 02 FF
  /// (все по маске статуса FF; если сервис не поддержан — вклад пуст, без
  /// ошибок). Возвращает уникальные коды вида 'P0300' (порядок появления).
  static Future<List<String>> readCodes(ElmSendCommand send) async {
    final codes = <String>{};
    for (final mode in ['03', '07']) {
      final resp = await send(mode, timeoutMs: 2000);
      final b = ObdParser.extractBytes(resp, mode == '03' ? '43' : '47');
      if (b == null || b.length < 3) continue;
      final cnt = b[0];
      final usable = (cnt > 0 && cnt <= 40 && b.length >= 1 + cnt * 2)
          ? cnt
          : (b.length - 1) ~/ 2;
      for (int i = 0; i < usable; i++) {
        final code = dtcFromBytes(b[1 + i * 2], b[2 + i * 2]);
        if (code != null) codes.add(code);
      }
    }
    final u19 = await send('1902FF', timeoutMs: 2000);
    codes.addAll(parseDtc19(u19));
    return codes.toList();
  }

  /// Разбор ответа UDS ReadDTCInformation 19 02 FF (ISO 14229):
  /// `59 02 <маска доступности> [DTC(3 байта) + статус]×N`.
  /// Защита от неоднозначной структуры: если размер не «1 + N×4» — пусто
  /// (лучше без кодов, чем выдуманные). Нулевые DTC пропускаются.
  static List<String> parseDtc19(String resp) {
    final b = ObdParser.extractBytes(resp, '5902');
    if (b == null || b.length < 5 || (b.length - 1) % 4 != 0) return const [];
    final out = <String>[];
    for (var i = 1; i + 3 < b.length; i += 4) {
      final code = dtcFromBytes(b[i], b[i + 1]);
      if (code != null) out.add(code);
    }
    return out;
  }

  /// Два байта DTC → 'P0300' (кодировка ISO 15031: P/C/B/U + 4 hex-цифры).
  /// null — нулевой DTC (пустой слот).
  static String? dtcFromBytes(int b1, int b2) {
    if (b1 == 0 && b2 == 0) return null;
    const types = ['P', 'C', 'B', 'U'];
    return '${types[(b1 >> 6) & 0x03]}${(b1 >> 4) & 0x03}'
        '${(b1 & 0x0F).toRadixString(16).toUpperCase()}'
        '${((b2 >> 4) & 0x0F).toRadixString(16).toUpperCase()}'
        '${(b2 & 0x0F).toRadixString(16).toUpperCase()}';
  }

  /// Стоп-кадр (Mode 02): фиксированные PID на момент появления кода.
  /// Нет ответа по PID — ключ просто отсутствует (никаких заглушек).
  static Future<Map<String, double?>> readFreezeFrame(
      ElmSendCommand send, String code) async {
    final out = <String, double?>{};
    Future<List<int>?> ask(String cmd, String prefix) async =>
        ObdParser.extractBytes(await send(cmd, timeoutMs: 900), prefix);

    final rpm = await ask('020C00', '420C');
    if (rpm != null && rpm.length >= 3) {
      out['Обороты, об/мин'] = ((rpm[1] * 256) + rpm[2]) / 4;
    }
    final ect = await ask('020500', '4205');
    if (ect != null && ect.length >= 2) out['Темп. ОЖ, °C'] = (ect[1] - 40).toDouble();
    final map = await ask('020B00', '420B');
    if (map != null && map.length >= 2) out['ДАД, кПа'] = map[1].toDouble();
    final stft = await ask('020600', '4206');
    if (stft != null && stft.length >= 2) {
      out['STFT, %'] = (stft[1] - 128) * 100.0 / 128.0;
    }
    final ltft = await ask('020700', '4207');
    if (ltft != null && ltft.length >= 2) {
      out['LTFT, %'] = (ltft[1] - 128) * 100.0 / 128.0;
    }
    final spd = await ask('020D00', '420D');
    if (spd != null && spd.length >= 2) out['Скорость, км/ч'] = spd[1].toDouble();
    final volt = await ask('024200', '4242');
    if (volt != null && volt.length >= 3) {
      out['Бортсеть, В'] = ((volt[1] * 256) + volt[2]) / 1000.0;
    }
    return out;
  }
}

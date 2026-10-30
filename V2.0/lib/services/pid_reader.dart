// lib/services/pid_reader.dart — чтение Mode 01 PID и ATRV в цикле опроса.
// П1 (отзывчивость): ядро каждого цикла — ATRV+010C (пост-пауза 50 мс),
// прочие PID — строго по одному за цикл (round-robin, [auxOrder]).
// Проверки отмены (остановка опроса) и пороги валидности — как прежде.
import 'obd_parser.dart';

class PidReader {
  PidReader({required this.send});

  final ElmSendCommand send;

  /// Пост-пауза ядра цикла (ATRV/010C): 40–60 мс по плану П1 (был дефолт 120).
  static const int corePostDelayMs = 50;

  static void pushTrace(
      List<double> trace, Map<String, double> d, String key, double v) {
    d[key] = v;
    trace.add(v);
    if (trace.length > 80) trace.removeAt(0);
  }

  /// Ядро каждого цикла: ATRV + 010C.
  /// [onRpm] вызывается ТОЛЬКО когда 010C распарсен в этом цикле (для сверки).
  /// Возвращает true, если был хотя бы один полезный ответ (контроль живости).
  Future<bool> readCoreInto(
    Map<String, double> d, {
    bool Function()? isCancelled,
    void Function(double rpm)? onRpm,
  }) async {
    var gotAny = false;

    // Бортсеть (ATRV)
    final mV = RegExp(r'(\d+[.,]\d+)').firstMatch(
        await send('ATRV', timeoutMs: 500, postDelayMs: corePostDelayMs));
    final v =
        mV == null ? null : double.tryParse(mV.group(1)!.replaceAll(',', '.'));
    if (v != null && v > 4.5 && v < 18.5) {
      d['volt'] = v;
      if (d['min_volt'] == null || v < d['min_volt']!) d['min_volt'] = v;
      gotAny = true;
    }
    if (cancelled(isCancelled)) return gotAny;

    // Обороты: СТРОГО (A*256+B)/4
    final bRpm = ObdParser.extractBytes(
        await send('010C', timeoutMs: 600, postDelayMs: corePostDelayMs),
        '410C');
    if (bRpm != null && bRpm.length >= 2) {
      d['rpm'] = ((bRpm[0] * 256) + bRpm[1]) / 4;
      onRpm?.call(d['rpm']!);
      gotAny = true;
    }
    return gotAny;
  }

  /// Порядок «прочих» PID (команда, префикс ответа): ТОЖ → ДЗ → ДК1 → ДК2 →
  /// скорость → нагрузка → IAT → STFT → LTFT. Ровно один PID за цикл.
  static const List<(String, String)> auxOrder = [
    ('0105', '4105'),
    ('0111', '4111'),
    ('0114', '4114'),
    ('0115', '4115'),
    ('010D', '410D'),
    ('0104', '4104'),
    ('010F', '410F'),
    ('0106', '4106'),
    ('0107', '4107'),
  ];

  /// Один «прочий» PID за цикл: slot — номер цикла, круг по [auxOrder].
  /// Трассы осциллографа (0114/0115) пополняются в своём слоте.
  /// true — PID распарсен в этом цикле (пороги валидности — как прежде).
  Future<bool> readAuxInto(
    int slot,
    Map<String, double> d,
    List<double> t1,
    List<double> t2,
  ) async {
    final (cmd, prefix) = auxOrder[slot % auxOrder.length];
    final p = ObdParser.extractBytes(await send(cmd, timeoutMs: 600), prefix);
    if (p == null || p.isEmpty) return false;

    if (cmd == '0105') {
      if (p[0] <= 20 || p[0] >= 170) return false;
      d['ect'] = (p[0] - 40).toDouble();
    } else if (cmd == '0111') {
      d['tps'] = p[0] * 100.0 / 255.0;
    } else if (cmd == '0114') {
      pushTrace(t1, d, 'udk', p[0] / 200.0);
    } else if (cmd == '0115') {
      pushTrace(t2, d, 'ddk', p[0] / 200.0);
    } else if (cmd == '010D') {
      d['speed'] = p[0].toDouble();
    } else if (cmd == '0104') {
      d['load'] = p[0] * 100.0 / 255.0;
    } else if (cmd == '010F') {
      d['iat'] = (p[0] - 40).toDouble();
    } else if (cmd == '0106') {
      d['stft'] = (p[0] - 128) * 100.0 / 128.0;
    } else if (cmd == '0107') {
      d['ltft'] = (p[0] - 128) * 100.0 / 128.0;
    } else {
      return false;
    }
    return true;
  }

  static bool cancelled(bool Function()? isCancelled) =>
      isCancelled != null && isCancelled();
}

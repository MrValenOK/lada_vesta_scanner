// lib/services/m86_block_reader.dart — чтение блока DID 220001 и оценка сверки.
// Вынесено из obd_provider (лимит 400 строк). Единый путь: числовой DID →
// ObdParser.buildReadDidCommand → validateDidSample; отказ НЕ обнуляет значения.
import '../data/models/ecu_profile.dart';
import 'obd_parser.dart';
import 'uds_sample.dart';

/// Результат одного чтения блока (для пайплайна и журнала).
class BlockReadResult {
  final String raw; // сырой ответ ELM (для raw-снапшота)
  final DidSample sample; // проверенный сэмпл (accepted/rejectReason/flags)
  final double? udsRpm; // uds_rpm из принятых DATA (для три-стейт сверки)

  BlockReadResult({required this.raw, required this.sample, this.udsRpm});
}

/// Чтение блока из профиля: числовой DID, валидаторы, последний принятый сэмпл.
class M86BlockReader {
  M86BlockReader({required this.send, required this.block});

  final ElmSendCommand send;
  final EcuRequestBlock block;

  List<int>? _lastAccepted;
  int rejects = 0; // подряд отклонённых (для журнала без спама)

  /// Всего принятых/отклонённых пакетов за сессию (для ИИ-снапшота, П6).
  int accepted = 0;
  int rejected = 0;

  Future<BlockReadResult> read() async {
    final raw = await send(ObdParser.buildReadDidCommand(block.did),
        timeoutMs: 2000, postDelayMs: 250);
    final payload =
        ObdParser.extractBytes(raw, ObdParser.positiveDidPrefix(block.did));
    final sample = validateDidSample(payload, block.validators,
        previousAccepted: _lastAccepted);
    if (sample.accepted) {
      _lastAccepted = sample.data;
      rejects = 0;
      accepted++;
    } else {
      rejects++;
      rejected++;
    }
    double? udsRpm;
    if (sample.accepted) {
      for (final p in block.parameters) {
        if (p.id == 'uds_rpm') {
          udsRpm = p.decode(sample.data!);
          break;
        }
      }
    }
    return BlockReadResult(raw: raw, sample: sample, udsRpm: udsRpm);
  }
}

/// Сверка 220001[4..5] ↔ 010C: три-стейт — 'ok'/'fail' только при реальной паре
/// в пределах 1 c, иначе 'none' («—»), без выдуманных true/false.
class M86BlockWatcher {
  DateTime? _rpmAt;
  double? _rpm;

  /// Интервал между двумя последними реальными 010C, мс (П1: контроль «≤1 с»
  /// по журналу; null — была меньше двух пар).
  int? lastRpmGapMs;

  double? get lastRpm => _rpm;

  /// Сброс пейсинга: старт опроса и цикл с чтением блока 220001 — интервал,
  /// включающий паузу/блок, не считается «лагом» 010C.
  void resetPacing() {
    _rpmAt = null;
    lastRpmGapMs = null;
  }

  /// Вызывать ТОЛЬКО когда 010C реально распарсен в текущем цикле.
  void noteEngineRpm(double rpm) {
    final now = DateTime.now();
    lastRpmGapMs =
        _rpmAt == null ? null : now.difference(_rpmAt!).inMilliseconds;
    _rpm = rpm;
    _rpmAt = now;
  }

  String evaluate(double? udsRpm) {
    final at = _rpmAt;
    final rpm = _rpm;
    if (udsRpm == null ||
        at == null ||
        rpm == null ||
        DateTime.now().difference(at).inMilliseconds > 1000) {
      return 'none';
    }
    return (udsRpm - rpm).abs() <= 50 ? 'ok' : 'fail';
  }
}

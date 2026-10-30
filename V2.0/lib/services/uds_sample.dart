// lib/services/uds_sample.dart — проверки качества сэмпла DID (H2) и слияние
// значений. Слой services: UI о байтах не знает; профиль задаёт валидаторы.
//
// Абсолютные проверки: длина DATA и якорь хвоста (из профиля).
// Ниббл-сдвиг хвоста vs предыдущий ПРИНЯТЫЙ кадр — только признак cf_suspect
// (эмпирический, дампы 2026-10-29; точная причина повреждения требует сырого
// транспортного трейса и не утверждается).
import '../data/models/ecu_parameter.dart';
import '../data/models/ecu_profile.dart';

/// Результат проверки одного ответа ReadDataByIdentifier.
class DidSample {
  final List<int>? data; // принятые DATA (null = отклонён)
  final List<String> flags; // len_ok/echo_ok/tail_ok/cf_suspect...
  final String? rejectReason; // понятная причина отказа для журнала/UI

  DidSample({this.data, List<String>? flags, this.rejectReason})
      : flags = flags ?? const [];

  bool get accepted => data != null;
}

/// Проверка ответа DID до декодирования.
/// [payload] — DATA после '62 DID_H DID_L' (null = нет ответа/NRC — не ноль!).
DidSample validateDidSample(
  List<int>? payload,
  DidValidators? validators, {
  List<int>? previousAccepted,
}) {
  if (payload == null || payload.isEmpty) {
    return DidSample(rejectReason: 'нет данных или NRC');
  }
  // Эхо DID гарантировано extractBytes: payload извлекается по префиксу '62' + DID.
  final flags = <String>['echo_ok'];

  final expected = validators?.expectedDataLengthBytes;
  if (expected != null && payload.length != expected) {
    return DidSample(
      flags: [...flags, 'len_fail'],
      rejectReason: 'длина=${payload.length} (ожидалось $expected)',
    );
  }
  flags.add('len_ok');

  final off = validators?.tailAnchorOffset;
  final anchor = validators?.tailAnchorBytes;
  if (off != null && anchor != null && off + anchor.length <= payload.length) {
    for (var i = 0; i < anchor.length; i++) {
      if (payload[off + i] != anchor[i]) {
        return DidSample(
          flags: [...flags, 'tail_fail'],
          rejectReason: 'якорь хвоста не сошёлся — сбой передачи кадра '
              '(обычное для бюджетных ELM327); последние значения сохранены',
        );
      }
    }
    flags.add('tail_ok');
  }

  if (previousAccepted != null && previousAccepted.length == payload.length) {
    if (nibbleShiftSuspect(previousAccepted, payload)) {
      flags.add('cf_suspect');
    }
  }
  return DidSample(data: payload, flags: flags);
}

/// Эмпирический детектор ниббл-сдвига хвоста: cur[k] совпадает с ниббл-сдвигом
/// prev (s=1..4) при совпадении >= [threshold] хвоста начиная с [fromByte].
bool nibbleShiftSuspect(
  List<int> prev,
  List<int> cur, {
  int fromByte = 16,
  double threshold = 0.7,
}) {
  if (prev.length <= fromByte || cur.length <= fromByte) return false;
  final nibs = (prev.length - fromByte) * 2;
  int nib(int i) {
    final b = prev[fromByte + (i >> 1)];
    return (i & 1) == 0 ? (b >> 4) & 0xF : b & 0xF;
  }

  for (var s = 1; s <= 4; s++) {
    var match = 0, comp = 0;
    for (var k = fromByte; k < cur.length; k++) {
      final i = (k - fromByte) * 2 + s;
      if (i + 1 >= nibs) break;
      comp++;
      if (((nib(i) << 4) | nib(i + 1)) == cur[k]) match++;
    }
    if (comp >= 20 && match / comp >= threshold) return true;
  }
  return false;
}

/// Слияние принятого сэмпла с текущими значениями.
/// Отклонённый сэмпл возвращает [current] без изменений — последние хорошие
/// значения не подменяются нулём; поле с недоступными байтами пропускается,
/// не ломая остальные.
Map<String, double> applySample(
  Map<String, double> current,
  DidSample sample,
  List<EcuParameter> params,
) {
  if (!sample.accepted) return current;
  final out = Map<String, double>.from(current);
  for (final p in params) {
    final v = p.decode(sample.data!);
    if (v != null) out[p.id] = v;
  }
  return out;
}

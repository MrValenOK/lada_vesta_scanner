// lib/core/spec_notes.dart — экспертный слой: справка по параметрам.
// Нормы — границы из M86Specs (ТИ 3100.25100.12056, табл. 2.4-01; прогретый
// ДВС на ХХ). Условия проверки и типичные причины отклонения — свод полевого
// опыта старой версии приложения (это «что проверить», а не диагноз).
// Слой core: только числа и текст, без UI и без байтов.
import 'constants.dart';

/// Диапазон нормы (границы — из M86Specs).
class SpecRange {
  final double min;
  final double max;
  const SpecRange(this.min, this.max);

  bool isOut(double v) => v < min || v > max;
}

/// Статус параметра относительно нормы.
/// none — нормы нет; pending — норма есть, но условие проверки не выполнено
/// (холодный ДВС, не ХХ, значения нет) — карточка не обвиняет и не хвалит.
enum SpecStatus { none, pending, ok, out }

class SpecCheck {
  final SpecStatus status;
  final String? rangeText;
  const SpecCheck(this.status, this.rangeText);
}

/// Справка по параметру: единицы, условие, причины, оговорки.
class SpecNote {
  final String title;
  final String unit;
  final String condition;
  final List<String> causes;
  final String? extraNorm; // второй режим (например, контроль на 3000 об/мин)
  final String? caveat; // оговорка (UDS-кандидат, расчётный параметр и т.п.)
  const SpecNote({
    required this.title,
    required this.unit,
    required this.condition,
    this.causes = const [],
    this.extraNorm,
    this.caveat,
  });
}

// Типичные причины отклонения коррекций (формулировки старой версии:
// бедная — «подсос воздуха, усталость ДК1, давление в рампе»;
// богатая — «клапан продувки адсорбера (EVAP), форсунки»).
const List<String> _causesTrim = [
  'в плюс (бедная смесь): подсос воздуха, усталость ДК1, давление в рампе',
  'в минус (богатая смесь): негерметичность клапана продувки адсорбера, форсунки',
];

/// Общая оговорка для значений из UDS-блока 220001 (кандидаты реверса).
const String _kUdsCaveat =
    'Источник UDS 220001; значение-кандидат: оценивайте вместе со статусом '
    'блока 220001 («сверка 010C» в карточке параметров М86).';

const Map<String, SpecNote> kSpecNotes = {
  'rpm': SpecNote(
    title: 'Обороты КВ (010C)',
    unit: 'об/мин',
    condition: 'Прогретый ДВС (ТОЖ ≥ 75 °C), ХХ, потребители выключены',
    causes: [
      'зажатые клапаны или смещение меток ГРМ (нестабильный/смещённый ХХ)',
      'подсос неучтённого воздуха: ресивер, кольца форсунок, вакуумные шланги',
      'дроссельный узел: загрязнение, адаптация нуля заслонки (P1545, P2176)',
    ],
    extraNorm: 'на 3000 об/мин: 3000 ± 100',
  ),
  'uds_rpm': SpecNote(
    title: 'Обороты (UDS @4..5)',
    unit: 'об/мин',
    condition: 'Прогретый ДВС, ХХ, потребители выключены',
    causes: [
      'зажатые клапаны или смещение меток ГРМ (нестабильный/смещённый ХХ)',
      'подсос неучтённого воздуха, дроссельный узел (P1545, P2176)',
    ],
    extraNorm: 'на 3000 об/мин: 3000 ± 100',
    caveat: _kUdsCaveat,
  ),
  'ect': SpecNote(
    title: 'Температура ОЖ (0105)',
    unit: '°C',
    condition: 'Прогретый ДВС, ХХ',
    causes: [
      'перегрев > 103 °C: включение 1-й скорости вентилятора (102 °C) и термостат',
    ],
    extraNorm: 'цель прогрева: 94–102 °C',
  ),
  'uds_ect': SpecNote(
    title: 'ТОЖ (UDS @3)',
    unit: '°C',
    condition: 'Прогретый ДВС, ХХ',
    causes: [
      'перегрев > 103 °C: включение 1-й скорости вентилятора (102 °C) и термостат',
    ],
    extraNorm: 'цель прогрева: 94–102 °C',
    caveat: _kUdsCaveat,
  ),
  'volt': SpecNote(
    title: 'Бортсеть (ATRV)',
    unit: 'В',
    condition: 'Работающий ДВС (обороты ≥ 700)',
    causes: ['генератор и клеммы: натяжение ремня, масса двигателя и кузова'],
    extraNorm: 'просадка при пуске: < 10.5 В — АКБ/массы; < 9.8 В — критично',
  ),
  'uds_volt': SpecNote(
    title: 'Бортсеть (UDS @1)',
    unit: 'В',
    condition: 'Работающий ДВС (обороты ≥ 700)',
    causes: ['генератор и клеммы: натяжение ремня, масса двигателя и кузова'],
    caveat: _kUdsCaveat,
  ),
  'stft': SpecNote(
    title: 'Коррекция STFT (0106)',
    unit: '%',
    condition: 'Прогретый ДВС, замкнутая петля (не прогрев, не ПХХ)',
    causes: _causesTrim,
    extraNorm: 'на ХХ адаптация строже: ± 2.5 %',
  ),
  'ltft': SpecNote(
    title: 'Коррекция LTFT (0107)',
    unit: '%',
    condition: 'Прогретый ДВС, замкнутая петля (не прогрев, не ПХХ)',
    causes: _causesTrim,
    extraNorm: 'на ХХ адаптация строже: ± 2.5 %',
  ),
  'uds_ltft': SpecNote(
    title: 'LTFT (UDS @27)',
    unit: '%',
    condition: 'Прогретый ДВС, замкнутая петля',
    causes: _causesTrim,
    extraNorm: 'на ХХ адаптация строже: ± 2.5 %',
    caveat: _kUdsCaveat,
  ),
  'load': SpecNote(
    title: 'Параметр нагрузки (0104)',
    unit: '%',
    condition: 'Прогретый ДВС, ХХ, потребители выключены',
    causes: [
      'завышено: подсос воздуха, смещение меток ГРМ, зажатые клапаны',
      'оценивайте вместе с ДАД и коррекциями: нагрузка рассчитывается ЭБУ по воздуху',
    ],
  ),
  'speed': SpecNote(
    title: 'Скорость (010D)',
    unit: 'км/ч',
    condition: '—',
    causes: [],
    caveat: 'Диагностической нормы нет — контроль по ситуации (движение/стоянка).',
  ),
  'map': SpecNote(
    title: 'ДАД (канал АЦП)',
    unit: 'В (ХХ)',
    condition: 'Прогретый ДВС, ХХ',
    causes: [
      'завышено: подсос воздуха, зажатые клапаны, смещение меток ГРМ',
      'занижено: утечка/подклинивание ДАД, цепь сигнала',
    ],
    caveat: 'По OBD (010B) ДАД ЭБУ не отдаёт («НЕТ ДАННЫХ»); норма канала — '
        'справочно, по ТИ (канал 1.56–1.66 В).',
  ),
  'air': SpecNote(
    title: 'Воздух (расчётный по 0104)',
    unit: 'кг/ч',
    condition: 'Прогретый ДВС, ХХ / 3000',
    causes: [
      'используется бортовым компьютером (БК): точность зависит от калибровки расхода',
    ],
    extraNorm: 'на 3000 об/мин: 27–35 кг/ч',
    caveat: 'Расчётное значение (по нагрузке), не расходомер: контроль по заправкам (П4).',
  ),
};

/// Норма в виде диапазона (из M86Specs) или null — нормы нет.
SpecRange? specRangeFor(String key) => switch (key) {
      'rpm' || 'uds_rpm' => const SpecRange(
          M86Specs.rpmIdle - M86Specs.rpmIdleTol,
          M86Specs.rpmIdle + M86Specs.rpmIdleTol),
      'ect' || 'uds_ect' =>
        const SpecRange(M86Specs.coolantMin, M86Specs.coolantMax),
      'volt' || 'uds_volt' => const SpecRange(M86Specs.vbusMin, M86Specs.vbusMax),
      'stft' =>
        const SpecRange(-100.0 * M86Specs.stftTol, 100.0 * M86Specs.stftTol),
      'ltft' || 'uds_ltft' =>
        const SpecRange(-100.0 * M86Specs.ltftTol, 100.0 * M86Specs.ltftTol),
      'load' => const SpecRange(M86Specs.loadIdleMin, M86Specs.loadIdleMax),
      'map' => const SpecRange(
          M86Specs.mapVoltageIdleMin, M86Specs.mapVoltageIdleMax),
      'air' =>
        const SpecRange(M86Specs.airFlowIdleMin, M86Specs.airFlowIdleMax),
      _ => null,
    };

/// '90–103' (целые без «.0») или null.
String? specRangeText(String key) {
  final r = specRangeFor(key);
  if (r == null) return null;
  return '${_fmtNum(r.min)}–${_fmtNum(r.max)}';
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Оценка параметра для карточки/строки: вне нормы — только если условие
/// проверки выполнено; «прогрев» и частичные нагрузки не считаются отказом.
SpecCheck checkSpec(String key, Map<String, double> d) {
  final rt = specRangeText(key);
  final range = specRangeFor(key);
  if (range == null) return const SpecCheck(SpecStatus.none, null);

  final ect = d['ect'];
  final tps = d['tps'];
  final rpm = d['rpm'];
  final warm = ect != null && ect >= M86Specs.coldEngineTempC;
  final idle = warm &&
      tps != null &&
      tps <= M86Specs.idleTpsMaxPct &&
      rpm != null &&
      rpm < M86Specs.trimZoneLowRpm;
  final running = rpm != null && rpm >= 700;

  double? v;
  switch (key) {
    case 'rpm':
    case 'uds_rpm':
      if (!idle) return SpecCheck(SpecStatus.pending, rt);
      v = d[key];
    case 'ect':
    case 'uds_ect':
      v = d[key];
      // Ниже нормы в прогреве — не приговор: ждём выхода на 90+.
      if (v == null || !warm || v < M86Specs.coolantMin) {
        return SpecCheck(SpecStatus.pending, rt);
      }
      return SpecCheck(
          v > M86Specs.coolantMax ? SpecStatus.out : SpecStatus.ok, rt);
    case 'volt':
    case 'uds_volt':
      if (!running) return SpecCheck(SpecStatus.pending, rt);
      v = d[key];
    case 'stft':
    case 'ltft':
    case 'uds_ltft':
      if (!(warm && running)) return SpecCheck(SpecStatus.pending, rt);
      v = d[key];
    case 'load':
      if (!idle) return SpecCheck(SpecStatus.pending, rt);
      v = d['load'];
    case 'map':
    case 'air':
      // Значения ЭБУ не отдаёт (010B) / величина расчётная — справка без оценки.
      return SpecCheck(SpecStatus.pending, rt);
    default:
      return const SpecCheck(SpecStatus.none, null);
  }
  if (v == null) return SpecCheck(SpecStatus.pending, rt);
  return SpecCheck(range.isOut(v) ? SpecStatus.out : SpecStatus.ok, rt);
}

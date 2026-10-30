// lib/services/ai_prompt_builder.dart — текст «ИИ-Снапшота» V2.0 (П6):
// инженерный промпт для внешнего ИИ-диагноста. Шесть разделов и жёсткое
// эпистемическое разделение:
//   [ФАКТ]    — Mode 01 + ATRV: измерено самим ЭБУ, сверяется с ТИ;
//   [КАНДИДАТ] — поля UDS 220001, реверс которых НЕ доказан (status профиля);
//   [TBD]      — структуры, которые отвечают, но не интерпретированы (0621).
// Нормы берутся из M86Specs через core/spec_notes.dart — тот же checkSpec,
// что и в карточках дашборда: промпт и UI не могут разойтись в оценке.
// «—» в промпте = значение не прочитано (НЕ ноль и НЕ выдумка).
// Слой services: не знает ни о UI, ни о байтах; принимает модели, отдаёт строку.
import '../core/constants.dart';
import '../core/spec_notes.dart';
import '../data/models/ecu_parameter.dart';
import 'ai_prompt_format.dart';
import 'ai_uds_section.dart';
import 'trim_matrix.dart';
import 'trip_calculator.dart';

/// Запись журнала для промпта: лёгкая копия NuanceEvent без зависимости
/// services → providers (слой services не импортирует провайдеры).
class AiJournalEntry {
  final String time;
  final String severity; // info | warning | critical
  final String title;
  final String description;

  const AiJournalEntry({
    required this.time,
    required this.severity,
    required this.title,
    required this.description,
  });
}

class AiPromptBuilder {
  AiPromptBuilder._();

  /// Последние записи журнала в промпте (требование П6 — 10).
  static const int journalLimit = 10;

  static String build({
    required Map<String, double> liveData,
    required String ecuId,
    required String ecuType,
    required bool isConnected,
    required bool isPolling,
    required bool isUds,
    required String udsStatus,
    required String rpmXcheck,
    required int udsAccepted,
    required int udsRejected,
    required List<EcuParameter> udsParams,
    required Map<String, String> passport,
    required double? minVoltage,
    required double? maxEct,
    required TrimMatrix matrix,
    required TripCalculator trip,
    required List<String> dtcCodes,
    required List<AiJournalEntry> journal,
  }) {
    final d = liveData;
    final sb = StringBuffer();
    sb.writeln('ИИ-СНАПШОТ VestaScan Pro V2.0 — Lada Vesta 1.6L 16V '
        '(ВАЗ-21129), ЭБУ ИТЭЛМА М86');
    sb.writeln('Метки достоверности: [ФАКТ] — Mode 01/ATRV; [КАНДИДАТ] — '
        'UDS 220001, реверс не доказан; [TBD] — структура не '
        'интерпретирована; «—» — значение не прочитано, а НЕ ноль.');
    sb.writeln();

    // ── 1. Паспорт ────────────────────────────────────────────────────────
    sb.writeln('1. ПАСПОРТ АВТОМОБИЛЯ И ЭСУД');
    sb.writeln('• ЭБУ: $ecuType · семейство ИТЭЛМА М86 (1.6L 16V, ВАЗ-21129)');
    sb.writeln('• Калибровка ПО (0904): $ecuId');
    sb.writeln('• Номер детали ВАЗ (220091): '
        '${passport['part'] ?? 'не запрашивалось'}');
    sb.writeln('• Модель/ДВС (220097): '
        '${passport['model'] ?? 'не запрашивалось'}');
    sb.writeln('• Краткий ID ПО (22009A): '
        '${passport['sw_short'] ?? 'не запрашивалось'}');
    sb.writeln('• Активная сессия: '
        '${isUds ? 'UDS (1003 → default 1001)' : 'KWP-CAN (1081)'}');
    sb.writeln('• Соединение: ${AiFmt.link(isConnected, isPolling)}');
    sb.writeln();

    // ── 2. Телеметрия Mode 01 + ATRV (факты) ─────────────────────────────
    sb.writeln('2. ПОДТВЕРЖДЁННАЯ ТЕЛЕМЕТРИЯ (Mode 01 + ATRV) — [ФАКТ]');
    sb.writeln('Нормы — ТИ 3100.25100.12056 (табл. 2.4-01), прогретый ДВС, ХХ, '
        'потребители выключены. Отклонение — только при выполненном условии.');
    for (final line in _telemetry(d, minVoltage)) {
      sb.writeln(line);
    }
    sb.writeln('• За сессию: мин. АКБ ${AiFmt.val(minVoltage, 2, 'В')} · '
        'макс. ТОЖ ${AiFmt.val(maxEct, 0, '°C')}');
    sb.writeln('• ДАД (010B): НЕТ ДАННЫХ (не поддерживается ЭБУ М86 в данной '
        'конфигурации, NRC 0x12)');
    sb.writeln();

    // ── 3. UDS 220001 со статусом каждого поля ───────────────────────────
    sb.writeln('3. РАСШИРЕННЫЙ БЛОК UDS 220001 — ДОСТОВЕРНОСТЬ [КАНДИДАТ]');
    for (final line in AiUdsSection.lines(
      params: udsParams,
      data: d,
      udsStatus: udsStatus,
      rpmXcheck: rpmXcheck,
      accepted: udsAccepted,
      rejected: udsRejected,
    )) {
      sb.writeln(line);
    }
    sb.writeln('• ect@54 ОТОЗВАН: 0x77 — константа во всех 321 кадре живого '
        'дампа, это НЕ ТОЖ; использовать нельзя.');
    sb.writeln('• Mode 06 (0621): ЭБУ отвечает (46 21 …), но структура TBD — '
        'счётчики/пропуски не интерпретировать.');
    sb.writeln('• При расхождении UDS и Mode 01 источник истины — '
        '010C/0105/0106/0107/ATRV.');
    sb.writeln();

    // ── 4. Матрица самообучения коррекций ────────────────────────────────
    sb.writeln('4. МАТРИЦА САМООБУЧЕНИЯ ТОПЛИВНЫХ КОРРЕКЦИЙ (STFT + LTFT, '
        'ЛИСТ 19 ТИ АВТОВАЗ)');
    sb.writeln('Total Trim = STFT + LTFT; зона — по оборотам; в скобках — '
        'число замеров.');
    for (final line in _matrixLines(matrix)) {
      sb.writeln(line);
    }
    sb.writeln('• Вердикт матрицы: ${matrix.verdict().text}');
    sb.writeln('• Пороги: норма |Total Trim| ≤ ${AiFmt.num(M86Specs.trimNormOkPct)} %; '
        'подсос ХХ ≥ +${AiFmt.num(M86Specs.trimLeakIdlePct)} %; нехватка топлива ≥ '
        '+${AiFmt.num(M86Specs.trimLeanLoadPct)} %; перелив ≤ '
        '${AiFmt.num(M86Specs.trimRichPct)} %; нужно ≥ '
        '${M86Specs.trimMinZoneSamples} замеров в «ХХ» и «частичные» '
        '(границы включительные).');
    sb.writeln();

    // ── 5. Поездка, DTC, журнал ──────────────────────────────────────────
    sb.writeln('5. СВОДКА ПОЕЗДКИ (БК), КОДЫ DTC И ЖУРНАЛ');
    sb.writeln('Поездка:');
    for (final line in _tripLines(trip)) {
      sb.writeln(line);
    }
    sb.writeln('Коды DTC (объединённый список 03 + 07 + UDS 19 02: активные и '
        'ожидающие вместе — ЭБУ М86 не разделяет их в ответе):');
    for (final line in _dtcLines(dtcCodes)) {
      sb.writeln(line);
    }
    sb.writeln('Последние записи журнала (до $journalLimit, новые первыми):');
    for (final line in _journalLines(journal)) {
      sb.writeln(line);
    }
    sb.writeln();

    // ── 6. Задание ИИ-ассистенту ─────────────────────────────────────────
    sb.writeln('6. ЗАДАНИЕ ИИ-АССИСТЕНТУ');
    sb.writeln('Ты — инженер-диагност ЭСУД АвтоВАЗ (ТИ 3100.25100.12056). '
        'Проанализируй разделы 1–5 и выдай водителю конкретный чек-лист:');
    sb.writeln('a) Тепловой режим: термостат, вентилятор, датчик ТОЖ — по ТОЖ, '
        'макс. ТОЖ за сессию, норме 90–103 °C и цели прогрева 94–102 °C.');
    sb.writeln('b) АКБ и генератор: бортсеть 13–14.5 В на работающем ДВС, '
        'минимум за сессию, просадка при пуске (< 10.5 В — АКБ/массы, '
        '< 9.8 В — критично).');
    sb.writeln('c) Топливные коррекции по зонам: ХХ — подсос неучтённого '
        'воздуха; частичные/высокие — давление топлива (бензонасос '
        '364–400 кПа), форсунки; вердикт матрицы — гипотеза, пока замеров '
        'меньше порога.');
    sb.writeln('d) ДК1/ДК2: прогретый ДК1 0.18–0.95 В, ДК2 0.59–0.75 В; '
        '1.18–1.78 В — непрогретый датчик, это НЕ отказ.');
    sb.writeln('e) Итог: 3–7 проверок от простого к сложному — что измерить, '
        'чем, ожидаемое значение; затем что подтвердить повторным замером.');
    sb.writeln('ПРАВИЛА ОТВЕТА:');
    sb.writeln('— [ФАКТ] считай доказанным; [КАНДИДАТ] и TBD — только '
        'гипотезы, помечай их явно.');
    sb.writeln('— Не подставляй числа вместо «—»/«НЕТ ДАННЫХ» и не считай '
        'прогрев или не-ХХ режимы отклонением.');
    sb.writeln('— Если данных для вывода нет — так и напиши и укажи, какой '
        'PID/блок доснять.');
    sb.writeln('— Ответ по-русски, структурировано, без общих слов.');
    return sb.toString();
  }

  // ── Раздел 2: строки телеметрии ────────────────────────────────────────
  static List<String> _telemetry(Map<String, double> d, double? minVoltage) {
    return [
      _fact(d, 'rpm', 'Обороты КВ', '010C', 'об/мин', digits: 0),
      _fact(d, 'ect', 'ТОЖ', '0105', '°C', digits: 0),
      _fact(d, 'load', 'Нагрузка', '0104', '%', digits: 1),
      _fact(d, 'speed', 'Скорость', '010D', 'км/ч', digits: 0),
      _fact(d, 'tps', 'Дроссель', '0111', '%', digits: 1,
          normText: 'признак ХХ ≤ ${AiFmt.num(M86Specs.idleTpsMaxPct)} %',
          tagOverride: _tpsTag(d['tps'])),
      _fact(d, 'volt', 'Бортсеть', 'ATRV', 'В', digits: 2),
      '• Минимум за сессию (ATRV): ${AiFmt.val(minVoltage, 2, 'В')} | при пуске '
          '≥ ${AiFmt.num(M86Specs.crankingWarnV)} В, < '
          '${AiFmt.num(M86Specs.crankingCritV)} В — критично | '
          '${_minVoltTag(minVoltage)}',
      _fact(d, 'stft', 'STFT', '0106', '%', digits: 1,
          normText: '${specRangeText('stft')} % (на ХХ ±'
              '${AiFmt.num(M86Specs.ltftIdleTolPercent)} %)'),
      _fact(d, 'ltft', 'LTFT', '0107', '%', digits: 1,
          normText: '${specRangeText('ltft')} % (на ХХ ±'
              '${AiFmt.num(M86Specs.ltftIdleTolPercent)} %)'),
      _o2('ДК1 до нейтрализатора', '0114', d['udk'],
          M86Specs.udkMin, M86Specs.udkMax),
      _o2('ДК2 после нейтрализатора', '0115', d['ddk'],
          M86Specs.ddkMin, M86Specs.ddkMax),
      '• Расчётный расход воздуха (по 0104): '
          '${AiFmt.val(d['air_mass_kgh'], 1, 'кг/ч')} | норма ХХ '
          '${AiFmt.num(M86Specs.airFlowIdleMin)}–'
          '${AiFmt.num(M86Specs.airFlowIdleMax)} кг/ч | '
          '[РАСЧЁТ, не датчик: ДАД 010B ЭБУ не отдаёт]',
    ];
  }

  /// FACT-строка: значение, норма M86Specs (или переопределённая) и честный
  /// статус из общего checkSpec (условие проверки учитывается).
  static String _fact(
    Map<String, double> d,
    String key,
    String label,
    String pid,
    String unit, {
    int digits = 0,
    String? normText,
    String? tagOverride,
  }) {
    final v = d[key];
    final range = specRangeText(key);
    final norm = normText ??
        (range == null
            ? 'норма не нормирована'
            : 'норма $range${unit.isEmpty ? '' : ' $unit'}');
    return '• $label ($pid): ${AiFmt.val(v, digits, unit)} | $norm | '
        '${tagOverride ?? _specTag(key, d, v)}';
  }

  /// Дроссель: полосы допуска в ТИ нет — честно различаем ХХ и нагрузку
  /// (порог признака ХХ из M86Specs), не объявляя «отклонением».
  static String _tpsTag(double? v) {
    if (v == null) return '[НЕТ ДАННЫХ]';
    return v <= M86Specs.idleTpsMaxPct
        ? '[ХХ ≤ ${AiFmt.num(M86Specs.idleTpsMaxPct)} %]'
        : '[НАГРУЗКА > ${AiFmt.num(M86Specs.idleTpsMaxPct)} %]';
  }

  static String _specTag(String key, Map<String, double> d, double? value) {
    if (value == null) return '[НЕТ ДАННЫХ]';
    return switch (checkSpec(key, d).status) {
      SpecStatus.ok => '[В НОРМЕ]',
      SpecStatus.out => '[ОТКЛОНЕНИЕ]',
      SpecStatus.pending => '[УСЛОВИЕ ПРОВЕРКИ НЕ ВЫПОЛНЕНО]',
      SpecStatus.none => '[СПРАВОЧНО]',
    };
  }

  /// Датчик кислорода: значения > 1.0 В — непрогретый ДК (окно 1.18–1.78 В),
  /// это не отклонение. Норма прогретого — диапазон из M86Specs.
  static String _o2(
      String label, String pid, double? v, double min, double max) {
    final tag = v == null
        ? '[НЕТ ДАННЫХ]'
        : v > 1.0
            ? '[НЕПРОГРЕТЫЙ ДК — не отказ]'
            : (v < min || v > max ? '[ОТКЛОНЕНИЕ]' : '[В НОРМЕ]');
    return '• $label ($pid): ${AiFmt.val(v, 2, 'В')} | норма прогретого '
        '${AiFmt.num(min)}–${AiFmt.num(max)} В | $tag';
  }

  static String _minVoltTag(double? v) {
    if (v == null) return '[НЕТ ДАННЫХ]';
    if (v < M86Specs.crankingCritV) return '[КРИТИЧНО: < 9.8 В]';
    if (v < M86Specs.crankingWarnV) return '[НИЖЕ 10.5 В — проверить АКБ/массы]';
    return '[В НОРМЕ ≥ 10.5 В]';
  }

  // ── Раздел 4: зоны матрицы ─────────────────────────────────────────────
  static List<String> _matrixLines(TrimMatrix m) {
    const zones = <(TrimZone, String, String)>[
      (TrimZone.idle, 'ХХ', '<1100'),
      (TrimZone.lowLoad, 'Малые', '1100–2200'),
      (TrimZone.partLoad, 'Частичные', '2200–3400'),
      (TrimZone.highLoad, 'Высокие', '>3400'),
    ];
    return [
      for (final (z, name, range) in zones)
        _matrixLine(m.bins[z]!, name, range),
    ];
  }

  static String _matrixLine(TrimBin b, String name, String range) {
    final mean = b.count == 0
        ? '— %'
        : '${b.mean >= 0 ? '+' : ''}${b.mean.toStringAsFixed(1)} %';
    return '• $name $range об/мин: $mean | N зам.: ${b.count}';
  }

  // ── Раздел 5: поездка, DTC, журнал ────────────────────────────────────
  static List<String> _tripLines(TripCalculator t) {
    final avg = t.averageConsumptionL100Km;
    final instant = t.isMoving
        ? '${t.instantFuelL100Km.toStringAsFixed(1)} л/100 км'
        : '${t.instantFuelLpH.toStringAsFixed(2)} л/ч';
    return [
      '• Пробег за сессию: ${t.totalDistanceKm.toStringAsFixed(2)} км',
      '• Израсходовано (расчёт БК): ${t.totalFuelLiters.toStringAsFixed(2)} л',
      '• Средний расход: '
          '${avg > 0 ? '${avg.toStringAsFixed(1)} л/100 км' : '— (нет движения)'}',
      '• Мгновенный расход: $instant (на стоянке ≤3 км/ч — л/ч, в движении — '
          'л/100 км)',
      '• Скорость: средняя ${t.averageSpeedKmh.toStringAsFixed(0)} · '
          'максимальная ${t.maxSpeedKmh.toStringAsFixed(0)} км/ч',
      '• Поправка БК: ×${t.fuelTrimFactor.toStringAsFixed(2)} '
          '(калибровка по чеку)',
    ];
  }

  static List<String> _dtcLines(List<String> codes) {
    if (codes.isEmpty) {
      return ['• Ошибок нет (Mode 03/07 и UDS 19 02 вернули пусто)'];
    }
    return [
      for (final c in codes)
        '• $c — ${kM86DtcDatabase[c] ?? 'Нет описания в базе М86 (ТИ)'}',
    ];
  }

  static List<String> _journalLines(List<AiJournalEntry> j) {
    if (j.isEmpty) return ['• записей нет'];
    return [
      for (final e in j.take(journalLimit))
        '• [${e.time}] ${e.severity.toUpperCase()}: ${e.title} — '
            '${e.description}',
    ];
  }

}

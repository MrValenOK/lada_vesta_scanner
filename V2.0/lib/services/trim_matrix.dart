// lib/services/trim_matrix.dart — матрица самообучения топливных коррекций
// («МАТРИЦА САМООБУЧЕНИЯ, ЛИСТ 19 ТИ АВТОВАЗ»).
//
// Порт логики lada_vesta_scanner@5335a2e (lib/main.dart): 4 зоны ХХ/малые/
// частичные/высокие, гейты прогрева/петли/ПХХ, вердикт _buildTrimMapCard.
// П3 (2026-10-30): накопление — среднее Total Trim = STFT + LTFT и число
// замеров на зону (вместо медианного окна M2); вердикты — по паттернам
// задания (подсос / нехватка топлива / перелив; пороги — M86Specs).
//
// Источники значений НЕ смешиваются: пара Mode 01 0106+0107 (приоритетно)
// либо пара UDS uds_stft+uds_ltft — выбор в trim_matrix_provider. Зоны
// классифицируются ЧИСТО по оборотам (1100/2200/3400); в источнике зона
// дополнительно зависела от ДЗ и ДАД. Гейты: прогрев ≥ 75 °C, замкнутая
// петля (не ПХХ, не прогрев ДК), ДЗ < 70 %, ДВС вращается (≥ 400 об/мин),
// первые 20 с после старта опроса. Накопленное — в shared_preferences.
//
// Слой services: UI не знает ни о байтах, ни о prefs.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Зона матрицы (порядок — как в источнике: от ХХ к высоким нагрузкам).
enum TrimZone { idle, lowLoad, partLoad, highLoad }

extension TrimZoneInfo on TrimZone {
  String get label => switch (this) {
        TrimZone.idle => 'ХХ',
        TrimZone.lowLoad => 'Малые',
        TrimZone.partLoad => 'Част.',
        TrimZone.highLoad => 'Высок.',
      };

  /// Ключ хранения — как в источнике (совместимость со старым состоянием).
  String get storageKey => switch (this) {
        TrimZone.idle => 'zone_idle',
        TrimZone.lowLoad => 'zone_low_load',
        TrimZone.partLoad => 'zone_part_load',
        TrimZone.highLoad => 'zone_high_load',
      };
}

/// Накопитель одной зоны: сумма и число замеров Total Trim (STFT+LTFT, %).
/// Среднее = sum/count; зона без замеров показывает «--- / 0 зам.».
class TrimBin {
  TrimBin(this.label);

  final String label;
  double _sum = 0;
  int _count = 0;

  int get count => _count;
  double get sum => _sum;
  double get mean => _count == 0 ? 0.0 : _sum / _count;
  bool get isNotEmpty => _count > 0;

  /// Восстановление из хранилища (count ≤ 0 или нечисловой sum → пусто).
  void loadStat(double sum, int count) {
    final ok = count > 0 && sum.isFinite;
    _sum = ok ? sum : 0;
    _count = ok ? count : 0;
  }

  /// [stft]/[ltft] — в процентах. Сэмпл с |значением| выше жёсткого предела
  /// (`trimHardLimitPct + 5`) отбрасывается как недостоверный (сбой CAN/выброс).
  /// Возвращает true, если сэмпл принят.
  bool addSample(double stft, double ltft) {
    const hard = M86Specs.trimHardLimitPct + 5.0;
    if (stft.abs() > hard || ltft.abs() > hard) return false;
    _sum += stft + ltft;
    _count += 1;
    return true;
  }

  void clear() {
    _sum = 0;
    _count = 0;
  }
}

/// Итог матрицы. [group] — группа для снапшота/агрегатов: «подсос»,
/// «форсунки/топливо», «богатая» или «—» (пока нет вердикта).
enum TrimVerdictKind { none, leak, lean, rich }

class TrimVerdict {
  const TrimVerdict(this.kind, this.text);

  final TrimVerdictKind kind;
  final String text;

  String get group => switch (kind) {
        TrimVerdictKind.leak => 'подсос',
        TrimVerdictKind.lean => 'форсунки/топливо',
        TrimVerdictKind.rich => 'богатая',
        TrimVerdictKind.none => '—',
      };
}

/// Матрица: 4 зоны + классификация по оборотам + вердикт.
class TrimMatrix {
  TrimMatrix() {
    for (final z in TrimZone.values) {
      bins[z] = TrimBin(z.label);
    }
  }

  final Map<TrimZone, TrimBin> bins = {};

  /// Зона по оборотам (границы 1100/2200/3400): ХХ < 1100 ≤ малые < 2200 ≤
  /// частичные < 3400 ≤ высокие.
  static TrimZone zoneForRpm(double rpm) {
    if (rpm < M86Specs.trimZoneLowRpm) return TrimZone.idle;
    if (rpm < M86Specs.trimZonePartRpm) return TrimZone.lowLoad;
    if (rpm < M86Specs.trimZoneHighRpm) return TrimZone.partLoad;
    return TrimZone.highLoad;
  }

  /// Гейт накопления: прогрев ≥ 75 °C, замкнутая петля (не ПХХ и не прогрев
  /// ДК), ДЗ < 70 %, прошли первые секунды пуска [M86Specs.trimStartupGraceSec]
  /// от старта опроса. Если ТОЖ неизвестна или время опроса не передано —
  /// условие не подтверждено, сэмпл не берём.
  static bool accepts({
    required double? ectC,
    required bool dfcoCutoff,
    required bool o2Cold,
    required double? tpsPct,
    required double? pollSeconds,
  }) {
    if (ectC == null || ectC < M86Specs.coldEngineTempC) return false;
    if (dfcoCutoff || o2Cold) return false;
    if (tpsPct != null && tpsPct >= M86Specs.trimTpsMaxPct) return false;
    if (pollSeconds == null ||
        pollSeconds < M86Specs.trimStartupGraceSec) {
      return false;
    }
    return true;
  }

  /// Добавить замер (Total Trim = stft + ltft). Возвращает true, если он
  /// прошёл гейты и лёг в зону. ДВС не вращается (< 400 об/мин) — не замер.
  bool addSample({
    required double rpm,
    required double stftPct,
    required double ltftPct,
    double? ectC,
    double? tpsPct,
    bool dfcoCutoff = false,
    bool o2Cold = false,
    double? pollSeconds,
  }) {
    if (rpm < M86Specs.trimRunRpmMin) return false;
    if (!accepts(
        ectC: ectC,
        dfcoCutoff: dfcoCutoff,
        o2Cold: o2Cold,
        tpsPct: tpsPct,
        pollSeconds: pollSeconds)) {
      return false;
    }
    return bins[zoneForRpm(rpm)]!.addSample(stftPct, ltftPct);
  }

  /// Вердикт по средним Total Trim зон (паттерны П3; пороги — M86Specs).
  /// Нужно ≥ [M86Specs.trimMinZoneSamples] замеров в «ХХ» и «частичные»;
  /// пороги включительные: ХХ ≥ +8 % уже подсос, ≤ −8 % — перелив.
  TrimVerdict verdict() {
    final idle = bins[TrimZone.idle]!;
    final part = bins[TrimZone.partLoad]!;
    const min = M86Specs.trimMinZoneSamples;
    if (idle.count < min || part.count < min) {
      return TrimVerdict(
          TrimVerdictKind.none,
          'Накапливается: нужно ≥$min замеров в «ХХ» и «частичные» '
          '(сейчас ${idle.count} и ${part.count}).');
    }

    final idleM = idle.mean;
    final loadZones = <TrimBin>[
      bins[TrimZone.lowLoad]!,
      part,
      bins[TrimZone.highLoad]!,
    ].where((b) => b.count > 0).toList();
    var loadMax = double.negativeInfinity;
    for (final b in loadZones) {
      if (b.mean > loadMax) loadMax = b.mean;
    }
    final allZones = <TrimBin>[idle, ...loadZones];

    String s(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

    // 1. Подсос неучтённого воздуха: ХХ выраженный плюс, под нагрузкой норма.
    if (idleM >= M86Specs.trimLeakIdlePct &&
        loadMax <= M86Specs.trimNormOkPct) {
      return TrimVerdict(
          TrimVerdictKind.leak,
          'ПОДСОС неучтённого воздуха: ХХ ${s(idleM)}, под нагрузкой '
          '${s(loadMax)} (норма). Проверьте ресивер, кольца форсунок, '
          'вакуумные шланги.');
    }

    // 2. Нехватка топлива: ХХ в норме, с ростом нагрузки — сильный плюс.
    final partM = part.mean;
    final high = bins[TrimZone.highLoad]!;
    if (idleM.abs() <= M86Specs.trimNormOkPct &&
        (partM >= M86Specs.trimLeanLoadPct ||
            (high.count >= min && high.mean >= M86Specs.trimLeanLoadPct))) {
      return TrimVerdict(
          TrimVerdictKind.lean,
          'НЕХВАТКА ТОПЛИВА: ХХ ${s(idleM)} (норма), с ростом нагрузки '
          '${s(partM)}${high.count > 0 ? ' / ${s(high.mean)}' : ''}. '
          'Проверьте бензонасос (364–400 кПа), сетку/фильтр, форсунки.');
    }

    // 3. Перелив/богатая: устойчивый минус во всех зонах с данными.
    if (idleM <= M86Specs.trimRichPct &&
        allZones.every((b) => b.mean <= M86Specs.trimRichPct)) {
      return TrimVerdict(
          TrimVerdictKind.rich,
          'БОГАТАЯ СМЕСЬ (перелив): минус во всех зонах (${s(idleM)} … '
          '${s(loadMax)}). Проверьте форсунки, давление топлива, ДТОЖ, '
          'клапан адсорбера.');
    }

    // 4. Норма: все зоны с данными в пределах ±7 %.
    if (allZones.every((b) => b.mean.abs() <= M86Specs.trimNormOkPct)) {
      return const TrimVerdict(TrimVerdictKind.none,
          'Отклонений нет: Total Trim в пределах ±7 % во всех зонах.');
    }

    // 5. Смешанная картина — честно, без ярлыка.
    return TrimVerdict(
        TrimVerdictKind.none,
        'Выраженного паттерна нет: ХХ ${s(idleM)}, малые/част./высок. — '
        '${loadZones.map((b) => s(b.mean)).join(' / ')}. Наблюдайте дальше.');
  }

  int get totalSamples => bins.values.fold(0, (s, b) => s + b.count);

  void reset() {
    for (final b in bins.values) {
      b.clear();
    }
  }

  /// Копия (для уведомления UI: StateNotifier сравнивает по идентичности).
  TrimMatrix copy() {
    final m = TrimMatrix();
    for (final e in bins.entries) {
      m.bins[e.key]!.loadStat(e.value.sum, e.value.count);
    }
    return m;
  }

  /// JSON v2: `{zone: {"sum": …, "count": …}}`.
  Map<String, Map<String, num>> toJson() => {
        for (final e in bins.entries)
          e.key.storageKey: {'sum': e.value.sum, 'count': e.value.count},
      };

  void loadJson(Map<String, dynamic> json) {
    for (final z in TrimZone.values) {
      final v = json[z.storageKey];
      if (v is Map) {
        bins[z]!.loadStat((v['sum'] as num?)?.toDouble() ?? 0,
            (v['count'] as num?)?.toInt() ?? 0);
      } else if (v is List) {
        // Формат M2 (список сэмплов) — миграция без потери накопленного:
        // сумма значений и их количество дают то же среднее.
        final sum = v.fold<double>(0, (acc, e) => acc + (e as num).toDouble());
        bins[z]!.loadStat(sum, v.length);
      }
    }
  }
}

/// Хранение матрицы в shared_preferences (ключ `trim_matrix_v1`).
/// В источнике зоны писались в файл `.vesta_state`; в V2.0 — prefs.
class TrimMatrixStore {
  static const String prefsKey = 'trim_matrix_v1';

  Future<void> save(TrimMatrix matrix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(matrix.toJson()));
  }

  Future<void> loadInto(TrimMatrix matrix) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      matrix.loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Повреждённые данные не должны ронять приложение — начинаем заново.
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}

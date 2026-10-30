// lib/services/health_monitor.dart — сессионный контроль здоровья М86:
// минимум напряжения, максимум ТОЖ и критические события (просадка АКБ при
// пуске, перегрев, новые DTC). Не знает о providers: severity — строкой,
// маппинг в NuanceSeverity делает провайдер (JournalLogger.severityOf).
// Пороги — M86Specs (ТИ 3100.25100.12056 / эвристики приложения).
import '../core/constants.dart';

class HealthAlert {
  final String id;
  final String title;
  final String description;
  final String severity; // 'critical' | 'warning'

  const HealthAlert(this.id, this.title, this.description, this.severity);
}

class HealthMonitor {
  double? minVoltage;
  double? maxEct;

  final Set<String> _knownDtcs = {};

  /// Новая сессия: минимумы/максимумы и известные DTC начинаются заново.
  void resetSession() {
    minVoltage = null;
    maxEct = null;
    _knownDtcs.clear();
  }

  /// Копит минимум напряжения и максимум ТОЖ (вызывать каждый цикл опроса).
  void observe(Map<String, double> d) {
    final v = d['volt'];
    if (v != null && (minVoltage == null || v < minVoltage!)) minVoltage = v;
    final e = d['ect'];
    if (e != null && (maxEct == null || e > maxEct!)) maxEct = e;
  }

  /// Критичные события текущего цикла (с фильтром условий).
  List<HealthAlert> check(Map<String, double> d) {
    final out = <HealthAlert>[];
    final rpm = d['rpm'] ?? 0;

    // Просадка АКБ при прокрутке стартера: фиксируется только 100–600 об/мин.
    final volt = d['volt'];
    if (volt != null &&
        rpm >= M86Specs.crankingRpmMin &&
        rpm <= M86Specs.crankingRpmMax &&
        volt < M86Specs.crankingWarnV) {
      final critical = volt < M86Specs.crankingCritV;
      out.add(HealthAlert(
          'crank_volt_low',
          'Просадка АКБ при пуске',
          '${volt.toStringAsFixed(2)} В при прокрутке (норма ≥ '
          '${M86Specs.crankingWarnV.toStringAsFixed(1)} В): АКБ и силовые массы.',
          critical ? 'critical' : 'warning'));
    }

    // Перегрев: выше верхней границы ТИ (103 °C).
    final ect = d['ect'];
    if (ect != null && ect > M86Specs.coolantMax) {
      out.add(HealthAlert(
          'overheat',
          'Перегрев ОЖ',
          '${ect.toStringAsFixed(0)} °C > '
          '${M86Specs.coolantMax.toStringAsFixed(0)} °C: вентилятор '
          '(1-я скорость 102 °C) и термостат.',
          'critical'));
    }
    return out;
  }

  /// Проверить цикл и отдать события колбэком (провайдер только логирует).
  void checkInto(Map<String, double> d, void Function(HealthAlert) emit) {
    for (final a in check(d)) {
      emit(a);
    }
  }

  /// Отдать колбэком только новые DTC (за сессию).
  void dtcInto(List<String> codes, void Function(HealthAlert) emit) {
    for (final a in dtcAlerts(codes)) {
      emit(a);
    }
  }

  /// Новые (ещё не виденные за сессию) DTC → критические события.
  List<HealthAlert> dtcAlerts(List<String> codes) {
    final fresh = codes.where((c) => !_knownDtcs.contains(c)).toList();
    _knownDtcs.addAll(codes);
    return [
      for (final c in fresh)
        HealthAlert('dtc_new_$c', 'Новый DTC: $c',
            'Появился код $c — расшифровка и стоп-кадр на экране «Коды».',
            'critical')
    ];
  }
}

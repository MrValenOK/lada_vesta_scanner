// lib/services/trip_calculator.dart — бортовой компьютер поездки (П4).
// Расход: air_mass / 14.7 × trim(STFT/LTFT) × fuelTrimFactor; на стоянке
// (≤3 км/ч) — л/ч, в движении (>3 км/ч) — л/100 км. Пробег — интеграл
// скорости, средняя скорость — по времени движения. Состояние поездки и
// поправка БК переживают перезапуск (shared_preferences, автосохранение
// не чаще 1 раза в 3 с). Калибровка — по фактически залитым литрам (чек).
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class TripCalculator {
  TripCalculator({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  double totalDistanceKm = 0.0;
  double totalFuelLiters = 0.0;
  double maxSpeedKmh = 0.0;
  double averageSpeedKmh = 0.0;

  // Текущие показатели для вывода на дашборд в реальном времени
  double instantFuelLpH = 0.0;
  double instantFuelL100Km = 0.0;

  /// Поправка БК: 0.50–1.50 (по умолчанию 1.00), множитель к расчётному расходу.
  double fuelTrimFactor = M86Specs.fuelFactorDefault;

  double _movingHours = 0.0;
  double _lastSpeedKmh = 0.0;
  DateTime? _lastTickTime;
  DateTime? _lastSaveAt;
  bool _loaded = false;

  static const String tripPrefsKey = 'trip_state_v1';
  static const String factorPrefsKey = 'fuel_trim_factor_v1';
  static const Duration _savePeriod = Duration(seconds: 3);

  bool get isMoving => _lastSpeedKmh > M86Specs.tripMovingKmh;
  bool get isLoaded => _loaded;

  void update({
    required int rpm,
    required double speedKmh,
    required double airMassKgH,
    required double tpsPct,
    required bool isDfcoActive,
    double stftPct = 0.0, // Краткосрочная коррекция М86 (%)
    double ltftPct = 0.0, // Долгосрочная коррекция М86 (%)
  }) {
    final now = _clock();
    final prev = _lastTickTime;
    _lastTickTime = now;
    if (prev == null) return;

    final deltaTimeSec = now.difference(prev).inMilliseconds / 1000.0;
    final deltaHours = deltaTimeSec / 3600.0;

    // Защита от зависания Bluetooth или паузы опроса
    if (deltaTimeSec <= 0.0 || deltaTimeSec > 5.0) return;

    _lastSpeedKmh = speedKmh;

    // 1. Интеграл скорости (пробег) и время движения — для средней скорости.
    if (speedKmh > 0) {
      totalDistanceKm += speedKmh * deltaHours;
      _movingHours += deltaHours;
      if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;
      averageSpeedKmh =
          _movingHours > 0 ? totalDistanceKm / _movingHours : 0.0;
    }

    // 2. Расход топлива с защитой ПХХ (отсечка топливоподачи).
    double currentFuelKgH = 0.0;

    // Если ЭБУ остановил двигатель (rpm == 0) или активен режим ПХХ — подача 0
    final bool isCutoff =
        (rpm < 300) || isDfcoActive || (tpsPct < 2.0 && rpm > 1500);

    if (!isCutoff && airMassKgH > 0) {
      // Коррекции смеси по УДК × калибровочная поправка БК (П4).
      final double trimFactor =
          (1.0 + (stftPct / 100.0)) * (1.0 + (ltftPct / 100.0));
      currentFuelKgH = (airMassKgH / M86Specs.fuelStoichRatio) *
          trimFactor *
          fuelTrimFactor;
    }

    // Перевод из кг/ч в л/ч
    instantFuelLpH = currentFuelKgH / M86Specs.fuelDensityKgL;
    totalFuelLiters += instantFuelLpH * deltaHours;

    // Мгновенный путевой расход — только в движении (>3 км/ч); на стоянке л/ч.
    instantFuelL100Km = speedKmh > M86Specs.tripMovingKmh
        ? (instantFuelLpH / speedKmh) * 100.0
        : 0.0;

    _scheduleSave(now);
  }

  // Средний расход на 100 км за поездку
  double get averageConsumptionL100Km {
    if (totalDistanceKm < 0.1) return 0.0;
    return (totalFuelLiters / totalDistanceKm) * 100.0;
  }

  /// Загрузка сохранённой поездки и поправки БК (при старте приложения).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final f = prefs.getDouble(factorPrefsKey);
      if (f != null) {
        fuelTrimFactor =
            f.clamp(M86Specs.fuelFactorMin, M86Specs.fuelFactorMax).toDouble();
      }
      final raw = prefs.getString(tripPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        totalDistanceKm = _nonNegative(json['distance']);
        totalFuelLiters = _nonNegative(json['fuel']);
        maxSpeedKmh = _nonNegative(json['maxSpeed']);
        _movingHours = _nonNegative(json['movingHours']);
        _recalcAverageSpeed();
      }
    } catch (_) {
      // Повреждённые данные не должны ронять приложение — начинаем заново.
    } finally {
      _loaded = true;
    }
  }

  static double _nonNegative(Object? v) {
    final d = (v as num?)?.toDouble() ?? 0.0;
    return d.isFinite && d > 0 ? d : 0.0;
  }

  void _recalcAverageSpeed() {
    averageSpeedKmh = _movingHours > 0 ? totalDistanceKm / _movingHours : 0.0;
  }

  /// Ручная установка поправки БК (clamp 0.50–1.50). Возвращает применённое.
  double setFuelTrimFactor(double value) {
    fuelTrimFactor =
        value.clamp(M86Specs.fuelFactorMin, M86Specs.fuelFactorMax).toDouble();
    unawaited(save());
    return fuelTrimFactor;
  }

  /// Калибровка по чеку: actualLiters — фактически залито (израсходовано).
  /// Поправка умножается на actual/расчёт, т.к. расчёт уже содержит текущую.
  /// false — ввод некорректен или накоплено мало данных (нет смысла калибровать).
  bool calibrateFromActual(double actualLiters) {
    if (actualLiters <= 0 ||
        totalFuelLiters < M86Specs.tripCalibrationMinLiters) {
      return false;
    }
    final next = fuelTrimFactor * (actualLiters / totalFuelLiters);
    fuelTrimFactor =
        next.clamp(M86Specs.fuelFactorMin, M86Specs.fuelFactorMax).toDouble();
    unawaited(save());
    return true;
  }

  void _scheduleSave(DateTime now) {
    final last = _lastSaveAt;
    if (last != null && now.difference(last) < _savePeriod) return;
    _lastSaveAt = now;
    unawaited(save());
  }

  /// Сохранение поездки и поправки БК в shared_preferences.
  /// Счётчик поколений: более свежий save отменяет запись устаревшего снимка.
  int _saveSeq = 0;

  Future<void> save() async {
    final seq = ++_saveSeq;
    final payload = jsonEncode({
      'distance': totalDistanceKm,
      'fuel': totalFuelLiters,
      'maxSpeed': maxSpeedKmh,
      'movingHours': _movingHours,
    });
    final factor = fuelTrimFactor;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (seq != _saveSeq) return; // уже запрошено более свежее сохранение
      await prefs.setString(tripPrefsKey, payload);
      await prefs.setDouble(factorPrefsKey, factor);
    } catch (_) {
      // Нет доступа к prefs — поездка продолжается в памяти.
    }
  }

  void reset() {
    totalDistanceKm = 0.0;
    totalFuelLiters = 0.0;
    maxSpeedKmh = 0.0;
    averageSpeedKmh = 0.0;
    _movingHours = 0.0;
    _lastSpeedKmh = 0.0;
    instantFuelLpH = 0.0;
    instantFuelL100Km = 0.0;
    _lastTickTime = null;
    _lastSaveAt = null;
    unawaited(save()); // нули должны пережить перезапуск
  }
}
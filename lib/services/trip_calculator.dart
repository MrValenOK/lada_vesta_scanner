class TripCalculator {
  double totalDistanceKm = 0.0;
  double totalFuelLiters = 0.0;
  double maxSpeedKmh = 0.0;

  // Текущие показатели для вывода на дашборд в реальном времени
  double instantFuelLpH = 0.0;
  double instantFuelL100Km = 0.0;

  DateTime? _lastTickTime;

  // Константы для бензина АИ-92 / АИ-95
  final double stoichiometricRatio = 14.7;
  final double fuelDensityKgL = 0.75; // ~0.75 кг/л при 15-20°C

  void update({
    required int rpm,
    required double speedKmh,
    required double airMassKgH,
    required double tpsPct,
    required bool isDfcoActive,
    double stftPct = 0.0, // Краткосрочная коррекция М86 (%)
    double ltftPct = 0.0, // Долгосрочная коррекция М86 (%)
  }) {
    final now = DateTime.now();
    if (_lastTickTime == null) {
      _lastTickTime = now;
      return;
    }

    final deltaTimeSec = now.difference(_lastTickTime!).inMilliseconds / 1000.0;
    final deltaHours = deltaTimeSec / 3600.0;
    _lastTickTime = now;

    // Защита от зависания Bluetooth или паузы опроса
    if (deltaTimeSec <= 0.0 || deltaTimeSec > 5.0) return;

    // 1. Интеграл скорости (пробег)
    if (speedKmh > 0) {
      totalDistanceKm += speedKmh * deltaHours;
      if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;
    }

    // 2. Расход топлива с защитой ПХХ (отсечка топливоподачи)
    double currentFuelKgH = 0.0;

    // Если ЭБУ остановил двигатель (rpm == 0) или активен режим ПХХ — подача 0
    final bool isCutoff = (rpm < 300) || isDfcoActive || (tpsPct < 2.0 && rpm > 1500);

    if (!isCutoff && airMassKgH > 0) {
      // Коэффициент коррекции смеси по УДК (например, STFT -3.9% и LTFT +0.8%)
      final double trimFactor = (1.0 + (stftPct / 100.0)) * (1.0 + (ltftPct / 100.0));
      currentFuelKgH = (airMassKgH / stoichiometricRatio) * trimFactor;
    }

    // Перевод из кг/ч в л/ч
    instantFuelLpH = currentFuelKgH / fuelDensityKgL;
    totalFuelLiters += instantFuelLpH * deltaHours;

    // Мгновенный путевой расход (считаем только при движении > 5 км/ч)
    if (speedKmh >= 5.0) {
      instantFuelL100Km = (instantFuelLpH / speedKmh) * 100.0;
    } else {
      instantFuelL100Km = 0.0; // На месте показываем instantFuelLpH (л/ч)
    }
  }

  // Средний расход на 100 км за поездку
  double get averageConsumptionL100Km {
    if (totalDistanceKm < 0.1) return 0.0;
    return (totalFuelLiters / totalDistanceKm) * 100.0;
  }

  void reset() {
    totalDistanceKm = 0.0;
    totalFuelLiters = 0.0;
    maxSpeedKmh = 0.0;
    instantFuelLpH = 0.0;
    instantFuelL100Km = 0.0;
    _lastTickTime = null;
  }
}
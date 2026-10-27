class TripCalculator {
  double totalDistanceKm = 0.0;
  double totalFuelLiters = 0.0;
  double maxSpeedKmh = 0.0;
  
  DateTime? _lastTickTime;
  
  // Константы
  final double stoichiometricRatio = 14.7;
  final double fuelDensityKgL = 0.75;

  void update({
    required int rpm,
    required double speedKmh,
    required double airMassKgH,
    required double tpsPct,
    required bool isDfcoActive,
  }) {
    final now = DateTime.now();
    
    if (_lastTickTime == null) {
      _lastTickTime = now;
      return;
    }
    
    final deltaTimeSec = now.difference(_lastTickTime!).inMilliseconds / 1000.0;
    final deltaHours = deltaTimeSec / 3600.0;
    _lastTickTime = now;

    // Защита от слишком долгих пауз (например, потеря связи Bluetooth)
    if (deltaTimeSec > 5.0) return;

    // 1. Интеграл скорости (пробег)
    if (speedKmh > 0) {
      totalDistanceKm += speedKmh * deltaHours;
      if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;
    }

    // 2. Расчет расхода топлива с защитой ПХХ (отсечка)
    double currentFuelKgH = 0.0;
    final bool isCutoff = isDfcoActive || (tpsPct < 2.0 && rpm > 1500);

    if (!isCutoff) {
      currentFuelKgH = airMassKgH / stoichiometricRatio;
    }

    final currentFuelLpH = currentFuelKgH / fuelDensityKgL;
    totalFuelLiters += currentFuelLpH * deltaHours;
  }

  double get averageConsumptionL100Km {
    if (totalDistanceKm < 0.1) return 0.0;
    return (totalFuelLiters / totalDistanceKm) * 100;
  }
  
  void reset() {
    totalDistanceKm = 0.0;
    totalFuelLiters = 0.0;
    maxSpeedKmh = 0.0;
    _lastTickTime = null;
  }
}
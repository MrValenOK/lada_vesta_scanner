import 'dart:math' as math;

class EcuParameter {
  final String id;
  final String name;
  final int byteOffset;
  final int width;
  final double multiplier;
  final double divisor;
  final double offset;
  final int decimals;
  final bool signedComplement;
  final int bitIndex; // Если -1, то это число. Если >= 0, то битовый флаг (0 или 1)
  final String unit;

  EcuParameter({
    required this.id,
    required this.name,
    required this.byteOffset,
    required this.width,
    this.multiplier = 1.0,
    this.divisor = 1.0,
    this.offset = 0.0,
    this.decimals = 0,
    this.signedComplement = false,
    this.bitIndex = -1,
    this.unit = '',
  });

  factory EcuParameter.fromJson(Map<String, dynamic> json) {
    return EcuParameter(
      id: json['id'] as String,
      name: json['name'] as String,
      byteOffset: json['byteOffset'] as int,
      width: json['width'] as int? ?? 1,
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      divisor: (json['divisor'] as num?)?.toDouble() ?? 1.0,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      decimals: json['decimals'] as int? ?? 0,
      signedComplement: json['signedComplement'] as bool? ?? false,
      bitIndex: json['bitIndex'] as int? ?? -1,
      unit: json['unit'] as String? ?? '',
    );
  }

  /// Метод декодирования сырых байт в готовое значение
  double? decode(List<int> payload) {
    // Защита от выхода за пределы массива
    if (byteOffset < 0 || byteOffset + width > payload.length) return null;

    int raw = 0;
    // Собираем число из байтов (Big Endian)
    for (int i = 0; i < width; i++) {
      raw = (raw << 8) | payload[byteOffset + i];
    }

    // Если это битовый флаг
    if (bitIndex >= 0) {
      return ((raw >> bitIndex) & 1).toDouble();
    }

    // Обработка отрицательных чисел (Дополнительный код / Two's complement)
    if (signedComplement) {
      final signBit = 1 << (width * 8 - 1);
      if ((raw & signBit) != 0) {
        raw -= (1 << (width * 8));
      }
    }

    // Применяем формулу
    double v = (raw * multiplier / divisor) + offset;
    
    // Округляем до нужного количества знаков
    if (decimals > 0) {
      final factor = math.pow(10, decimals);
      v = (v * factor).roundToDouble() / factor;
    } else {
      v = v.roundToDouble();
    }
    
    // Избегаем "-0.0"
    return v == 0 ? 0.0 : v;
  }
}

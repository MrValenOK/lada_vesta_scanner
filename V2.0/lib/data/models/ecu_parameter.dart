import 'dart:math' as math;

/// Параметр ЭБУ: каноническая линейная модель профиля.
/// Позиция поля — [byteOffset] (байт DATA после service+DID).
/// Значение — ЕДИНАЯ формула: `value = raw * multiplier + addend`.
/// Legacy-имена (`divisor`, позиционный `offset`) в модель не входят —
/// asset мигрирован (правила нормализации: AUDIT/03_review_datacontract_v2.md).
class EcuParameter {
  final String id;
  final String name;
  final int byteOffset;
  final int width;
  final double multiplier;
  final double addend;
  final int decimals;
  final bool signedComplement;
  final int bitIndex; // -1 = число; >= 0 = битовый флаг (0 или 1)
  final String unit;

  /// Уровень доказанности (из профиля): confirmed /
  /// observed_pending_synchronous_crosscheck / candidate / raw.
  final String status;

  EcuParameter({
    required this.id,
    required this.name,
    required this.byteOffset,
    this.width = 1,
    this.multiplier = 1.0,
    this.addend = 0.0,
    this.decimals = 0,
    this.signedComplement = false,
    this.bitIndex = -1,
    this.unit = '',
    this.status = '',
  });

  factory EcuParameter.fromJson(Map<String, dynamic> json) {
    return EcuParameter(
      id: json['id'] as String,
      name: json['name'] as String,
      byteOffset: json['byteOffset'] as int,
      width: json['width'] as int? ?? 1,
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      addend: (json['addend'] as num?)?.toDouble() ?? 0.0,
      decimals: json['decimals'] as int? ?? 0,
      signedComplement: json['signedComplement'] as bool? ?? false,
      bitIndex: json['bitIndex'] as int? ?? -1,
      unit: json['unit'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  /// Метод декодирования сырых байт в готовое значение.
  /// Возвращает null, если байты не влезают в payload (параметр не ломает другие).
  double? decode(List<int> payload) {
    if (byteOffset < 0 || byteOffset + width > payload.length) return null;

    int raw = 0;
    // Собираем число из байтов (Big Endian)
    for (int i = 0; i < width; i++) {
      raw = (raw << 8) | payload[byteOffset + i];
    }

    // Битовый флаг
    if (bitIndex >= 0) {
      return ((raw >> bitIndex) & 1).toDouble();
    }

    // Отрицательные числа (дополнительный код)
    if (signedComplement) {
      final signBit = 1 << (width * 8 - 1);
      if ((raw & signBit) != 0) {
        raw -= (1 << (width * 8));
      }
    }

    // Каноническая формула
    double v = raw * multiplier + addend;

    // Округление отображения
    if (decimals > 0) {
      final factor = math.pow(10, decimals);
      v = (v * factor).roundToDouble() / factor;
    } else {
      v = v.roundToDouble();
    }

    return v == 0 ? 0.0 : v;
  }

  /// Ожидает синхронной сверки с Mode 01 (пара ≤ 1 c) — для честных подписей UI.
  bool get awaitingSyncCrosscheck =>
      status == 'observed_pending_synchronous_crosscheck';
}

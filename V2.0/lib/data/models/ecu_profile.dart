import 'ecu_parameter.dart';

/// Валидаторы ответа DID из профиля (не хардкод в коде приложения):
/// ожидаемая длина DATA, эмпирический якорь хвоста, лимит частоты опроса.
class DidValidators {
  final int? expectedDataLengthBytes;
  final int? tailAnchorOffset;
  final List<int>? tailAnchorBytes;
  final double? maxRateHz;

  DidValidators({
    this.expectedDataLengthBytes,
    this.tailAnchorOffset,
    this.tailAnchorBytes,
    this.maxRateHz,
  });

  factory DidValidators.fromJson(Map<String, dynamic> json) {
    int? anchorOffset;
    List<int>? anchorBytes;
    final anchor = json['tailAnchor'];
    if (anchor is Map<String, dynamic>) {
      anchorOffset = anchor['byteOffset'] as int?;
      final hex = anchor['bytes'] as String?;
      if (hex != null) {
        anchorBytes = RegExp(r'[0-9A-Fa-f]{2}')
            .allMatches(hex)
            .map((m) => int.parse(m.group(0)!, radix: 16))
            .toList();
      }
    }
    return DidValidators(
      expectedDataLengthBytes: json['expectedDataLengthBytes'] as int?,
      tailAnchorOffset: anchorOffset,
      tailAnchorBytes: anchorBytes,
      maxRateHz: (json['maxRateHz'] as num?)?.toDouble(),
    );
  }
}

/// Блок чтения по профилю. DID — ЧИСЛО (service 0x22); команда запроса
/// собирается единственным путём: ObdParser.buildReadDidCommand(did).
class EcuRequestBlock {
  final String name;
  final int did;
  final DidValidators? validators;
  final List<EcuParameter> parameters;

  EcuRequestBlock({
    required this.name,
    required this.did,
    this.validators,
    required this.parameters,
  });

  factory EcuRequestBlock.fromJson(Map<String, dynamic> json) {
    final v = json['validators'];
    return EcuRequestBlock(
      name: json['name'] as String,
      did: (json['did'] as num).toInt(),
      validators: v is Map<String, dynamic> ? DidValidators.fromJson(v) : null,
      parameters: (json['parameters'] as List)
          .map((p) => EcuParameter.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class EcuProfile {
  final String id;
  final String name;
  final List<EcuRequestBlock> blocks;

  EcuProfile({
    required this.id,
    required this.name,
    required this.blocks,
  });

  factory EcuProfile.fromJson(Map<String, dynamic> json) {
    return EcuProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      blocks: (json['blocks'] as List)
          .map((b) => EcuRequestBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

import 'ecu_parameter.dart';

class EcuRequestBlock {
  final String name;       // Название пакета (например, "Основные параметры")
  final String kwpCommand; // Команда для KWP2000 (например, "2101")
  final String udsCommand; // Команда для UDS (например, "222001")
  final List<EcuParameter> parameters;

  EcuRequestBlock({
    required this.name,
    required this.kwpCommand,
    required this.udsCommand,
    required this.parameters,
  });

  factory EcuRequestBlock.fromJson(Map<String, dynamic> json) {
    return EcuRequestBlock(
      name: json['name'] as String,
      kwpCommand: json['kwpCommand'] as String,
      udsCommand: json['udsCommand'] as String,
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

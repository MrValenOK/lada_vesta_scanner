class VehicleProfile {
  final String id;
  final String brand;
  final String model;
  final String engine;
  final String ecuProfileId; // Имя файла JSON без расширения (например, "m86_uds")

  VehicleProfile({
    required this.id,
    required this.brand,
    required this.model,
    required this.engine,
    required this.ecuProfileId,
  });

  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    return VehicleProfile(
      id: json['id'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      engine: json['engine'] as String,
      ecuProfileId: json['ecuProfileId'] as String,
    );
  }
}
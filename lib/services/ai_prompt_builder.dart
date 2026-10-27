class AiPromptBuilder {
  static String generateSnapshot({
    required Map<String, double> liveData,
    required double tripDistance,
    required double fuelConsumed,
    String userNotes = "",
  }) {
    final buffer = StringBuffer();
    
    buffer.writeln('Действуй как эксперт-автодиагност. Проанализируй лог телеметрии автомобиля Lada Vesta (ЭБУ Итэлма М86 UDS) и найди возможные аномалии.');
    if (userNotes.isNotEmpty) {
      buffer.writeln('Жалоба водителя: "$userNotes"');
    }
    
    buffer.writeln('\n--- ДАТЧИКИ ДВИГАТЕЛЯ (ТЕКУЩИЕ) ---');
    buffer.writeln('Обороты: ${liveData["rpm"]?.toInt() ?? 0} об/мин');
    buffer.writeln('Температура ОЖ: ${liveData["ect"]?.toInt() ?? 0} °C');
    
    // Безопасное извлечение коррекций, если они есть
    if (liveData.containsKey('stft')) {
      buffer.writeln('Краткосрочная коррекция (STFT): ${liveData["stft"]}%');
    }
    if (liveData.containsKey('ltft')) {
      buffer.writeln('Долгосрочная коррекция (LTFT): ${liveData["ltft"]}%');
    }

    buffer.writeln('\n--- ДАННЫЕ БОРТОВОГО КОМПЬЮТЕРА ---');
    buffer.writeln('Длительность текущей поездки: ${tripDistance.toStringAsFixed(1)} км');
    buffer.writeln('Потрачено топлива: ${fuelConsumed.toStringAsFixed(2)} л');

    buffer.writeln('\nТвоя задача:');
    buffer.writeln('1. Оцени адекватность показаний датчиков для текущего режима.');
    buffer.writeln('2. Если есть отклонения, назови 3 наиболее вероятные аппаратные причины.');
    buffer.writeln('3. Какие параметры мне нужно проверить дополнительно, чтобы сузить поиск?');

    return buffer.toString();
  }
}
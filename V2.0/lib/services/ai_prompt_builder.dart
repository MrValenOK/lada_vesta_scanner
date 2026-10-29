// lib/services/ai_prompt_builder.dart — текст «ИИ-Снапшота» (инженерный промпт в буфер).
// Вынесено из obd_provider (лимит 400 строк/файл). Сервис не знает о UI:
// принимает значения, возвращает строку.
import 'trip_calculator.dart';

class AiPromptBuilder {
  AiPromptBuilder._();

  static String build({
    required Map<String, double> liveData,
    required String ecuId,
    required bool isUds,
    required String rawLastBlock,
    required TripCalculator trip,
  }) {
    final d = liveData;
    final sb = StringBuffer();
    sb.writeln('Ты — ведущий инженер-диагност ЭСУД АвтоВАЗ (ТИ 3100.25100.12056).');
    sb.writeln('Проанализируй снапшот Lada Vesta (VestaScan Pro V2.0):');
    sb.writeln('• Калибровка ЭБУ: $ecuId | Протокол: ${isUds ? 'UDS (1003)' : 'KWP (1081)'}');
    sb.writeln('• Обороты: ${d['rpm']?.toInt() ?? '---'} об/мин | '
        'ТОЖ: ${d['ect']?.toInt() ?? '---'} °C');
    sb.writeln('• ДАД (010B): НЕТ ДАННЫХ (не поддерживается) | '
        'Нагрузка 0104: ${d['load']?.toStringAsFixed(1) ?? '---'}% | '
        'Дроссель: ${d['tps']?.toStringAsFixed(1) ?? '---'}%');
    sb.writeln('• Бортсеть: ${d['volt']?.toStringAsFixed(2) ?? '---'} В '
        '(мин. за сессию: ${d['min_volt']?.toStringAsFixed(2) ?? '---'} В)');
    sb.writeln('• Коррекции: STFT = ${d['stft']?.toStringAsFixed(1) ?? '---'}% | '
        'LTFT = ${d['ltft']?.toStringAsFixed(1) ?? '---'}%');
    sb.writeln('• ДК1/ДК2: ${d['udk']?.toStringAsFixed(2) ?? '---'} В | '
        '${d['ddk']?.toStringAsFixed(2) ?? '---'} В');
    sb.writeln('• БК (расчёт): воздух ~${d['air_mass_kgh']?.toStringAsFixed(1) ?? '---'} кг/ч | '
        'расход ${trip.instantFuelLpH.toStringAsFixed(2)} л/ч | '
        'пробег ${trip.totalDistanceKm.toStringAsFixed(2)} км');
    sb.writeln('• Последний ответ расширенного блока: $rawLastBlock');
    sb.writeln('');
    sb.writeln('Задача: 1) Оцени параметры ДВС, впуска и топливной системы. '
        '2) Укажи отклонения от заводских норм. 3) Какие проверки выполнить далее?');
    return sb.toString();
  }
}

// lib/features/journal/journal_csv.dart — CSV журнала (П5): UTF-8 с BOM,
// разделитель ';', колонки по заданию. Поля экранируются кавычками, значения
// снимка очищаются от единиц и получают десятичную запятую (Excel ru-RU).
import 'dart:convert';

import '../../providers/obd_state.dart';

class JournalCsv {
  static const String header =
      'Время;Тип;Событие;Значение;Обороты (010C);ТОЖ (°C);'
      'Бортсеть (В);STFT (%);LTFT (%);Скорость (км/ч)';

  /// CSV-текст: заголовок + по строке на событие (CRLF — для Excel).
  static String build(List<NuanceEvent> events) {
    final sb = StringBuffer()..write('$header\r\n');
    for (final e in events) {
      final s = e.snapshot;
      final cells = <String>[
        e.timeStr,
        e.severity.name.toUpperCase(),
        e.title,
        e.description,
        _num(s['RPM']),
        _num(s['ОЖ']),
        _num(s['Сеть']),
        _num(s['STFT']),
        _num(s['LTFT']),
        _num(s['Скорость']),
      ];
      sb.write('${cells.map(_cell).join(';')}\r\n');
    }
    return sb.toString();
  }

  /// UTF-8 + BOM (EF BB BF): Excel на ПК открывает кириллицу без искажений.
  static List<int> bytes(String csv) => utf8.encode('\uFEFF$csv');

  /// Числовое поле: убираем единицы, десятичную точку меняем на запятую.
  static String _num(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final cleaned = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    return cleaned.replaceAll('.', ',');
  }

  /// Кавычки обязательны: в описаниях бывают ';', кавычки и переводы строк.
  static String _cell(String v) => '"${v.replaceAll('"', '""')}"';
}

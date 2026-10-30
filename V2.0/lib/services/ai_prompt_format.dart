// lib/services/ai_prompt_format.dart — единое форматирование чисел для
// ИИ-Снапшота (вынесено из ai_prompt_builder, лимит 400 строк/файл).
// Одна точка правды: разделы телеметрии и UDS не могут разойтись в формате
// (десятичный разделитель, «—» вместо нуля, хвостовые нули формул).
class AiFmt {
  AiFmt._();

  /// Значение с единицей; null → «—» (не прочитано, НЕ ноль).
  static String val(double? v, int digits, String unit) {
    if (v == null) return '—';
    final s = v.toStringAsFixed(digits);
    return unit.isEmpty ? s : '$s $unit';
  }

  /// Целое без «.0» (90.0 → «90»), иначе — как есть.
  static String num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Число без хвостовых нулей (0.78125 → «0.78125», 48.0 → «48»).
  static String trim(double v, int maxDigits) {
    var s = v.toStringAsFixed(maxDigits);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return s;
  }

  /// Статус соединения словами (без выдумок о данных).
  static String link(bool connected, bool polling) {
    if (!connected) return 'НЕТ СВЯЗИ (данные не читались)';
    return polling ? 'на связи, опрос идёт' : 'на связи, опрос остановлен';
  }
}

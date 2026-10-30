// lib/providers/journal_logger.dart — журнал событий OBD-сессии: по-типовой
// cooldown (критичное — ≤2 с, предупреждения — 18 с, инфо — 25 с),
// HZ-группировка повторов (hzCount), снимок «живых» значений (RPM/ОЖ/Сеть/
// STFT/LTFT/скорость), лимит 500 записей и JSON-сериализация (П5).
// Вынесено из obd_provider (правило лимита 400 строк, AGENTS: вынос).
import 'obd_state.dart';

class JournalLogger {
  /// [maxEntries] — потолок записей: старшие вытесняются (как было в провайдере).
  JournalLogger({int maxEntries = 500}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final List<NuanceEvent> _list = [];
  final Map<String, DateTime> _lastTimes = {};

  /// Записи для UI (новые — первыми). Новый список-обёртка на каждый вызов:
  /// состояние провайдера получает неизменяемое представление.
  List<NuanceEvent> get entries => List.unmodifiable(_list);

  /// По-типовой кулдаун по важности: критичные события не прячем за 25 с.
  static int cooldownFor(NuanceSeverity severity) => switch (severity) {
        NuanceSeverity.critical => 2,
        NuanceSeverity.warning => 18,
        NuanceSeverity.info => 25,
      };

  /// Severity из строки (HealthMonitor не зависит от providers).
  static NuanceSeverity severityOf(String name) =>
      name == 'critical' ? NuanceSeverity.critical : NuanceSeverity.warning;

  /// Снимок «живых» значений на момент события — то, что водитель видит
  /// рядом с предупреждением (чего ещё не читали — в снимке нет).
  /// STFT/LTFT/скорость нужны и в CSV-экспорте (П5).
  static Map<String, String> snapshotOf(Map<String, double> liveData) =>
      <String, String>{
        if (liveData['rpm'] != null) 'RPM': '${liveData['rpm']!.toInt()}',
        if (liveData['ect'] != null) 'ОЖ': '${liveData['ect']!.toInt()}°C',
        if (liveData['volt'] != null)
          'Сеть': '${liveData['volt']!.toStringAsFixed(2)}В',
        if (liveData['stft'] != null)
          'STFT': '${liveData['stft']!.toStringAsFixed(1)}%',
        if (liveData['ltft'] != null)
          'LTFT': '${liveData['ltft']!.toStringAsFixed(1)}%',
        if (liveData['speed'] != null)
          'Скорость': '${liveData['speed']!.toInt()}',
      };

  /// Запись события. Повтор того же [id] раньше кулдауна (по важности или
  /// явно заданного) не пишется, но HZ-счётчик существующей записи растёт —
  /// частота повторов не теряется. Разные id не блокируют друг друга.
  /// true — событие записано (UI нужно обновить).
  bool log(
    String id,
    String title,
    String description,
    NuanceSeverity severity,
    Map<String, String> snapshot, {
    int? cooldownSec,
  }) {
    final now = DateTime.now();
    final cooldown = cooldownSec ?? cooldownFor(severity);
    final last = _lastTimes[id];
    if (last != null && now.difference(last).inSeconds < cooldown) {
      final idx = _list.indexWhere((e) => e.id == id);
      if (idx != -1) _list[idx].hzCount += 1;
      return false;
    }
    _lastTimes[id] = now;

    final idx = _list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final ex = _list.removeAt(idx);
      ex.hzCount += 1;
      ex.timestamp = now;
      ex.severity = severity;
      ex.title = title;
      ex.description = description;
      ex.snapshot = snapshot;
      _list.insert(0, ex);
    } else {
      _list.insert(
          0,
          NuanceEvent(
              id: id,
              timestamp: now,
              severity: severity,
              title: title,
              description: description,
              snapshot: snapshot));
    }
    if (_list.length > _maxEntries) {
      _list.removeRange(_maxEntries, _list.length);
    }
    return true;
  }

  /// JSON для shared_preferences (StorageService хранит последние 300).
  List<Map<String, dynamic>> toJson() => [
        for (final e in _list)
          {
            'id': e.id,
            'ts': e.timestamp.toIso8601String(),
            'sev': e.severity.name,
            'title': e.title,
            'desc': e.description,
            'snap': e.snapshot,
            'hz': e.hzCount,
          }
      ];

  /// Восстановление журнала после перезапуска: терпимо к битым записям,
  /// сортировка «новые первыми», cooldown-метки восстанавливаются.
  void loadJson(List<Map<String, dynamic>> raw) {
    _list.clear();
    _lastTimes.clear();
    for (final m in raw) {
      final id = (m['id'] ?? '').toString();
      final ts = DateTime.tryParse((m['ts'] ?? '').toString());
      if (id.isEmpty || ts == null) continue;
      final sev = NuanceSeverity.values.firstWhere((s) => s.name == m['sev'],
          orElse: () => NuanceSeverity.info);
      final snapRaw = m['snap'];
      final snap = <String, String>{};
      if (snapRaw is Map) {
        for (final e in snapRaw.entries) {
          snap[e.key.toString()] = e.value.toString();
        }
      }
      _list.add(NuanceEvent(
          id: id,
          timestamp: ts,
          severity: sev,
          title: (m['title'] ?? '').toString(),
          description: (m['desc'] ?? '').toString(),
          snapshot: snap,
          hzCount: (m['hz'] as num?)?.toInt() ?? 1));
    }
    _list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_list.length > _maxEntries) {
      _list.removeRange(_maxEntries, _list.length);
    }
    for (final e in _list) {
      final prev = _lastTimes[e.id];
      if (prev == null || e.timestamp.isAfter(prev)) {
        _lastTimes[e.id] = e.timestamp;
      }
    }
  }

  void clear() {
    _list.clear();
    _lastTimes.clear();
  }
}

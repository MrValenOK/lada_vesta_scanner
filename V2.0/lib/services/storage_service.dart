// lib/services/storage_service.dart — персистентность П5: журнал (последние
// 300 событий), последний успешно подключённый адаптер ELM327 и настройки.
// Компактный слой над shared_preferences; битые данные не роняют приложение
// (возвращаем пустое значение, а не исключение в UI).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String journalKey = 'journal_v1';
  static const String lastAdapterKey = 'last_adapter_v1';
  static const String settingsKey = 'settings_v1';
  static const int maxJournalEntries = 300;

  /// Журнал: новые записи первыми, хранится не больше [maxJournalEntries].
  Future<void> saveJournal(List<Map<String, dynamic>> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = entries.length > maxJournalEntries
          ? entries.sublist(0, maxJournalEntries)
          : entries;
      await prefs.setString(journalKey, jsonEncode(trimmed));
    } catch (_) {
      // Нет доступа к prefs — журнал продолжает жить в памяти.
    }
  }

  Future<List<Map<String, dynamic>>> loadJournal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(journalKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map) Map<String, dynamic>.from(e)
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearJournal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(journalKey);
    } catch (_) {
      // Очистка памяти уже выполнена вызывающим кодом.
    }
  }

  /// Последний успешный адаптер: MAC + имя (для автовыбора при старте).
  Future<void> saveLastAdapter(String address, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          lastAdapterKey, jsonEncode({'address': address, 'name': name}));
    } catch (_) {}
  }

  Future<Map<String, String>?> loadLastAdapter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastAdapterKey);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final address = (m['address'] ?? '').toString();
      if (address.isEmpty) return null;
      return {
        'address': address,
        'name': (m['name'] ?? address).toString(),
      };
    } catch (_) {
      return null;
    }
  }

  /// Настройки: тема/профиль (выбор пока в UI не выведен — П7/v4) и другие
  /// пользовательские ключи. merge: существующие ключи не теряются.
  Future<void> saveSettings(Map<String, Object?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadSettings();
      current.addAll(values);
      await prefs.setString(settingsKey, jsonEncode(current));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(settingsKey);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

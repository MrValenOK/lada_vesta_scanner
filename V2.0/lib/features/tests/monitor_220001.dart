// lib/features/tests/monitor_220001.dart — мониторинг блока 220001 (1 Гц).
// Назначение: реверс структуры блока — пользователь заводит машину, включает
// мониторинг и видит, какие байты меняются при газе.
// Контракт (живой дамп 2026-10-29): 220001 читается в DEFAULT SESSION —
// никакого 1003 перед чтением; ответ многокадровый, собирается extractBytes.
// Вывод: HEX байт-за-байтом; байты, изменившиеся с прошлого тика, помечаются Δ.
import 'dart:async';

import '../../services/obd_parser.dart';

class Monitor220001 {
  Monitor220001({
    required this.send,
    required this.log,
    required this.isConnected,
  });

  /// Отправка команды (провайдерный sendCommandForSniffer).
  final Future<String> Function(String cmd, {int timeoutMs, int postDelayMs})
      send;
  final void Function(String line) log;
  final bool Function() isConnected;

  Timer? _timer;
  bool _tickBusy = false;
  List<int>? _prev;

  bool get isOn => _timer != null;

  void start() {
    _prev = null;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick(); // первый замер сразу
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_timer == null || _tickBusy) return;
    if (!isConnected()) {
      stop();
      log('[MON] Связь потеряна — мониторинг остановлен');
      return;
    }
    _tickBusy = true;
    try {
      final t = DateTime.now();
      final ts = '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}:'
          '${t.second.toString().padLeft(2, '0')}';

      final resp =
          await send('220001', timeoutMs: 2000, postDelayMs: 250);
      if (_timer == null) return; // остановлен во время ожидания

      final bytes = ObdParser.extractBytes(resp, '620001');
      if (bytes == null || bytes.isEmpty) {
        log('$ts 220001 => нет данных (${resp.replaceAll('\n', ' | ')})');
        return;
      }

      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

      var diff = '';
      final prev = _prev;
      if (prev != null && prev.length == bytes.length) {
        final changed = <int>[];
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] != prev[i]) changed.add(i);
        }
        if (changed.isNotEmpty) diff = '  Δ[${changed.join(',')}]';
      }
      _prev = bytes;
      log('$ts 220001 => $hex$diff');
    } finally {
      _tickBusy = false;
    }
  }
}

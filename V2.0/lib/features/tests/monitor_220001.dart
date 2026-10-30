// lib/features/tests/monitor_220001.dart — мониторинг блока 220001 (1 Гц).
// Ручной исследовательский захват: пользователь явно включает его на экране
// «Анализ». DID — число, команда/префикс собираются единственным путём;
// ответ проверяется валидаторами профиля (длина, якорь хвоста) ДО вывода.
// Отклонённые кадры помечаются причиной; Δ — только вспомогательный сигнал.
import 'dart:async';

import '../../data/models/ecu_profile.dart';
import '../../services/obd_parser.dart';
import '../../services/uds_sample.dart';

class Monitor220001 {
  Monitor220001({
    required this.send,
    required this.log,
    required this.isConnected,
    this.did = 1,
    this.validators,
  });

  /// Отправка команды (провайдерный sendCommandForSniffer).
  final Future<String> Function(String cmd, {int timeoutMs, int postDelayMs})
      send;
  final void Function(String line) log;
  final bool Function() isConnected;
  final int did;
  final DidValidators? validators;

  Timer? _timer;
  bool _tickBusy = false;
  List<int>? _prevAccepted;

  bool get isOn => _timer != null;

  void start() {
    _prevAccepted = null;
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

      final resp = await send(ObdParser.buildReadDidCommand(did),
          timeoutMs: 2000, postDelayMs: 250);
      if (_timer == null) return; // остановлен во время ожидания

      final payload =
          ObdParser.extractBytes(resp, ObdParser.positiveDidPrefix(did));
      final sample = validateDidSample(payload, validators,
          previousAccepted: _prevAccepted);
      if (!sample.accepted) {
        log('$ts 220001 => отклонён: ${sample.rejectReason}'
            ' (${resp.replaceAll('\n', ' | ')})');
        return;
      }
      if (sample.flags.contains('cf_suspect')) {
        log('$ts 220001 => ⚠ cf_suspect: ниббл-сдвиг хвоста vs предыдущий принятый '
            'кадр; причина повреждения без сырого трейса не доказана');
      }

      final bytes = sample.data!;
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

      var diff = '';
      final prev = _prevAccepted;
      if (prev != null && prev.length == bytes.length) {
        final changed = <int>[];
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] != prev[i]) changed.add(i);
        }
        if (changed.isNotEmpty) diff = '  Δ[${changed.join(',')}]';
      }
      _prevAccepted = bytes;
      log('$ts 220001 => $hex$diff');
    } finally {
      _tickBusy = false;
    }
  }
}

// lib/services/bluetooth_service.dart — транспорт ELM327 (Bluetooth Classic SPP). V2.1.
//
// КЛЮЧЕВОЕ ЗНАНИЕ О ПЛАГИНЕ flutter_bluetooth_classic_serial 1.3.2
// (проверено по исходникам плагина и полевым тестом в автомобиле):
//  • _bt.connect() возвращает true СРАЗУ: нативный socket.connect() выполняется
//    в фоновой корутине и поднимает RFCOMM через ~1–1,5 с. До этого sendData
//    кидает PlatformException(NOT_CONNECTED).
//  • Поэтому после connect() обязательна двусторонняя проверка готовности
//    _waitForSocketReady(): шлём 'AT\r' и ждём ответ с '>'. Только после неё
//    состояние = connected и разрешена инициализация.
//  • Если socket.connect() падает (флаки RFCOMM у клонов — обычное дело),
//    плагин шлёт событие isConnected:false со status 'ERROR: ...'. V2.1 ловит
//    это событие, прерывает рукопожатие и делает ПОВТОР всего цикла (до 2 раз)
//    с чисткой сокета — вместо 10-секундного ожидания и общей ошибки.
//  • Причина отказа всегда сохраняется в lastError (текст исключения/статуса) —
//    молчаливых ошибок нет.
//
// Инициализация — проверенный боем набор (рабочий проект lada_vesta_scanner
// v3.0.0, работает в автомобиле): ATZ + критичные ATE0/ATL0/ATS0/ATH0/ATSP6/
// ATSH7E0/ATCRA7E8 (порог okCritical >= 6) + опциональные ATAL/ATCAF1/
// ATFCSH7E0/ATFCSD300000/ATFCSM1 (полный flow control, «Рамки» plan.md).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

enum BtConnectionState { disconnected, connecting, connected, error }

class BluetoothService {
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();
  final StringBuffer _rxBuffer = StringBuffer();

  final ValueNotifier<BtConnectionState> _state =
      ValueNotifier(BtConnectionState.disconnected);
  ValueNotifier<BtConnectionState> get stateNotifier => _state;
  BtConnectionState get state => _state.value;
  bool get isConnected => _state.value == BtConnectionState.connected;

  /// Причина последнего отказа подключения (для UI/лога). Молчаливых ошибок нет.
  String? _lastError;
  String? get lastError => _lastError;

  Completer<void>? _cmdLock;
  StreamSubscription? _dataSub;
  StreamSubscription? _connSub;
  bool _subsReady = false;

  /// Отказ нативного socket.connect() от плагина (status 'ERROR: ...').
  bool _connFailed = false;
  String? _connFailStatus;

  void _ensureSubscriptions() {
    if (_subsReady) return;
    _subsReady = true;

    _connSub = _bt.onConnectionChanged.listen(
      (s) {
        if (s.isConnected) {
          _connFailed = false;
          return;
        }
        // Отказ нативного socket.connect() — в отличие от обрыва уже поднятой
        // связи (status 'DISCONNECTED: ...') и ошибки записи ('WRITE_ERROR: ...')
        if (_state.value == BtConnectionState.connecting &&
            s.status.startsWith('ERROR')) {
          _connFailed = true;
          _connFailStatus = s.status;
        }
        if (_state.value == BtConnectionState.connected) {
          _state.value = BtConnectionState.disconnected;
          _rxBuffer.clear();
        }
      },
      onError: (e) => debugPrint('[BT] conn stream error: $e'),
    );

    // utf8 с allowMalformed — как в боевом старом коде; битые байты безопасны,
    // т.к. парсер всё равно срезает любые не-Hex символы.
    _dataSub = _bt.onDataReceived.listen(
      (d) => _rxBuffer.write(utf8.decode(d.data, allowMalformed: true)),
      onError: (e) => debugPrint('[BT] data stream error: $e'),
    );
  }

  Future<List<Map<String, String>>> getPairedDevices() async {
    try {
      final list = await _bt.getPairedDevices();
      final uniq = <String, BluetoothDevice>{};
      for (final d in list) {
        if (d.address.isNotEmpty) uniq[d.address] = d;
      }
      return uniq.values
          .map((d) => <String, String>{
                'name': d.name.isNotEmpty ? d.name : d.address,
                'address': d.address,
              })
          .toList();
    } catch (e) {
      debugPrint('[BT] getPairedDevices: $e');
      return [];
    }
  }

  /// Подключение: до 2 попыток «socket + рукопожатие» с чисткой сокета между
  /// ними. Причина отказа — в lastError (текст исключения/статуса плагина).
  Future<bool> connect(String address) async {
    if (isConnected) return true; // уже подключены — не рвём рабочую сессию
    _ensureSubscriptions();
    _lastError = null;

    try {
      if (!await _bt.isBluetoothEnabled()) {
        _lastError = 'Bluetooth выключен на телефоне';
        _state.value = BtConnectionState.error;
        return false;
      }
    } catch (e) {
      debugPrint('[BT] isBluetoothEnabled: $e');
    }

    for (int attempt = 1; attempt <= 2; attempt++) {
      _state.value = BtConnectionState.connecting;
      _connFailed = false;
      _connFailStatus = null;

      try {
        final ok = await _bt.connect(address);
        if (!ok) {
          _lastError = 'Плагин не подтвердил подключение';
          _state.value = BtConnectionState.error;
          return false;
        }
      } catch (e) {
        _lastError = _describeConnectError(e);
        _state.value = BtConnectionState.error;
        return false; // разрешения/адрес — повтор бессмысленен
      }

      if (await _waitForSocketReady()) {
        _state.value = BtConnectionState.connected;
        return true;
      }

      _lastError =
          _connFailStatus ?? 'ELM327 не ответил на AT (таймаут рукопожатия)';
      debugPrint('[BT] попытка $attempt не удалась: $_lastError');
      try {
        await _bt.disconnect(); // чистим сокет перед повтором
      } catch (_) {}
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    _state.value = BtConnectionState.error;
    return false;
  }

  String _describeConnectError(Object e) {
    final s = e.toString();
    if (s.contains('PERMISSION_DENIED')) {
      return 'Нужно разрешение Bluetooth — выдайте его в системном диалоге и повторите';
    }
    if (s.contains('DEVICE_NOT_FOUND')) {
      return 'Устройство не найдено — проверьте сопряжение ELM327';
    }
    if (s.contains('BLUETOOTH_UNAVAILABLE')) {
      return 'Bluetooth недоступен на телефоне';
    }
    return s;
  }

  /// Двусторонняя проверка готовности RFCOMM и UART ELM327:
  /// шлём 'AT\r' и ждём реального ответа с '>' от адаптера.
  /// Прерывается досрочно, если плагин сообщил об отказе socket.connect().
  Future<bool> _waitForSocketReady() async {
    // Остатки прошлой сессии не должны дать ложное «готово»
    _rxBuffer.clear();
    await Future.delayed(const Duration(milliseconds: 350));
    for (int attempt = 1; attempt <= 10; attempt++) {
      if (_connFailed) return false;
      try {
        await _bt.sendString('AT\r');
        final sw = Stopwatch()..start();
        while (sw.elapsedMilliseconds < 600) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (_rxBuffer.toString().contains('>')) return true;
        }
      } catch (e) {
        debugPrint('[BT] сокет не готов ($attempt/10): $e');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> disconnect() async {
    _rxBuffer.clear();
    try {
      await _bt.disconnect();
    } catch (_) {}
    _state.value = BtConnectionState.disconnected;
  }

  /// Инициализация адаптера. Возвращает true, если применились все критичные
  /// команды (без них ответы приходят с '7E8' и пробелами — byteOffset в
  /// m86_uds.json ломается молча).
  Future<bool> initializeAdapter() async {
    // ATZ — холодный ресет; на клонах бывает долгим, ответ ждём до 1.8 с.
    final z = await sendCommand('ATZ', timeoutMs: 1800, postDelayMs: 250);
    if (z.startsWith('ERR:')) debugPrint('[BT] ATZ: $z — продолжаем');

    const critical = <String>[
      'ATE0',
      'ATL0',
      'ATS0',
      'ATH0',
      'ATSP6',
      'ATSH7E0',
      'ATCRA7E8',
    ];
    int okCritical = 0;
    for (final cmd in critical) {
      final r = await sendCommand(cmd, timeoutMs: 900, postDelayMs: 60);
      if (!r.startsWith('ERR:') && !r.contains('?')) {
        okCritical++;
      } else {
        debugPrint('[BT] критичная команда $cmd не принята: $r');
      }
    }

    const optional = <String>[
      'ATAL',
      'ATCAF1',
      'ATFCSH7E0',
      'ATFCSD300000',
      'ATFCSM1',
    ];
    for (final cmd in optional) {
      final r = await sendCommand(cmd, timeoutMs: 700, postDelayMs: 50);
      if (r.startsWith('ERR:') || r.contains('?')) {
        debugPrint('[BT] опциональная команда $cmd не принята: $r');
      }
    }

    final ok = okCritical >= 6;
    if (!ok) debugPrint('[BT] init частичный: $okCritical/7 критичных');
    return ok;
  }

  /// Отправка команды. Возвращает ответ без эха и '>' либо 'ERR:...'.
  /// Коды ошибок: ERR:NOT_CONNECTED | ERR:TIMEOUT | ERR:<текст>.
  Future<String> sendCommand(
    String cmd, {
    int timeoutMs = 1200,
    int postDelayMs = 120,
  }) async {
    if (_state.value != BtConnectionState.connected &&
        _state.value != BtConnectionState.connecting) {
      return 'ERR:NOT_CONNECTED';
    }

    while (_cmdLock != null) {
      try {
        await _cmdLock!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        _cmdLock = null;
        break;
      }
    }

    final lock = Completer<void>();
    _cmdLock = lock;
    try {
      _rxBuffer.clear();
      try {
        await _bt.sendString('$cmd\r');
      } catch (e) {
        if (e.toString().contains('NOT_CONNECTED')) {
          // Сокет ещё поднимается — один повтор после паузы.
          await Future.delayed(const Duration(milliseconds: 250));
          _rxBuffer.clear();
          await _bt.sendString('$cmd\r');
        } else {
          rethrow;
        }
      }

      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < timeoutMs) {
        await Future.delayed(const Duration(milliseconds: 25));
        final cur = _rxBuffer.toString();
        if (cur.contains('>')) {
          if (postDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: postDelayMs));
          }
          return _cleanRaw(cur, cmd);
        }
      }
      return 'ERR:TIMEOUT';
    } catch (e) {
      return 'ERR:$e';
    } finally {
      _cmdLock = null;
      if (!lock.isCompleted) lock.complete();
    }
  }

  /// Снимает эхо команды, '>', пустые строки; строки склеивает через ' | '.
  String _cleanRaw(String raw, String sentCmd) {
    var s = raw.replaceAll('>', '').replaceAll('\r', '\n');
    final lines = s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.toUpperCase() != sentCmd.toUpperCase())
        .toList();
    return lines.join(' | ').trim();
  }

  void clearBuffer() => _rxBuffer.clear();

  void dispose() {
    _dataSub?.cancel();
    _connSub?.cancel();
    _state.dispose();
  }
}

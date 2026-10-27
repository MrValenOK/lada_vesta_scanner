import 'dart:async';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class BluetoothService {
  final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();
  final StringBuffer _rxBuffer = StringBuffer();
  
  Completer<void>? _cmdLock;
  bool _isConnected = false;
  StreamSubscription? _dataSubscription;

  bool get isConnected => _isConnected;

  /// Инициализация и подключение к ELM327
  Future<bool> connect(String address) async {
    try {
      await _bt.connect(address);
      _isConnected = true;
      
      // Подписка на входящий поток байтов
      _dataSubscription = _bt.onDataReceived.listen((data) {
        // Конвертируем байты в строку и добавляем в буфер
        _rxBuffer.write(String.fromCharCodes(data.data));
      });
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  /// Отключение
  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await _bt.disconnect();
    } finally {
      _isConnected = false;
    }
  }

  /// Главный метод отправки команд с защитой от одновременных запросов
  Future<String> sendCommand(
    String cmd, {
    int timeoutMs = 1200,
    int postDelayMs = 50,
  }) async {
    if (!_isConnected) return 'ERR:NOT_CONNECTED';

    // Очередь команд: ждем, если шина занята
    while (_cmdLock != null) {
      await _cmdLock!.future;
    }
    
    final lock = Completer<void>();
    _cmdLock = lock;

    try {
      _rxBuffer.clear();
      // Отправляем команду с символом возврата каретки (требование ELM327)
      await _bt.sendString('$cmd\r');

      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < timeoutMs) {
        await Future.delayed(const Duration(milliseconds: 20));
        final current = _rxBuffer.toString();
        
        // Как только прилетел символ '>', адаптер закончил передачу
        if (current.contains('>')) {
          if (postDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: postDelayMs));
          }
          // Очищаем ответ от символа '>' и лишних пробелов
          return current.replaceAll('>', '').replaceAll('\r', '\n').trim();
        }
      }
      
      // Если уперлись в таймаут, отдаем то, что успели получить
      return _rxBuffer.toString().trim();
    } catch (e) {
      return 'ERR:$e';
    } finally {
      _cmdLock = null;
      lock.complete();
    }
  }
}
import 'dart:async';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class BluetoothService {
  final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();
  final StringBuffer _rxBuffer = StringBuffer();
  
  Completer<void>? _cmdLock;
  bool _isConnected = false;
  StreamSubscription? _dataSubscription;

  bool get isConnected => _isConnected;

  Future<List<Map<String, String>>> getPairedDevices() async {
    try {
      final devices = await _bt.getPairedDevices();
      return devices.map((d) => {'name': d.name, 'address': d.address}).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    try {
      await _bt.connect(address);
      _isConnected = true;
      _dataSubscription = _bt.onDataReceived.listen((data) {
        _rxBuffer.write(String.fromCharCodes(data.data));
      });
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await _bt.disconnect();
    } finally {
      _isConnected = false;
    }
  }

  Future<String> sendCommand(String cmd, {int timeoutMs = 1200, int postDelayMs = 50}) async {
    if (!_isConnected) return 'ERR:NOT_CONNECTED';
    while (_cmdLock != null) {
      await _cmdLock!.future;
    }
    final lock = Completer<void>();
    _cmdLock = lock;

    try {
      _rxBuffer.clear();
      await _bt.sendString('$cmd\r');
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < timeoutMs) {
        await Future.delayed(const Duration(milliseconds: 20));
        final current = _rxBuffer.toString();
        if (current.contains('>')) {
          if (postDelayMs > 0) await Future.delayed(Duration(milliseconds: postDelayMs));
          return current.replaceAll('>', '').replaceAll('\r', '\n').trim();
        }
      }
      return _rxBuffer.toString().trim();
    } catch (e) {
      return 'ERR:$e';
    } finally {
      _cmdLock = null;
      lock.complete();
    }
  }
}
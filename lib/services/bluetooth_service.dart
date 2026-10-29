import 'dart:async';
import 'dart:convert';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();
  final StringBuffer _rxBuffer = StringBuffer();
  Completer<void>? _cmdLock;
  bool _isConnected = false;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connSubscription;

  bool get isConnected => _isConnected;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final list = await _bt.getPairedDevices();
      final unique = <String, BluetoothDevice>{};
      for (final d in list) {
        if (d.address.isNotEmpty) unique[d.address] = d;
      }
      return unique.values.toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    if (_isConnected) return true;
    try {
      final ok = await _bt.connect(address);
      _isConnected = ok;
      await _dataSubscription?.cancel();
      await _connSubscription?.cancel();

      _connSubscription = _bt.onConnectionChanged.listen((state) {
        _isConnected = state.isConnected;
      });
      _dataSubscription = _bt.onDataReceived.listen((data) {
        _rxBuffer.write(utf8.decode(data.data, allowMalformed: true));
      });
      return ok;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await _connSubscription?.cancel();
      await _bt.disconnect();
    } finally {
      _isConnected = false;
    }
  }

  Future<String> sendCommand(String cmd, {int timeoutMs = 1100, int postDelayMs = 60}) async {
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
        await Future.delayed(const Duration(milliseconds: 25));
        if (_rxBuffer.toString().contains('>')) {
          if (postDelayMs > 0) await Future.delayed(Duration(milliseconds: postDelayMs));
          return _rxBuffer.toString().replaceAll('>', '').replaceAll('\r', '\n').trim();
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
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ecu_profile.dart';
import '../services/bluetooth_service.dart';
import '../services/obd_parser.dart';
import '../services/trip_calculator.dart';

class ObdState {
  final bool isConnected;
  final bool isPolling;
  final Map<String, double> liveData;
  final List<double> trace1;

  ObdState({
    this.isConnected = false,
    this.isPolling = false,
    this.liveData = const {},
    this.trace1 = const [],
  });

  ObdState copyWith({
    bool? isConnected,
    bool? isPolling,
    Map<String, double>? liveData,
    List<double>? trace1,
  }) {
    return ObdState(
      isConnected: isConnected ?? this.isConnected,
      isPolling: isPolling ?? this.isPolling,
      liveData: liveData ?? this.liveData,
      trace1: trace1 ?? this.trace1,
    );
  }
}

final bluetoothServiceProvider = Provider((ref) => BluetoothService());

final obdProvider = StateNotifierProvider<ObdNotifier, ObdState>((ref) {
  return ObdNotifier(ref.read(bluetoothServiceProvider));
});

class ObdNotifier extends StateNotifier<ObdState> {
  final BluetoothService _btService;
  Timer? _pollTimer;
  final TripCalculator tripCalculator = TripCalculator();
  EcuProfile? _ecuProfile;
  bool _isUdsM86 = false;
  bool _isPollCycleBusy = false;

  ObdNotifier(this._btService) : super(ObdState()) {
    _loadJsonProfile();
  }

  Future<void> _loadJsonProfile() async {
    try {
      final jsonString = await rootBundle.loadString('lib/data/json_profiles/m86_uds.json');
      final jsonMap = json.decode(jsonString);
      _ecuProfile = EcuProfile.fromJson(jsonMap);
    } catch (e) {
      // Здесь можно добавить логирование, если файл не найден
    }
  }

  Future<bool> connect(String macAddress) async {
    final success = await _btService.connect(macAddress);
    if (!success) return false;

    final initCmds = [
      'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 
      'ATSP6', 'ATAL', 'ATSH7E0', 'ATCRA7E8'
    ];
    for (final cmd in initCmds) {
      await _btService.sendCommand(cmd, timeoutMs: 500);
    }

    final r1081 = (await _btService.sendCommand('1081', timeoutMs: 1000)).replaceAll(' ', '');
    final r1003 = (await _btService.sendCommand('1003', timeoutMs: 1000)).replaceAll(' ', '');

    final kwpOk = r1081.contains('5081');
    final udsOk = r1003.contains('5003');
    
    _isUdsM86 = !kwpOk && udsOk;

    state = state.copyWith(isConnected: true);
    return true;
  }

  void startPolling() {
    if (!state.isConnected || state.isPolling) return;
    state = state.copyWith(isPolling: true);

    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      await _pollCycle();
    });
  }

  Future<void> _pollCycle() async {
    if (_isPollCycleBusy || _ecuProfile == null || _ecuProfile!.blocks.isEmpty) return;
    _isPollCycleBusy = true;

    try {
      final block = _ecuProfile!.blocks.first;
      final cmd = _isUdsM86 ? block.udsCommand : block.kwpCommand;
      final prefix = _isUdsM86 ? '622001' : '6101';
      
      final response = await _btService.sendCommand(cmd);
      final bytes = ObdParser.extractBytes(response, prefix);

      final updatedData = Map<String, double>.from(state.liveData);
      
      if (bytes != null) {
        for (final param in block.parameters) {
          final val = param.decode(bytes);
          if (val != null) {
            updatedData[param.id] = val;
          }
        }
      }

      // Отдельно опрашиваем стандартный PID скорости (010D)
      final speedResp = await _btService.sendCommand('010D');
      final speedBytes = ObdParser.extractBytes(speedResp, '410D');
      if (speedBytes != null && speedBytes.isNotEmpty) {
        updatedData['speed'] = speedBytes[0].toDouble();
      }

      final updatedTrace = List<double>.from(state.trace1);
      if (updatedData.containsKey('rpm')) {
        updatedTrace.add(updatedData['rpm']!);
        if (updatedTrace.length > 100) {
          updatedTrace.removeAt(0);
        }
      }

      // Расчет расхода воздуха (псевдо ДМРВ по MAP и оборотам)
      final mapVal = updatedData['map'] ?? 30.0;
      final rpmVal = updatedData['rpm'] ?? 0.0;
      final pseudoAirMass = (mapVal * rpmVal) / 1000.0;

      // Обновляем калькулятор поездки
      tripCalculator.update(
        rpm: rpmVal.toInt(),
        speedKmh: updatedData['speed'] ?? 0.0,
        airMassKgH: pseudoAirMass,
        tpsPct: updatedData['tps'] ?? 0.0,
        isDfcoActive: false, // Отсечка также рассчитывается внутри по TPS и RPM
        stftPct: updatedData['stft'] ?? 0.0,
        ltftPct: updatedData['ltft'] ?? 0.0,
      );

      state = state.copyWith(
        liveData: updatedData,
        trace1: updatedTrace,
      );
    } catch (e) {
      // Пропускаем ошибки на единичных пакетах
    } finally {
      _isPollCycleBusy = false;
    }
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = state.copyWith(isPolling: false);
  }
}

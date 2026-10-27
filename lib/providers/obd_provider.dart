import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bluetooth_service.dart';

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
  bool _isPollCycleBusy = false;
  double _demoSineWave = 0.0;

  ObdNotifier(this._btService) : super(ObdState());

  Future<bool> connect(String macAddress) async {
    state = state.copyWith(isConnected: true);
    return true;
  }

  Future<void> disconnect() async {
    stopPolling();
    await _btService.disconnect();
    state = state.copyWith(isConnected: false, liveData: {}, trace1: []);
  }

  void startPolling() {
    if (!state.isConnected || state.isPolling) return;
    state = state.copyWith(isPolling: true);

    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      await _pollCycle();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = state.copyWith(isPolling: false);
  }

  Future<void> _pollCycle() async {
    if (_isPollCycleBusy) return;
    _isPollCycleBusy = true;

    try {
      _demoSineWave += 0.2;
      final double simulatedValue = (math.sin(_demoSineWave) * 400) + 800;

      final updatedData = Map<String, double>.from(state.liveData);
      updatedData['rpm'] = simulatedValue;
      updatedData['ect'] = 88.0;

      final updatedTrace = List<double>.from(state.trace1);
      updatedTrace.add(simulatedValue);
      if (updatedTrace.length > 100) {
        updatedTrace.removeAt(0);
      }

      state = state.copyWith(liveData: updatedData, trace1: updatedTrace);
    } finally {
      _isPollCycleBusy = false;
    }
  }
}
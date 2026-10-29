// lib/providers/obd_state.dart — состояние OBD-сессии и модель события журнала.
enum NuanceSeverity { info, warning, critical }

class NuanceEvent {
  final String id;
  DateTime timestamp;
  NuanceSeverity severity;
  String title;
  String description;
  Map<String, String> snapshot;
  int hzCount;

  NuanceEvent({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.title,
    required this.description,
    required this.snapshot,
    this.hzCount = 1,
  });

  String get timeStr => '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';
}

class ObdState {
  final bool isConnected;
  final bool isPolling;
  final bool initOk;
  final String connectedDevice;
  final String ecuId;
  final String ecuType;
  final bool isUds;
  final String statusText;
  final Map<String, double> liveData;
  final List<double> trace1; // УДК (0..1.8 В)
  final List<double> trace2; // ДДК (0..1.8 В)
  final String rawLastBlock1;
  final List<NuanceEvent> nuances;
  final List<String> dtcList;
  final String? lastError;

  ObdState({
    this.isConnected = false,
    this.isPolling = false,
    this.initOk = false,
    this.connectedDevice = '---',
    this.ecuId = '---',
    this.ecuType = 'Итэлма М86',
    this.isUds = true,
    this.statusText = 'Выберите адаптер и нажмите Старт',
    this.liveData = const {},
    this.trace1 = const [],
    this.trace2 = const [],
    this.rawLastBlock1 = '---',
    this.nuances = const [],
    this.dtcList = const [],
    this.lastError,
  });

  ObdState copyWith({
    bool? isConnected,
    bool? isPolling,
    bool? initOk,
    String? connectedDevice,
    String? ecuId,
    String? ecuType,
    bool? isUds,
    String? statusText,
    Map<String, double>? liveData,
    List<double>? trace1,
    List<double>? trace2,
    String? rawLastBlock1,
    List<NuanceEvent>? nuances,
    List<String>? dtcList,
    String? lastError,
  }) {
    return ObdState(
      isConnected: isConnected ?? this.isConnected,
      isPolling: isPolling ?? this.isPolling,
      initOk: initOk ?? this.initOk,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      ecuId: ecuId ?? this.ecuId,
      ecuType: ecuType ?? this.ecuType,
      isUds: isUds ?? this.isUds,
      statusText: statusText ?? this.statusText,
      liveData: liveData ?? this.liveData,
      trace1: trace1 ?? this.trace1,
      trace2: trace2 ?? this.trace2,
      rawLastBlock1: rawLastBlock1 ?? this.rawLastBlock1,
      nuances: nuances ?? this.nuances,
      dtcList: dtcList ?? this.dtcList,
      // Фикс V2.0: lastError НЕ стирается при каждом copyWith (в старом коде стирался).
      lastError: lastError ?? this.lastError,
    );
  }
}

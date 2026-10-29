import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bluetooth_service.dart';
import '../services/obd_parser.dart';
import '../services/trip_calculator.dart';
import '../data/models/ecu_profile.dart';

// ===== МОДЕЛЬ СОБЫТИЯ ЖУРНАЛА =====
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

  String get timeStr =>
      "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
}

// ===== СОСТОЯНИЕ =====
class ObdState {
  final bool isConnected;
  final bool isPolling;
  final String connectedDevice;
  final String ecuId;
  final String ecuType;
  final bool isUdsM86; // Оставил псевдоним для совместимости с его кодом, если где-то используется
  final bool isUds;
  final String statusText;
  final Map<String, double> liveData;
  final List<double> trace1; // УДК (0..1.8 В)
  final List<double> trace2; // ДДК (0..1.8 В)
  final bool isRunningSniffer;
  final String snifferDump;
  final String rawLastBlock1;
  final List<NuanceEvent> nuances;
  final List<String> dtcList;
  final String? lastError;

  ObdState({
    this.isConnected = false,
    this.isPolling = false,
    this.connectedDevice = '---',
    this.ecuId = '---',
    this.ecuType = 'Итэлма М86',
    this.isUds = true,
    this.isUdsM86 = true,
    this.statusText = 'Выберите адаптер и нажмите Старт',
    this.liveData = const {},
    this.trace1 = const [],
    this.trace2 = const [],
    this.isRunningSniffer = false,
    this.snifferDump = 'Нажмите «Снять HEX-дамп», чтобы опросить регистры KWP/UDS (222001, 220401 и др.).',
    this.rawLastBlock1 = '---',
    this.nuances = const [],
    this.dtcList = const [],
    this.lastError,
  });

  ObdState copyWith({
    bool? isConnected,
    bool? isPolling,
    String? connectedDevice,
    String? ecuId,
    String? ecuType,
    bool? isUds,
    bool? isUdsM86,
    String? statusText,
    Map<String, double>? liveData,
    List<double>? trace1,
    List<double>? trace2,
    bool? isRunningSniffer,
    String? snifferDump,
    String? rawLastBlock1,
    List<NuanceEvent>? nuances,
    List<String>? dtcList,
    String? lastError,
  }) {
    return ObdState(
      isConnected: isConnected ?? this.isConnected,
      isPolling: isPolling ?? this.isPolling,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      ecuId: ecuId ?? this.ecuId,
      ecuType: ecuType ?? this.ecuType,
      isUds: isUds ?? this.isUds,
      isUdsM86: isUdsM86 ?? this.isUdsM86,
      statusText: statusText ?? this.statusText,
      liveData: liveData ?? this.liveData,
      trace1: trace1 ?? this.trace1,
      trace2: trace2 ?? this.trace2,
      isRunningSniffer: isRunningSniffer ?? this.isRunningSniffer,
      snifferDump: snifferDump ?? this.snifferDump,
      rawLastBlock1: rawLastBlock1 ?? this.rawLastBlock1,
      nuances: nuances ?? this.nuances,
      dtcList: dtcList ?? this.dtcList,
      lastError: lastError,
    );
  }
}

final bluetoothServiceProvider = Provider((ref) => BluetoothService());

final obdProvider = StateNotifierProvider<ObdNotifier, ObdState>((ref) {
  return ObdNotifier(ref.read(bluetoothServiceProvider));
});

class ObdNotifier extends StateNotifier<ObdState> {
  final BluetoothService _btService;
  bool _isCycleBusy = false;
  int _cycle = 0;
  int _consecutiveErrors = 0;
  EcuProfile? _ecuProfile;
  final TripCalculator tripCalculator = TripCalculator();
  final Map<String, DateTime> _lastNuanceTimes = {};

  ObdNotifier(this._btService) : super(ObdState()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final jsonString = await rootBundle.loadString('lib/data/json_profiles/m86_uds.json');
      _ecuProfile = EcuProfile.fromJson(jsonDecode(jsonString));
    } catch (_) {}
  }

  Future<bool> connect(String macAddress) async {
    state = state.copyWith(statusText: 'Подключение к $macAddress...');
    final success = await _btService.connect(macAddress);
    if (!success) {
      state = state.copyWith(isConnected: false, statusText: 'Ошибка подключения к ELM327');
      return false;
    }

    for (final cmd in [
      'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6',
      'ATAL', 'ATCAF1', 'ATSH7E0', 'ATCRA7E8', 'ATFCSH7E0', 'ATFCSD300000', 'ATFCSM1'
    ]) {
      await _btService.sendCommand(cmd, timeoutMs: cmd == 'ATZ' ? 1800 : 500);
    }

    // Паспорт ЭБУ (0904)
    String ecuId = state.ecuId;
    final idBytes = ObdParser.extractBytes(await _btService.sendCommand('0904', timeoutMs: 1600), '4904');
    if (idBytes != null && idBytes.isNotEmpty) {
      final chars = idBytes.where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join().trim();
      if (chars.isNotEmpty) ecuId = chars;
    }

    // Определение KWP (1081) vs UDS (1003)
    bool isUds = false;
    final r81 = await _btService.sendCommand('1081', timeoutMs: 800);
    if (!r81.replaceAll(' ', '').contains('5081')) {
      final r03 = await _btService.sendCommand('1003', timeoutMs: 800);
      if (r03.replaceAll(' ', '').contains('5003')) isUds = true;
    }
    
    final ecuType = _detectEcuType(ecuId);

    state = state.copyWith(
      isConnected: true,
      connectedDevice: macAddress,
      isUds: isUds,
      isUdsM86: isUds,
      ecuId: ecuId,
      ecuType: ecuType,
      statusText: 'На связи · $ecuId · ${isUds ? "UDS" : "KWP"}',
    );
    
    _logNuance(
      'session_start',
      'Сессия открыта',
      'Протокол: ${isUds ? "UDS" : "KWP-CAN"} · Калибровка: $ecuId',
      NuanceSeverity.info,
    );
    return true;
  }
  
  String _detectEcuType(String id) {
    final upper = id.toUpperCase();
    if (upper.contains('I785')) return 'Итэлма М86 (1.8л · UDS)';
    if (upper.contains('765') || upper.contains('M86') || upper.contains('I86')) {
      return 'Итэлма М86 (1.6л · UDS)';
    }
    if (upper.contains('M74')) return 'Итэлма М74';
    if (upper.contains('ME17')) return 'Bosch ME17.9.7';
    return 'ЭБУ не определён';
  }

  void startPolling() {
    if (!state.isConnected || state.isPolling) return;
    state = state.copyWith(isPolling: true);
    _runPollingLoop();
  }

  void stopPolling() {
    state = state.copyWith(isPolling: false);
  }

  void resetTrip() {
    tripCalculator.reset();
    state = state.copyWith();
  }
  
  Future<void> disconnect() async {
    stopPolling();
    await _btService.disconnect();
    state = state.copyWith(isConnected: false, isPolling: false);
  }

  Future<void> pauseForSniffer() async {
    stopPolling();
    while (_isCycleBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  void resumeAfterSniffer() {
    if (state.isConnected && !state.isPolling) startPolling();
  }
  
  Future<String> sendCommandForSniffer(String cmd) async {
    return await _btService.sendCommand(cmd, timeoutMs: 1600);
  }

  Future<void> _runPollingLoop() async {
    while (state.isPolling && _btService.isConnected) {
      if (_isCycleBusy) {
        await Future.delayed(const Duration(milliseconds: 40));
        continue;
      }
      _isCycleBusy = true;

      try {
        final updatedData = Map<String, double>.from(state.liveData);
        final updatedTrace1 = List<double>.from(state.trace1);
        final updatedTrace2 = List<double>.from(state.trace2);
        String lastRawBlock = state.rawLastBlock1;
        
        // P0-2: TesterPresent каждые ~2 сек
        if (_cycle % 5 == 0) {
          await _btService.sendCommand(state.isUds ? '3E00' : '3E', timeoutMs: 500);
        }

        // 1. Напряжение бортсети (ATRV)
        final rVolt = await _btService.sendCommand('ATRV', timeoutMs: 500);
        final mVolt = RegExp(r'(\d+[.,]\d+)').firstMatch(rVolt);
        if (mVolt != null) {
          final v = double.tryParse(mVolt.group(1)!.replaceAll(',', '.'));
          if (v != null && v > 4.5 && v < 18.5) {
            updatedData['volt'] = v;
            final minV = updatedData['min_volt'];
            if (minV == null || v < minV) updatedData['min_volt'] = v;
          }
        }
        if (!state.isPolling) break;

        // 2. Базовые быстрые PID (гарантированно работают на I765BJ56v3)
        final bRpm = ObdParser.extractBytes(await _btService.sendCommand('010C', timeoutMs: 600), '410C');
        if (bRpm != null && bRpm.length >= 2) {
          updatedData['rpm'] = (((bRpm[0] * 256) + bRpm[1]) ~/ 4).toDouble();
        } else if (bRpm == null) {
            _consecutiveErrors++;
        }

        final bStft = ObdParser.extractBytes(await _btService.sendCommand('0106', timeoutMs: 600), '4106');
        if (bStft != null && bStft.isNotEmpty) {
          updatedData['stft'] = (bStft[0] - 128) * 100.0 / 128.0;
        }

        final bLtft = ObdParser.extractBytes(await _btService.sendCommand('0107', timeoutMs: 600), '4107');
        if (bLtft != null && bLtft.isNotEmpty) {
          updatedData['ltft'] = (bLtft[0] - 128) * 100.0 / 128.0;
        }

        if (_cycle % 2 == 0) {
          final bEct = ObdParser.extractBytes(await _btService.sendCommand('0105', timeoutMs: 600), '4105');
          if (bEct != null && bEct.isNotEmpty) {
            final ectRaw = bEct[0] - 40;
            if (ectRaw > -20 && ectRaw < 130) {
              updatedData['ect'] = ectRaw.toDouble();
            }
          }

          final bTps = ObdParser.extractBytes(await _btService.sendCommand('0111', timeoutMs: 600), '4111');
          if (bTps != null && bTps.isNotEmpty) updatedData['tps'] = bTps[0] * 100.0 / 255.0;

          final bO2S1 = ObdParser.extractBytes(await _btService.sendCommand('0114', timeoutMs: 600), '4114');
          if (bO2S1 != null && bO2S1.isNotEmpty) {
            final v1 = bO2S1[0] / 200.0;
            updatedData['udk'] = v1;
            updatedTrace1.add(v1);
            if (updatedTrace1.length > 80) updatedTrace1.removeAt(0);
          }

          final bO2S2 = ObdParser.extractBytes(await _btService.sendCommand('0115', timeoutMs: 600), '4115');
          if (bO2S2 != null && bO2S2.isNotEmpty) {
            final v2 = bO2S2[0] / 200.0;
            updatedData['ddk'] = v2;
            updatedTrace2.add(v2);
            if (updatedTrace2.length > 80) updatedTrace2.removeAt(0);
          }
        } else {
          final bSpd = ObdParser.extractBytes(await _btService.sendCommand('010D', timeoutMs: 600), '410D');
          if (bSpd != null && bSpd.isNotEmpty) updatedData['speed'] = bSpd[0].toDouble();

          final bMap = ObdParser.extractBytes(await _btService.sendCommand('010B', timeoutMs: 600), '410B');
          if (bMap != null && bMap.isNotEmpty) {
            updatedData['map'] = bMap[0].toDouble();
          } else {
            final bLoad = ObdParser.extractBytes(await _btService.sendCommand('0104', timeoutMs: 600), '4104');
            if (bLoad != null && bLoad.isNotEmpty) {
              final loadPct = bLoad[0] * 100.0 / 255.0;
              updatedData['load'] = loadPct;
              updatedData['map'] = (loadPct * 0.95 + 12.0).roundToDouble().clamp(20.0, 105.0);
            }
          }

          // 3. Опрос расширенного блока по JSON-профилю (222001 / 2101)
          if (_ecuProfile != null && _ecuProfile!.blocks.isNotEmpty) {
            final block = _ecuProfile!.blocks.first;
            final cmd = state.isUds ? block.udsCommand : block.kwpCommand;
            final prefix = state.isUds ? '62${block.udsCommand.substring(2)}' : '61${block.kwpCommand.substring(2)}';
            final rawResponse = await _btService.sendCommand(cmd, timeoutMs: 1200);
            lastRawBlock = rawResponse.replaceAll('\\n', ' ');
            final bytes = ObdParser.extractBytes(rawResponse, prefix);
            if (bytes != null && bytes.isNotEmpty) {
              for (final param in block.parameters) {
                final val = param.decode(bytes);
                if (val != null) updatedData[param.id] = val;
              }
            }
          }
        }

        // 4. Реальный расчёт массового расхода воздуха и обновление TripCalculator
        final rpm = updatedData['rpm']?.toInt() ?? 0;
        final mapKpa = updatedData['map'] ?? 35.0;
        final iatK = (updatedData['iat'] ?? 30.0) + 273.15;
        final cyclicAir = (mapKpa * 3.05 * (293.15 / iatK)).clamp(40.0, 520.0);
        final airMassKgH = rpm > 300 ? ((cyclicAir * rpm * 2 * 60) / 1000000.0).clamp(1.0, 180.0) : 0.0;
        updatedData['air_mass_kgh'] = airMassKgH;

        final tpsPct = updatedData['tps'] ?? 0.0;
        final isDfco = rpm > 1500 && tpsPct < 2.0;

        tripCalculator.update(
          rpm: rpm,
          speedKmh: updatedData['speed'] ?? 0.0,
          airMassKgH: airMassKgH,
          tpsPct: tpsPct,
          isDfcoActive: isDfco,
          stftPct: updatedData['stft'] ?? 0.0,
          ltftPct: updatedData['ltft'] ?? 0.0,
        );

        _consecutiveErrors = 0;
        _cycle++;
        state = state.copyWith(
          liveData: updatedData,
          trace1: updatedTrace1,
          trace2: updatedTrace2,
          rawLastBlock1: lastRawBlock,
        );
      } catch (e) {
        _consecutiveErrors++;
        if (_consecutiveErrors >= 3) {
          stopPolling();
          state = state.copyWith(isConnected: false, lastError: 'Связь потеряна');
          _logNuance('bt_drop', 'Обрыв Bluetooth', 'Три цикла опроса завершились ошибкой', NuanceSeverity.critical);
        }
      } finally {
        _isCycleBusy = false;
        // Даем небольшую паузу между циклами
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // Инженерный Сниффер UDS / KWP
  Future<void> runM86HexSniffer() async {
    if (state.isRunningSniffer || !state.isConnected) return;
    final wasPolling = state.isPolling;
    stopPolling();
    while (_isCycleBusy) {
      await Future.delayed(const Duration(milliseconds: 30));
    }

    state = state.copyWith(isRunningSniffer: true, snifferDump: 'Опрос регистров М86...');

    try {
      final sb = StringBuffer();
      sb.writeln('=== ДАМП ОТВЕТОВ ЭБУ М86 (v3.0.0) ===');
      final r1081 = await _btService.sendCommand('1081', timeoutMs: 900);
      final r1003 = await _btService.sendCommand('1003', timeoutMs: 900);
      sb.writeln('1081 (KWP): $r1081 | 1003 (UDS): $r1003');

      final kwpOk = r1081.replaceAll(' ', '').contains('5081');
      final udsOk = r1003.replaceAll(' ', '').contains('5003');
      final isUds = !kwpOk && udsOk ? true : state.isUds;
      sb.writeln('=> Протокол: ${isUds ? "UDS" : "KWP-CAN"}');

      final cmds = <String>[
        '0904', '0100', '010B', '0104', '012E',
        if (isUds) ...[
          '222001', '222002', '222003',
          '220401', '220402', '220403',
          '22F187', '22F188', '22F190',
        ] else ...[
          '2101', '2102', '2103',
        ]
      ];

      for (final cmd in cmds) {
        await _btService.sendCommand(isUds ? '3E00' : '3E', timeoutMs: 400, postDelayMs: 30);
        final r = await _btService.sendCommand(cmd, timeoutMs: 1600, postDelayMs: 120);
        sb.writeln('$cmd => ${r.replaceAll('\\n', ' | ')}');
      }

      final dumpStr = sb.toString().trim();
      await Clipboard.setData(ClipboardData(text: dumpStr));
      state = state.copyWith(
        isUds: isUds,
        snifferDump: '$dumpStr\\n\\n✅ Дамп скопирован в буфер обмена!',
      );
    } finally {
      state = state.copyWith(isRunningSniffer: false);
      if (wasPolling) startPolling();
    }
  }

  // Генератор ИИ-Снапшота («Умный промпт»)
  Future<String> copyAiSnapshotPrompt() async {
    final d = state.liveData;
    final sb = StringBuffer();
    sb.writeln('Ты — ведущий инженер-диагност ЭСУД АвтоВАЗ (ТИ 3100.25100.12056).');
    sb.writeln('Проанализируй диагностический снапшот автомобиля Lada Vesta (VestaScan Pro v3.0):');
    sb.writeln('• Калибровка ЭБУ: ${state.ecuId} | Протокол: ${state.isUds ? "UDS (1003)" : "KWP (1081)"}');
    sb.writeln('• Обороты: ${d['rpm']?.toInt() ?? "---"} об/мин | Темп. ОЖ: ${d['ect']?.toInt() ?? "---"} °C');
    sb.writeln('• ДАД/Нагрузка: ${d['map']?.toInt() ?? "---"} кПа (Нагрузка 0104: ${d['load']?.toStringAsFixed(1) ?? "---"}%) | Дроссель: ${d['tps']?.toStringAsFixed(1) ?? "---"}%');
    sb.writeln('• Бортсеть: ${d['volt']?.toStringAsFixed(2) ?? "---"} В (Мин. за сессию: ${d['min_volt']?.toStringAsFixed(2) ?? "---"} В)');
    sb.writeln('• Топливные коррекции: STFT = ${d['stft']?.toStringAsFixed(1) ?? "---"}% | LTFT = ${d['ltft']?.toStringAsFixed(1) ?? "---"}%');
    sb.writeln('• Датчики кислорода: УДК (ДК1) = ${d['udk']?.toStringAsFixed(2) ?? "---"} В | ДДК (ДК2) = ${d['ddk']?.toStringAsFixed(2) ?? "---"} В');
    sb.writeln('• Расчёт БК: Воздух ~${d['air_mass_kgh']?.toStringAsFixed(1) ?? "---"} кг/ч | Часовой расход ${tripCalculator.instantFuelLpH.toStringAsFixed(2)} л/ч | Пробег ${tripCalculator.totalDistanceKm.toStringAsFixed(2)} км | Средний ${tripCalculator.averageConsumptionL100Km.toStringAsFixed(1)} л/100км');
    sb.writeln('• Последний ответ расширенного блока: ${state.rawLastBlock1}');
    sb.writeln('\\nЗадача: 1) Оцени параметры работы ДВС, впуска и топливной системы. 2) Укажи на отклонения от заводских норм. 3) Какие проверки выполнить далее?');

    final text = sb.toString();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }
  
  // ===== ДЛЯ ЭКРАНА ОШИБОК (DTC) =====
  Future<List<String>> readDtcs() async {
    final codes = <String>{};
    for (final mode in ['03', '07']) {
      final resp = await _btService.sendCommand(mode, timeoutMs: 2000);
      final b = ObdParser.extractBytes(resp, mode == '03' ? '43' : '47');
      if (b == null || b.length < 3) continue;

      final cnt = b[0];
      final usable = (cnt > 0 && cnt <= 40 && b.length >= 1 + cnt * 2)
          ? cnt
          : (b.length - 1) ~/ 2;

      for (int i = 0; i < usable; i++) {
        final b1 = b[1 + i * 2];
        final b2 = b[2 + i * 2];
        if (b1 == 0 && b2 == 0) continue;
        const types = ['P', 'C', 'B', 'U'];
        final t = types[(b1 >> 6) & 0x03];
        final code = '$t${((b1 >> 4) & 0x03)}${(b1 & 0x0F).toRadixString(16).toUpperCase()}${((b2 >> 4) & 0x0F).toRadixString(16).toUpperCase()}${(b2 & 0x0F).toRadixString(16).toUpperCase()}';
        codes.add(code);
      }
    }
    state = state.copyWith(dtcList: codes.toList());
    return codes.toList();
  }

  Future<void> clearDtcs() async {
    await _btService.sendCommand('04', timeoutMs: 2000);
    state = state.copyWith(dtcList: []);
    _logNuance('dtc_clear', 'Сброс DTC', 'Mode 04 выполнен', NuanceSeverity.info);
  }

  Future<Map<String, double?>> getFreezeFrame(String code) async {
    int? rpm, ect, map, speed;
    double? stft, ltft, volt;

    final rRpm = ObdParser.extractBytes(await _btService.sendCommand('020C00', timeoutMs: 900), '420C');
    if (rRpm != null && rRpm.length >= 3) rpm = ((rRpm[1] * 256) + rRpm[2]) ~/ 4;

    final rEct = ObdParser.extractBytes(await _btService.sendCommand('020500', timeoutMs: 900), '4205');
    if (rEct != null && rEct.length >= 2) ect = rEct[1] - 40;

    final rMap = ObdParser.extractBytes(await _btService.sendCommand('020B00', timeoutMs: 900), '420B');
    if (rMap != null && rMap.length >= 2) map = rMap[1];

    final rStft = ObdParser.extractBytes(await _btService.sendCommand('020600', timeoutMs: 900), '4206');
    if (rStft != null && rStft.length >= 2) stft = (rStft[1] - 128) * 100.0 / 128.0;

    final rLtft = ObdParser.extractBytes(await _btService.sendCommand('020700', timeoutMs: 900), '4207');
    if (rLtft != null && rLtft.length >= 2) ltft = (rLtft[1] - 128) * 100.0 / 128.0;

    final rSpeed = ObdParser.extractBytes(await _btService.sendCommand('020D00', timeoutMs: 900), '420D');
    if (rSpeed != null && rSpeed.length >= 2) speed = rSpeed[1];

    final rVolt = ObdParser.extractBytes(await _btService.sendCommand('024200', timeoutMs: 900), '4242');
    if (rVolt != null && rVolt.length >= 3) volt = ((rVolt[1] * 256) + rVolt[2]) / 1000.0;

    return {
      'rpm': rpm?.toDouble(),
      'ect': ect?.toDouble(),
      'map': map?.toDouble(),
      'speed': speed?.toDouble(),
      'stft': stft,
      'ltft': ltft,
      'volt': volt,
    };
  }

  // ===== ДЛЯ ЖУРНАЛА =====
  void _logNuance(String id, String title, String desc, NuanceSeverity sev, {int cooldownSec = 25}) {
    final now = DateTime.now();
    if (_lastNuanceTimes.containsKey(id) &&
        now.difference(_lastNuanceTimes[id]!).inSeconds < cooldownSec) {
      return;
    }
    _lastNuanceTimes[id] = now;

    final currentSnapshot = <String, String>{
      if (state.liveData['rpm'] != null) 'RPM': '${state.liveData['rpm']}',
      if (state.liveData['ect'] != null) 'ОЖ': '${state.liveData['ect']}°C',
      if (state.liveData['volt'] != null) 'Сеть': '${state.liveData['volt']}В',
    };

    final list = List<NuanceEvent>.from(state.nuances);
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final ex = list.removeAt(idx);
      ex.hzCount += 1;
      ex.timestamp = now;
      ex.severity = sev;
      ex.title = title;
      ex.description = desc;
      ex.snapshot = currentSnapshot;
      list.insert(0, ex);
    } else {
      list.insert(0, NuanceEvent(
        id: id,
        timestamp: now,
        severity: sev,
        title: title,
        description: desc,
        snapshot: currentSnapshot,
      ));
    }
    if (list.length > 500) list.removeRange(500, list.length);
    state = state.copyWith(nuances: list);
  }

  void logNuancePublic(String id, String title, String desc, NuanceSeverity sev) {
    _logNuance(id, title, desc, sev);
  }

  void clearJournal() {
    state = state.copyWith(nuances: []);
  }

  Future<String> exportJournalToCsv() async {
    final sb = StringBuffer();
    sb.writeln('=== VestaScan Pro · Экспорт ===');
    sb.writeln('Устройство: ${state.connectedDevice}');
    sb.writeln('ЭБУ: ${state.ecuType} · Калибровка: ${state.ecuId}');
    sb.writeln('Протокол: ${state.isUds ? "UDS" : "KWP-CAN"}');
    sb.writeln('');

    sb.writeln('--- ЖУРНАЛ ---');
    for (final e in state.nuances) {
      sb.writeln('[${e.timeStr}] [HZ:${e.hzCount}] [${e.severity.name.toUpperCase()}] ${e.title}: ${e.description}');
    }

    sb.writeln('');
    sb.writeln('--- ПАРАМЕТРЫ ---');
    state.liveData.forEach((k, v) => sb.writeln('$k: $v'));

    final csvText = sb.toString();
    await Clipboard.setData(ClipboardData(text: csvText));
    return '✅ Скопировано в буфер обмена';
  }
}
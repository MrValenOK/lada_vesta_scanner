import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/bluetooth_service.dart';
import '../services/obd_parser.dart';
import '../services/trip_calculator.dart';
import '../data/models/ecu_profile.dart';
import '../data/models/nuance_event.dart';

// ===== СОСТОЯНИЕ =====
class ObdState {
  final bool isConnected;
  final bool isPolling;
  final String connectedDevice;
  final String ecuId;
  final String ecuType;
  final bool isUdsM86;
  final bool isUds;
  final String statusText;
  final Map<String, double> liveData;
  final List<double> trace1; // УДК
  final List<double> trace2; // ДДК
  final bool isRunningSniffer;
  final String snifferDump;
  final String rawLastBlock1;
  final List<NuanceEvent> nuances;
  final List<String> dtcList;
  final String? lastError;
  final Map<String, double> trimMedians;

  ObdState({
    this.isConnected = false,
    this.isPolling = false,
    this.connectedDevice = '---',
    this.ecuId = '---',
    this.ecuType = 'Итэлма М86',
    this.isUdsM86 = true,
    this.isUds = true,
    this.statusText = 'Выберите адаптер и нажмите Старт',
    this.liveData = const {},
    this.trace1 = const [],
    this.trace2 = const [],
    this.isRunningSniffer = false,
    this.snifferDump = 'Нажмите «Снять HEX-дамп», чтобы опросить регистры (0904, 220001...).',
    this.rawLastBlock1 = '---',
    this.nuances = const [],
    this.dtcList = const [],
    this.lastError,
    this.trimMedians = const {},
  });

  ObdState copyWith({
    bool? isConnected,
    bool? isPolling,
    String? connectedDevice,
    String? ecuId,
    String? ecuType,
    bool? isUdsM86,
    bool? isUds,
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
    Map<String, double>? trimMedians,
  }) {
    return ObdState(
      isConnected: isConnected ?? this.isConnected,
      isPolling: isPolling ?? this.isPolling,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      ecuId: ecuId ?? this.ecuId,
      ecuType: ecuType ?? this.ecuType,
      isUdsM86: isUdsM86 ?? this.isUdsM86,
      isUds: isUds ?? this.isUds,
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
      trimMedians: trimMedians ?? this.trimMedians,
    );
  }
}

// ===== ПРОВАЙДЕР =====
final obdProvider = StateNotifierProvider<ObdNotifier, ObdState>((ref) {
  return ObdNotifier();
});

// ===== ЛОГИКА =====
class ObdNotifier extends StateNotifier<ObdState> {
  final BluetoothService _btService = BluetoothService();
  final TripCalculator tripCalculator = TripCalculator();

  Timer? _pollTimer;
  bool _isCycleBusy = false;
  int _cycle = 0;
  int _consecutiveErrors = 0;
  final Map<String, DateTime> _lastNuanceTimes = {};
  
  final Map<String, TrimBin> _bins = {
    'idle': TrimBin('ХХ'),
    'low': TrimBin('Малые'),
    'part': TrimBin('Част.'),
    'high': TrimBin('Выс.'),
  };

  ObdNotifier() : super(ObdState()) {
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logJson = prefs.getString('nuance_log');
      if (logJson != null) {
        final list = jsonDecode(logJson) as List;
        state = state.copyWith(nuances: list.map((e) => NuanceEvent.fromJson(e)).toList());
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nuance_log', jsonEncode(state.nuances.take(100).map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void clearJournal() {
    state = state.copyWith(nuances: []);
    _saveState();
  }

  Future<List<Map<String, String>>> getBluetoothDevices() async {
    final list = await _btService.getPairedDevices();
    return list.map((d) => {'name': d.name ?? 'Unknown', 'address': d.address}).toList();
  }

  // ===== ПОДКЛЮЧЕНИЕ =====
  Future<bool> connect(String macAddress) async {
    state = state.copyWith(statusText: 'Подключение к $macAddress...');
    final success = await _btService.connect(macAddress);
    if (!success) {
      state = state.copyWith(isConnected: false, statusText: 'Ошибка подключения к ELM327');
      return false;
    }

    // Инициализация ELM327
    for (final cmd in [
      'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6',
      'ATAL', 'ATCAF1', 'ATSH7E0', 'ATCRA7E8'
    ]) {
      await _btService.sendCommand(cmd, timeoutMs: cmd == 'ATZ' ? 1800 : 500);
    }

    // Открываем расширенную сессию UDS (для M86 I765BJ56v3)
    await _btService.sendCommand('1003', timeoutMs: 800);

    // Паспорт ЭБУ (0904) - Резервно пытаемся прочитать калибровку
    String ecuId = state.ecuId;
    final idBytes = ObdParser.extractBytes(await _btService.sendCommand('0904', timeoutMs: 1600), '4904');
    if (idBytes != null && idBytes.isNotEmpty) {
      final chars = idBytes.where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join().trim();
      if (chars.isNotEmpty) ecuId = chars;
    }

    state = state.copyWith(
      isConnected: true,
      connectedDevice: macAddress,
      isUds: true,
      isUdsM86: true,
      ecuId: ecuId,
      ecuType: 'Итэлма М86',
      statusText: 'На связи · $ecuId · UDS',
    );
    
    _logNuance(
      'session_start',
      'Сессия открыта',
      'Протокол: UDS (1003) · Калибровка: $ecuId',
      NuanceSeverity.info,
    );
    return true;
  }

  void startPolling() {
    if (!state.isConnected || state.isPolling) return;
    state = state.copyWith(isPolling: true, lastError: null);
    _consecutiveErrors = 0;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) async {
      await _pollCycle();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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

  // ===== ГЛАВНЫЙ ЦИКЛ ОПРОСА (Адаптирован под M86 I765BJ56v3) =====
  Future<void> _pollCycle() async {
    if (_isCycleBusy || !state.isConnected) return;
    _isCycleBusy = true;

    try {
      final updatedData = Map<String, double>.from(state.liveData);
      final trace1 = List<double>.from(state.trace1);
      final trace2 = List<double>.from(state.trace2);
      String lastRawBlock = state.rawLastBlock1;
      
      // TesterPresent каждые ~2 сек (каждый 5й цикл) для удержания сессии 1003
      if (_cycle % 5 == 0) {
        await _btService.sendCommand('3E00', timeoutMs: 500);
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
      if (!state.isPolling) return;

      // 2. Обороты (010C) - 41 0C A B => ((A*256)+B)/4
      final bRpm = ObdParser.extractBytes(await _btService.sendCommand('010C', timeoutMs: 600), '410C');
      if (bRpm != null && bRpm.length >= 2) {
        updatedData['rpm'] = (((bRpm[0] * 256) + bRpm[1]) ~/ 4).toDouble();
      } else {
        _consecutiveErrors++;
      }

      // 3. Коррекции (0106, 0107) - 41 0X A => (A-128)*100/128
      final bStft = ObdParser.extractBytes(await _btService.sendCommand('0106', timeoutMs: 600), '4106');
      if (bStft != null && bStft.isNotEmpty) {
        updatedData['stft'] = (bStft[0] - 128) * 100.0 / 128.0;
      }
      final bLtft = ObdParser.extractBytes(await _btService.sendCommand('0107', timeoutMs: 600), '4107');
      if (bLtft != null && bLtft.isNotEmpty) {
        updatedData['ltft'] = (bLtft[0] - 128) * 100.0 / 128.0;
      }

      // Разделяем тяжелые запросы на четные/нечетные циклы для скорости
      if (_cycle % 2 == 0) {
        // Температура ОЖ (0105) - 41 05 A => A-40
        final bEct = ObdParser.extractBytes(await _btService.sendCommand('0105', timeoutMs: 600), '4105');
        if (bEct != null && bEct.isNotEmpty) {
          final ectRaw = bEct[0] - 40;
          if (ectRaw > -20 && ectRaw < 130) {
            updatedData['ect'] = ectRaw.toDouble();
          }
        }

        // Дроссель (0111) - 41 11 A => A*100/255
        final bTps = ObdParser.extractBytes(await _btService.sendCommand('0111', timeoutMs: 600), '4111');
        if (bTps != null && bTps.isNotEmpty) updatedData['tps'] = bTps[0] * 100.0 / 255.0;

        // ДК1 (0114) и ДК2 (0115) - 41 14 A B => A/200
        final bO2S1 = ObdParser.extractBytes(await _btService.sendCommand('0114', timeoutMs: 600), '4114');
        if (bO2S1 != null && bO2S1.isNotEmpty) {
          final v1 = bO2S1[0] / 200.0;
          updatedData['udk'] = v1;
          trace1.add(v1);
          if (trace1.length > 80) trace1.removeAt(0);
        }
        final bO2S2 = ObdParser.extractBytes(await _btService.sendCommand('0115', timeoutMs: 600), '4115');
        if (bO2S2 != null && bO2S2.isNotEmpty) {
          final v2 = bO2S2[0] / 200.0;
          updatedData['ddk'] = v2;
          trace2.add(v2);
          if (trace2.length > 80) trace2.removeAt(0);
        }
      } else {
        // Скорость (010D)
        final bSpd = ObdParser.extractBytes(await _btService.sendCommand('010D', timeoutMs: 600), '410D');
        if (bSpd != null && bSpd.isNotEmpty) updatedData['speed'] = bSpd[0].toDouble();

        // Нагрузка на двигатель (0104) для расчета MAP, т.к. 010B не работает
        final bLoad = ObdParser.extractBytes(await _btService.sendCommand('0104', timeoutMs: 600), '4104');
        if (bLoad != null && bLoad.isNotEmpty) {
          final loadPct = bLoad[0] * 100.0 / 255.0;
          updatedData['load'] = loadPct;
          updatedData['map'] = (loadPct * 0.95 + 12.0).roundToDouble().clamp(20.0, 105.0);
        }

        // Заводской блок телеметрии UDS (220001) - 80 байт
        final rawResponse = await _btService.sendCommand('220001', timeoutMs: 1400);
        lastRawBlock = rawResponse.replaceAll('\n', ' ');
        final bytes = ObdParser.extractBytes(rawResponse, '620001');

        if (bytes != null && bytes.length > 16) {
          // Температура с валидацией
          final ectRaw = bytes[3] - 40;
          if (ectRaw > -20 && ectRaw < 130) {
            updatedData['ect'] = ectRaw.toDouble();
          }
          updatedData['tps'] = (bytes[11] * 100 / 255);
          updatedData['stft'] = ((bytes[15] - 128) * 100 / 128);
          updatedData['ltft'] = ((bytes[16] - 128) * 100 / 128);

          if (bytes.length > 8) {
            final mapRaw = bytes[8];
            if (mapRaw >= 15 && mapRaw <= 115) updatedData['map'] = mapRaw.toDouble();
          }
        }
      }

      // 4. Расчёт массового расхода воздуха (Speed-Density)
      final rpmVal = updatedData['rpm']?.toInt() ?? 0;
      final mapKpa = updatedData['map'] ?? 35.0;
      final iatK = (updatedData['iat'] ?? 30.0) + 273.15;
      final cyclicAir = (mapKpa * 3.05 * (293.15 / iatK)).clamp(40.0, 520.0);
      final airMassKgH = rpmVal > 300 ? ((cyclicAir * rpmVal * 2 * 60) / 1000000.0).clamp(1.0, 180.0) : 0.0;
      updatedData['air_mass_kgh'] = airMassKgH;

      // 5. Обновление БК и Матрицы
      final tpsPct = updatedData['tps'] ?? 0.0;
      final stft = updatedData['stft'];
      final ltft = updatedData['ltft'];

      tripCalculator.update(
        rpm: rpmVal,
        speedKmh: updatedData['speed'] ?? 0.0,
        airMassKgH: airMassKgH,
        tpsPct: tpsPct,
        isDfcoActive: rpmVal > 1500 && tpsPct < 2.0,
        stftPct: stft ?? 0.0,
        ltftPct: ltft ?? 0.0,
      );

      if (stft != null && ltft != null && rpmVal > 0 && tpsPct < 70) {
        if (rpmVal >= 740 && rpmVal <= 960 && tpsPct <= 4.5) { _bins['idle']!.addSample(stft, ltft); }
        else if (rpmVal > 1600 && tpsPct <= 12.0) { _bins['low']!.addSample(stft, ltft); }
        else if (rpmVal >= 1300 && rpmVal <= 3400 && tpsPct > 4.5 && tpsPct <= 35.0) { _bins['part']!.addSample(stft, ltft); }
        else if (tpsPct > 35.0) { _bins['high']!.addSample(stft, ltft); }
        
        final medians = {
          'idle': _bins['idle']!.median,
          'low': _bins['low']!.median,
          'part': _bins['part']!.median,
          'high': _bins['high']!.median,
        };
        state = state.copyWith(trimMedians: medians);
      }

      _consecutiveErrors = 0;
      _cycle++;
      state = state.copyWith(
        liveData: updatedData,
        trace1: trace1,
        trace2: trace2,
        rawLastBlock1: lastRawBlock,
      );
    } catch (e) {
      _consecutiveErrors++;
      if (_consecutiveErrors >= 4) {
        stopPolling();
        state = state.copyWith(isConnected: false, lastError: 'Связь потеряна');
        _logNuance('bt_drop', 'Обрыв Bluetooth', '4 цикла опроса завершились ошибкой', NuanceSeverity.critical);
      }
    } finally {
      _isCycleBusy = false;
    }
  }

  // ===== СНИФФЕР =====
  Future<void> runM86HexSniffer() async {
    if (state.isRunningSniffer || !state.isConnected) return;
    final wasPolling = state.isPolling;
    await pauseForSniffer();

    state = state.copyWith(isRunningSniffer: true, snifferDump: 'Опрос регистров М86...');

    try {
      final sb = StringBuffer();
      sb.writeln('=== ДАМП ОТВЕТОВ ЭБУ М86 (I765BJ56v3) ===');
      
      final cmds = <String>[
        '0904', '0100', '0104', '0105', '0106', '0107', '010C', '010D', '0111', '0114', '0115', // Mode 01
        '0600', '0601', '0621', // Mode 06
        '220090', '220091', '220097', '22009A', // UDS Инфо
        '220001', '220002', '220003', '220005', // UDS Телеметрия
      ];

      for (final cmd in cmds) {
        if (cmd.startsWith('22')) {
          await _btService.sendCommand('3E00', timeoutMs: 400, postDelayMs: 30);
        }
        final r = await _btService.sendCommand(cmd, timeoutMs: 1600, postDelayMs: 100);
        sb.writeln('$cmd => ${r.replaceAll('\n', ' | ')}');
      }

      final dumpStr = sb.toString().trim();
      await Clipboard.setData(ClipboardData(text: dumpStr));
      state = state.copyWith(snifferDump: '$dumpStr\n\n✅ Дамп скопирован в буфер обмена!');
    } finally {
      state = state.copyWith(isRunningSniffer: false);
      if (wasPolling) startPolling();
    }
  }

  // ===== ИИ-СНАПШОТ =====
  Future<String> copyAiSnapshotPrompt() async {
    final d = state.liveData;
    final sb = StringBuffer();
    sb.writeln('Ты — ведущий инженер-диагност ЭСУД АвтоВАЗ.');
    sb.writeln('Проанализируй диагностический снапшот Lada Vesta:');
    sb.writeln('• Калибровка ЭБУ: ${state.ecuId} | Протокол: UDS');
    sb.writeln('• Обороты: ${d['rpm']?.toInt() ?? "---"} об/мин | Темп. ОЖ: ${d['ect']?.toInt() ?? "---"} °C');
    sb.writeln('• Нагрузка (0104): ${d['load']?.toStringAsFixed(1) ?? "---"}% | Расчетный ДАД: ${d['map']?.toInt() ?? "---"} кПа | Дроссель: ${d['tps']?.toStringAsFixed(1) ?? "---"}%');
    sb.writeln('• Бортсеть: ${d['volt']?.toStringAsFixed(2) ?? "---"} В (Мин. за сессию: ${d['min_volt']?.toStringAsFixed(2) ?? "---"} В)');
    sb.writeln('• Коррекции: STFT = ${d['stft']?.toStringAsFixed(1) ?? "---"}% | LTFT = ${d['ltft']?.toStringAsFixed(1) ?? "---"}%');
    sb.writeln('• Лямбда: ДК1 = ${d['udk']?.toStringAsFixed(2) ?? "---"} В | ДК2 = ${d['ddk']?.toStringAsFixed(2) ?? "---"} В');
    sb.writeln('• Расчёт БК: Воздух ~${d['air_mass_kgh']?.toStringAsFixed(1) ?? "---"} кг/ч | Часовой расход ${tripCalculator.instantFuelLpH.toStringAsFixed(2)} л/ч');
    sb.writeln('• Последний ответ 220001: ${state.rawLastBlock1}');
    sb.writeln('\nЗадача: 1) Оцени параметры работы ДВС. 2) Укажи на отклонения от заводских норм.');

    final text = sb.toString();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }
  
  // ===== ОШИБКИ (DTC) =====
  Future<List<String>> readDtcs() async {
    final codes = <String>{};
    for (final mode in ['03', '07']) {
      final resp = await _btService.sendCommand(mode, timeoutMs: 2000);
      final b = ObdParser.extractBytes(resp, mode == '03' ? '43' : '47');
      if (b == null || b.length < 3) continue;

      final cnt = b[0];
      final usable = (cnt > 0 && cnt <= 40 && b.length >= 1 + cnt * 2) ? cnt : (b.length - 1) ~/ 2;

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

  Future<Map<String, String>> getFreezeFrame(String code) async {
    final result = <String, String>{};
    if (!state.isConnected) return result;

    int? rpm, ect, speed;
    double? stft, ltft, volt;

    final rRpm = ObdParser.extractBytes(await _btService.sendCommand('020C00', timeoutMs: 900), '420C');
    if (rRpm != null && rRpm.length >= 3) {
      rpm = ((rRpm[1] * 256) + rRpm[2]) ~/ 4;
      result['Обороты'] = '$rpm об/мин';
    }
    final rEct = ObdParser.extractBytes(await _btService.sendCommand('020500', timeoutMs: 900), '4205');
    if (rEct != null && rEct.length >= 2) {
      ect = rEct[1] - 40;
      result['Темп. ОЖ'] = '$ect °C';
    }
    final rStft = ObdParser.extractBytes(await _btService.sendCommand('020600', timeoutMs: 900), '4206');
    if (rStft != null && rStft.length >= 2) {
      stft = (rStft[1] - 128) * 100.0 / 128.0;
      result['STFT'] = '${stft.toStringAsFixed(1)} %';
    }
    final rLtft = ObdParser.extractBytes(await _btService.sendCommand('020700', timeoutMs: 900), '4207');
    if (rLtft != null && rLtft.length >= 2) {
      ltft = (rLtft[1] - 128) * 100.0 / 128.0;
      result['LTFT'] = '${ltft.toStringAsFixed(1)} %';
    }
    final rSpeed = ObdParser.extractBytes(await _btService.sendCommand('020D00', timeoutMs: 900), '420D');
    if (rSpeed != null && rSpeed.length >= 2) {
      speed = rSpeed[1];
      result['Скорость'] = '$speed км/ч';
    }
    final rVolt = ObdParser.extractBytes(await _btService.sendCommand('024200', timeoutMs: 900), '4242');
    if (rVolt != null && rVolt.length >= 3) {
      volt = ((rVolt[1] * 256) + rVolt[2]) / 1000.0;
      result['Бортсеть'] = '${volt.toStringAsFixed(2)} В';
    }
    return result;
  }

  // ===== ДЛЯ ЖУРНАЛА И ЭКСПОРТА =====
  void _logNuance(String id, String title, String desc, NuanceSeverity sev, {int cooldownSec = 25}) {
    final now = DateTime.now();
    if (_lastNuanceTimes.containsKey(id) && now.difference(_lastNuanceTimes[id]!).inSeconds < cooldownSec) {
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
      list.insert(0, ex);
    } else {
      list.insert(0, NuanceEvent(id: id, timestamp: now, severity: sev, title: title, description: desc, snapshot: currentSnapshot));
    }
    state = state.copyWith(nuances: list);
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
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../services/bluetooth_service.dart';
import '../services/obd_parser.dart';
import '../services/trip_calculator.dart';
import '../data/models/ecu_profile.dart';
import '../data/models/nuance_event.dart';

class ObdState {
  final bool isConnected;
  final bool isPolling;
  final Map<String, double> liveData;
  final List<double> trace1;   // УДК
  final List<double> trace2;   // ДДК
  final List<NuanceEvent> nuances;
  final Map<String, double> trimMedians;

  ObdState({
    this.isConnected = false,
    this.isPolling = false,
    this.liveData = const {},
    this.trace1 = const [],
    this.trace2 = const [],
    this.nuances = const [],
    this.trimMedians = const {},
  });

  ObdState copyWith({
    bool? isConnected,
    bool? isPolling,
    Map<String, double>? liveData,
    List<double>? trace1,
    List<double>? trace2,
    List<NuanceEvent>? nuances,
    Map<String, double>? trimMedians,
  }) {
    return ObdState(
      isConnected: isConnected ?? this.isConnected,
      isPolling: isPolling ?? this.isPolling,
      liveData: liveData ?? this.liveData,
      trace1: trace1 ?? this.trace1,
      trace2: trace2 ?? this.trace2,
      nuances: nuances ?? this.nuances,
      trimMedians: trimMedians ?? this.trimMedians,
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
  bool _isUdsM86 = false;
  final TripCalculator tripCalculator = TripCalculator();
  EcuProfile? _ecuProfile;

  final Map<String, TrimBin> _bins = {
    'idle': TrimBin('ХХ'),
    'low': TrimBin('Малые'),
    'part': TrimBin('Част.'),
    'high': TrimBin('Выс.'),
  };

  ObdNotifier(this._btService) : super(ObdState()) {
    _loadEcuProfile();
    _loadPersistedState();
  }

  Future<void> _loadEcuProfile() async {
    try {
      final jsonString = await rootBundle.loadString('lib/data/json_profiles/m86_uds.json');
      final jsonMap = jsonDecode(jsonString);
      _ecuProfile = EcuProfile.fromJson(jsonMap);
    } catch (e) {
      // Ошибка загрузки
    }
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final logJson = prefs.getString('nuance_log');
    if (logJson != null) {
      final list = jsonDecode(logJson) as List;
      state = state.copyWith(nuances: list.map((e) => NuanceEvent.fromJson(e)).toList());
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nuance_log', jsonEncode(state.nuances.take(100).map((e) => e.toJson()).toList()));
  }

  void _logNuance(String id, String title, String desc, NuanceSeverity sev) {
    final existingIdx = state.nuances.indexWhere((e) => e.id == id);
    final updated = List<NuanceEvent>.from(state.nuances);

    if (existingIdx != -1) {
      final ex = updated.removeAt(existingIdx);
      ex.hzCount += 1;
      ex.timestamp = DateTime.now();
      updated.insert(0, ex);
    } else {
      updated.insert(0, NuanceEvent(
        id: id, timestamp: DateTime.now(), severity: sev,
        title: title, description: desc,
        snapshot: {
          if (state.liveData['rpm'] != null) 'RPM': '${state.liveData['rpm']!.toInt()}',
          if (state.liveData['ect'] != null) 'ОЖ': '${state.liveData['ect']!.toInt()}°C',
        },
      ));
    }
    state = state.copyWith(nuances: updated);
    _saveState();
  }

  void clearJournal() {
    state = state.copyWith(nuances: []);
    _saveState();
  }

  void resetTrip() {
    tripCalculator.reset();
    state = state.copyWith();
  }

  Future<bool> connect(String macAddress) async {
    final success = await _btService.connect(macAddress);
    if (!success) return false;

    await _btService.sendCommand('ATZ', timeoutMs: 2000);
    await _btService.sendCommand('ATE0');
    await _btService.sendCommand('ATL0');
    await _btService.sendCommand('ATS0');
    await _btService.sendCommand('ATH0');
    await _btService.sendCommand('ATSP6');
    await _btService.sendCommand('ATAL');
    await _btService.sendCommand('ATSH7E0');
    await _btService.sendCommand('ATCRA7E8');

    final r81 = await _btService.sendCommand('1081', timeoutMs: 800);
    if (!r81.replaceAll(' ', '').contains('5081')) {
      final r03 = await _btService.sendCommand('1003', timeoutMs: 800);
      if (r03.replaceAll(' ', '').contains('5003')) _isUdsM86 = true;
    } else {
      _isUdsM86 = false;
    }

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

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = state.copyWith(isPolling: false);
  }

  Future<void> _pollCycle() async {
    if (!state.isConnected || _ecuProfile == null) return;

    try {
      final updatedData = Map<String, double>.from(state.liveData);

      // 1. Читаем ПЕРВЫЙ блок (Обороты, Температура, Дроссель)
      final block1 = _ecuProfile!.blocks[0];
      final cmd1 = _isUdsM86 ? block1.udsCommand : block1.kwpCommand;
      final res1 = await _btService.sendCommand(cmd1, timeoutMs: 1000);
      final prefix1 = _isUdsM86 ? '622001' : '6101';
      final bytes1 = ObdParser.extractBytes(res1, prefix1);

      if (bytes1 != null && bytes1.isNotEmpty) {
        for (final param in block1.parameters) {
          final val = param.decode(bytes1);
          if (val != null) updatedData[param.id] = val;
        }
      }

      // 2. Читаем ВТОРОЙ блок (Пропуски, Напряжение УДК)
      if (_ecuProfile!.blocks.length > 1) {
        final block2 = _ecuProfile!.blocks[1];
        final cmd2 = _isUdsM86 ? block2.udsCommand : block2.kwpCommand;
        final res2 = await _btService.sendCommand(cmd2, timeoutMs: 1000);
        final prefix2 = _isUdsM86 ? '622002' : '6102';
        final bytes2 = ObdParser.extractBytes(res2, prefix2);

        if (bytes2 != null && bytes2.isNotEmpty) {
          for (final param in block2.parameters) {
            final val = param.decode(bytes2);
            if (val != null) updatedData[param.id] = val;
          }
        }
      }

      // 2.5. Читаем УДК и ДДК (стандартные OBD-II PID)
      final resO2 = await _btService.sendCommand('0114', timeoutMs: 800);
      final bytesO2 = ObdParser.extractBytes(resO2, '4114');
      if (bytesO2 != null && bytesO2.isNotEmpty) {
        updatedData['udk_volt'] = bytesO2[0] / 200.0;
      }

      final resO2b = await _btService.sendCommand('0115', timeoutMs: 800);
      final bytesO2b = ObdParser.extractBytes(resO2b, '4115');
      if (bytesO2b != null && bytesO2b.isNotEmpty) {
        updatedData['ddk_volt'] = bytesO2b[0] / 200.0;
      }

      // 3. Читаем СКОРОСТЬ для БК (стандартный OBD2 PID 010D)
      final resSpeed = await _btService.sendCommand('010D', timeoutMs: 800);
      final bytesSpeed = ObdParser.extractBytes(resSpeed, '410D');
      if (bytesSpeed != null && bytesSpeed.isNotEmpty) {
        updatedData['speed'] = bytesSpeed[0].toDouble(); // км/ч
      }

      // 4. Кормим данные в БК
      tripCalculator.update(
        rpm: updatedData['rpm']?.toInt() ?? 0,
        speedKmh: updatedData['speed'] ?? 0.0,
        airMassKgH: (updatedData['map'] ?? 35.0) * (updatedData['rpm'] ?? 840.0) * 0.00025,
        tpsPct: updatedData['tps'] ?? 0.0,
        isDfcoActive: false,
        stftPct: updatedData['stft'] ?? 0.0,
        ltftPct: updatedData['ltft'] ?? 0.0,
      );

      // РАСЧЕТ МАТРИЦЫ КОРРЕКЦИЙ
      final rpm = updatedData['rpm'] ?? 0;
      final tps = updatedData['tps'] ?? 0;
      final stft = updatedData['stft'];
      final ltft = updatedData['ltft'];

      if (stft != null && ltft != null && rpm > 0 && tps < 70) {
        if (rpm >= 740 && rpm <= 960 && tps <= 4.5) _bins['idle']!.addSample(stft, ltft);
        else if (rpm > 1600 && tps <= 12.0) _bins['low']!.addSample(stft, ltft);
        else if (rpm >= 1300 && rpm <= 3400 && tps > 4.5 && tps <= 35.0) _bins['part']!.addSample(stft, ltft);
        else if (tps > 35.0) _bins['high']!.addSample(stft, ltft);
        
        final medians = {
          'idle': _bins['idle']!.median,
          'low': _bins['low']!.median,
          'part': _bins['part']!.median,
          'high': _bins['high']!.median,
        };
        state = state.copyWith(trimMedians: medians);
      }

      // ЛОГИРОВАНИЕ АНОМАЛИЙ
      if (updatedData['ect'] != null && updatedData['ect']! > 103) {
        _logNuance('overheat', 'Перегрев ОЖ', 'Температура ${updatedData['ect']!.toInt()}°C > 103°C', NuanceSeverity.critical);
      }

      // Логирование коррекций
      if (updatedData['stft'] != null && updatedData['stft']!.abs() > 15) {
        _logNuance('trim_high', 'Коррекция STFT > 15%', 'STFT: ${updatedData['stft']!.toStringAsFixed(1)}%', NuanceSeverity.warning);
      }
      
      // Логирование просадки АКБ
      if (updatedData['volt'] != null && updatedData['volt']! < 10.5 && updatedData['volt']! > 5.0) {
        _logNuance('volt_low', 'Просадка АКБ', 'Напряжение: ${updatedData['volt']!.toStringAsFixed(2)} В', NuanceSeverity.critical);
      }

      // Обновляем график УДК
      final updatedTrace1 = List<double>.from(state.trace1);
      if (updatedData.containsKey('udk_volt')) {
        updatedTrace1.add(updatedData['udk_volt']!);
        if (updatedTrace1.length > 100) updatedTrace1.removeAt(0);
      }

      // Обновляем график ДДК
      final updatedTrace2 = List<double>.from(state.trace2);
      if (updatedData.containsKey('ddk_volt')) {
        updatedTrace2.add(updatedData['ddk_volt']!);
        if (updatedTrace2.length > 100) updatedTrace2.removeAt(0);
      }

      state = state.copyWith(liveData: updatedData, trace1: updatedTrace1, trace2: updatedTrace2);

    } catch (e) {
      // Ошибка опроса
    }
  }

  // Чтение реальных кодов ошибок
  Future<List<String>> readDtcs() async {
    List<String> foundCodes = [];
    if (!state.isConnected) return foundCodes;

    try {
      // Пробуем стандартный OBD2 запрос (03), если не выйдет — шлем UDS (190208)
      String response = await _btService.sendCommand('03', timeoutMs: 2000);
      List<int>? bytes = ObdParser.extractBytes(response, '43');

      if (bytes == null) {
        // Если OBD2 не ответил, пробуем UDS
        response = await _btService.sendCommand('190208', timeoutMs: 2000);
        bytes = ObdParser.extractBytes(response, '590208');
      }

      if (bytes != null && bytes.isNotEmpty) {
        // Первый байт — количество ошибок. Дальше идут пары байтов (сами коды).
        int count = bytes[0];
        for (int i = 0; i < count; i++) {
          if (bytes.length >= 2 + (i * 2)) {
            int b1 = bytes[1 + (i * 2)];
            int b2 = bytes[2 + (i * 2)];
            if (b1 == 0 && b2 == 0) continue; // Пустые байты
            
            // Расшифровка DTC (P, C, B, U)
            const typeChars = ['P', 'C', 'B', 'U'];
            final type = typeChars[(b1 >> 6) & 0x03];
            final code = '$type${((b1 >> 4) & 0x03)}${(b1 & 0x0F).toRadixString(16).toUpperCase()}${((b2 >> 4) & 0x0F).toRadixString(16).toUpperCase()}${(b2 & 0x0F).toRadixString(16).toUpperCase()}';
            foundCodes.add(code);
          }
        }
      }
    } catch (e) {
      // Ошибка чтения
    }
    return foundCodes;
  }

  Future<void> clearDtcs() async {
    if (!state.isConnected) return;
    await _btService.sendCommand('04', timeoutMs: 1500);
    await _btService.sendCommand('14FFFFFF', timeoutMs: 1500);
  }

  Future<List<Map<String, String>>> getBluetoothDevices() async {
    return await _btService.getPairedDevices();
  }

  // Флаг для экстренной остановки теста
  bool _abortTest = false;
  
  void abortActuatorTest() {
    _abortTest = true;
  }

  Future<void> runActuatorTest({
    required String testName,
    required String cmdOn,
    required String cmdOff,
    required int holdSeconds,
    bool requireEngineRunning = false,
    bool requireEngineStopped = false,
    bool isOneShot = false,
  }) async {
    if (!state.isConnected) return;

    // 1. ПРОВЕРКА УСЛОВИЙ БЕЗОПАСНОСТИ
    final rpm = state.liveData['rpm']?.toInt() ?? 0;
    if (requireEngineRunning && rpm < 500) {
      throw Exception('Двигатель не заведен! Тест невозможен.');
    }
    if (requireEngineStopped && rpm > 0) {
      throw Exception('Двигатель работает! Заглушите мотор перед тестом.');
    }

    _abortTest = false;
    bool commandWasSent = false;

    try {
      // 2. ОТКРЫВАЕМ СЕССИЮ
      await _btService.sendCommand(_isUdsM86 ? '1003' : '1081', timeoutMs: 1000);
      
      // 3. ОТПРАВЛЯЕМ ON (С проверкой на NRC)
      final respOn = await _btService.sendCommand(cmdOn, timeoutMs: 1500);
      
      // Если ЭБУ вернуло Negative Response (7F) — тест не запустился
      if (respOn.contains('7F') || respOn.contains('ERR')) {
        throw Exception('ЭБУ отклонил команду: $respOn');
      }
      
      commandWasSent = true;

      // 4. ДЕРЖИМ (с проверкой на отмену и потерю связи)
      if (!isOneShot) {
        for (int i = 0; i < holdSeconds; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (!state.isConnected) {
            throw Exception('Потеря связи с ЭБУ во время теста!');
          }
          if (_abortTest) {
            throw Exception('Тест отменен пользователем.');
          }
        }
      }

    } finally {
      // 5. ГАРАНТИРОВАННОЕ ОТКЛЮЧЕНИЕ (выполняется ВСЕГДА)
      if (commandWasSent && !isOneShot) {
        try {
          await _btService.sendCommand(cmdOff, timeoutMs: 1500);
          // Дублируем по обоим протоколам для надежности
          if (_isUdsM86) {
            await _btService.sendCommand(cmdOff, timeoutMs: 1000);
          }
        } catch (_) {
          // Если даже тут связь упала — мы ничего не можем сделать, но пробуем
        }
      }
      // Всегда возвращаем стандартную сессию
      try {
        await _btService.sendCommand('1001', timeoutMs: 800);
      } catch (_) {}
    }
  }

  // Универсальный сниффер: опрашивает ЭБУ и возвращает сырые HEX-ответы
  Future<String> runSnifferDump() async {
    if (!state.isConnected) return 'ЭБУ не подключен';

    final sb = StringBuffer();
    sb.writeln('=== ДАМП ОТВЕТОВ ЭБУ ===');
    sb.writeln('Протокол: ${_isUdsM86 ? "UDS (22XX)" : "KWP (21XX)"}\n');

    // Список команд для проверки
    final commands = [
      // Стандартные OBD-II (для БК)
      ('0100', 'Поддерживаемые PID'),
      ('0105', 'Температура ОЖ'),
      ('010B', 'ДАД впуска (MAP)'),
      ('010C', 'Обороты двигателя'),
      ('010D', 'Скорость'),
      ('0110', 'MAF (воздух)'),
      ('0111', 'Дроссель'),
      ('0114', 'УДК'),
      // Расширенные М86
      ('222001', 'UDS блок 1 (основной)'),
      ('222002', 'UDS блок 2 (АЦП)'),
      ('22F190', 'VIN автомобиля'),
    ];

    for (final cmd in commands) {
      try {
        // TesterPresent для поддержки сессии (только для UDS)
        if (_isUdsM86) {
          await _btService.sendCommand('3E00', timeoutMs: 400);
        }
        
        final resp = await _btService.sendCommand(cmd.$1, timeoutMs: 1500);
        final cleanResp = resp.replaceAll('\n', ' ').replaceAll('\r', ' ');
        
        final status = cleanResp.contains('7F') || cleanResp.isEmpty || cleanResp.contains('NO DATA')
            ? '❌ НЕ ОТВЕЧАЕТ'
            : '✅ ОТВЕТ';
        
        sb.writeln('${cmd.$1} (${cmd.$2}) → $status');
        sb.writeln('   $cleanResp\n');
      } catch (e) {
        sb.writeln('${cmd.$1} (${cmd.$2}) → ОШИБКА: $e\n');
      }
    }

    return sb.toString();
  }

  // Адаптация дросселя
  Future<String> runThrottleAdaptation(Function(String) onUpdate) async {
    if (!state.isConnected) return 'ЭБУ не подключен';

    // 1. Проверка условий
    final rpm = state.liveData['rpm']?.toInt() ?? 0;
    final ect = state.liveData['ect']?.toInt() ?? 0;
    final tps = state.liveData['tps']?.toDouble() ?? 0.0;
    
    if (rpm > 0) return '⛔ СРЫВ: Двигатель должен быть заглушен!';
    if (ect < 5 || ect > 100) return '⛔ СРЫВ: Температура ОЖ вне коридора 5..100°C!';
    if (tps > 9.5) return '⛔ СРЫВ: Нажата педаль газа!';

    final sw = Stopwatch()..start();
    int lastEct = 0;

    while (sw.elapsedMilliseconds < 30000) {
      if (!state.isConnected) return '⛔ СРЫВ: Потеря связи с ЭБУ!';
      
      final rVolt = await _btService.sendCommand('ATRV', timeoutMs: 500);
      final volt = double.tryParse(RegExp(r'(\d+\.\d+)').firstMatch(rVolt)?.group(1) ?? '12.0') ?? 12.0;
      if (volt < 10.0) return '⛔ СРЫВ: Напряжение ниже 10.0 В!';

      final rTps = await _btService.sendCommand('0111', timeoutMs: 500);
      final tpsBytes = ObdParser.extractBytes(rTps, '4111');
      if (tpsBytes != null && tpsBytes[0] * 100.0 / 255.0 > 9.5) return '⛔ СРЫВ: Педаль нажата!';

      if (sw.elapsedMilliseconds - lastEct > 5000) {
        final rEct = await _btService.sendCommand('0105', timeoutMs: 500);
        final ectBytes = ObdParser.extractBytes(rEct, '4105');
        if (ectBytes != null && (ectBytes[0] - 40) > 100) return '⛔ СРЫВ: ОЖ > 100°C!';
        lastEct = sw.elapsedMilliseconds;
      }

      onUpdate('Шаг 1/2: Осталось ${30 - (sw.elapsedMilliseconds ~/ 1000)} сек');
      await Future.delayed(const Duration(milliseconds: 250));
    }

    for (int i = 10; i > 0; i--) {
      onUpdate('Шаг 2/2: ВЫКЛЮЧИТЕ ЗАЖИГАНИЕ! Ждем главное реле... $i сек');
      await Future.delayed(const Duration(seconds: 1));
    }

    return '✅ Адаптация дросселя успешно выполнена!';
  }

  // Чтение стоп-кадра (Freeze Frame) для конкретной ошибки
  Future<Map<String, String>> getFreezeFrame(String dtcCode) async {
    final result = <String, String>{};
    if (!state.isConnected) return result;

    try {
      // Стандартные запросы Mode 02 для М86
      final Map<String, String> pids = {
        '020C00': 'Обороты',     // Префикс ответа: 420C
        '020500': 'Темп. ОЖ',    // Префикс ответа: 4205
        '020B00': 'ДАД впуск',   // Префикс ответа: 420B
        '020600': 'STFT',        // Префикс ответа: 4206
        '020700': 'LTFT',        // Префикс ответа: 4207
        '020D00': 'Скорость',    // Префикс ответа: 420D
        '024200': 'Бортсеть',    // Префикс ответа: 4242
      };

      for (final entry in pids.entries) {
        final cmd = entry.key;
        final label = entry.value;
        final prefix = cmd.substring(0, 4); 
        final expectedPrefix = '42${prefix.substring(2)}'; 

        final resp = await _btService.sendCommand(cmd, timeoutMs: 1000);
        final bytes = ObdParser.extractBytes(resp, expectedPrefix);

        if (bytes != null && bytes.isNotEmpty) {
          if (cmd == '020C00' && bytes.length >= 3) {
            result[label] = '${((bytes[1] * 256) + bytes[2]) ~/ 4} об/мин';
          } else if (cmd == '020500' && bytes.length >= 2) {
            result[label] = '${bytes[1] - 40} °C';
          } else if (cmd == '020B00' && bytes.length >= 2) {
            result[label] = '${bytes[1]} кПа';
          } else if (cmd == '020600' && bytes.length >= 2) {
            result[label] = '${((bytes[1] - 128) * 100 / 128).toStringAsFixed(1)} %';
          } else if (cmd == '020700' && bytes.length >= 2) {
            result[label] = '${((bytes[1] - 128) * 100 / 128).toStringAsFixed(1)} %';
          } else if (cmd == '020D00' && bytes.length >= 2) {
            result[label] = '${bytes[1]} км/ч';
          } else if (cmd == '024200' && bytes.length >= 3) {
            result[label] = '${(((bytes[1] * 256) + bytes[2]) / 1000.0).toStringAsFixed(2)} В';
          }
        }
      }
    } catch (e) {
      // Игнорируем ошибки чтения
    }
    return result;
  }

  // Экспорт журнала в CSV
  Future<String> exportJournalToCsv() async {
    final sb = StringBuffer();
    
    // Заголовок файла
    sb.writeln('=== ЖУРНАЛ ДИАГНОСТИКИ (VestaScan Pro v2.0.0) ===');
    sb.writeln('Дата экспорта: ${DateTime.now().toIso8601String()}');
    sb.writeln('Всего событий: ${state.nuances.length}');
    sb.writeln('Протокол: ${_isUdsM86 ? "UDS" : "KWP-CAN"}');
    sb.writeln('');
    
    // Заголовки колонок
    sb.writeln('Time_ISO;Severity;Title;Description;HZ_Count;Snapshot');
    
    // Данные
    for (final e in state.nuances) {
      final snapshotStr = e.snapshot.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' | ');
      sb.writeln(
        '${e.timestamp.toIso8601String()};'
        '${e.severity.name.toUpperCase()};'
        '${e.title.replaceAll(';', ',')};'
        '${e.description.replaceAll(';', ',').replaceAll('\n', ' ')};'
        '${e.hzCount};'
        '$snapshotStr'
      );
    }
    
    // Добавляем данные БК
    sb.writeln('');
    sb.writeln('=== ДАННЫЕ ПОЕЗДКИ ===');
    sb.writeln('Пробег: ${tripCalculator.totalDistanceKm.toStringAsFixed(2)} км');
    sb.writeln('Средний расход: ${tripCalculator.averageConsumptionL100Km.toStringAsFixed(2)} л/100км');
    sb.writeln('Потрачено топлива: ${tripCalculator.totalFuelLiters.toStringAsFixed(3)} л');
    sb.writeln('Максимальная скорость: ${tripCalculator.maxSpeedKmh.toStringAsFixed(1)} км/ч');
    
    // Текущие живые данные
    sb.writeln('');
    sb.writeln('=== ТЕКУЩИЕ ДАННЫЕ ===');
    sb.writeln('Обороты: ${state.liveData['rpm']?.toInt() ?? '---'} об/мин');
    sb.writeln('ОЖ: ${state.liveData['ect']?.toInt() ?? '---'} °C');
    sb.writeln('ДАД: ${state.liveData['map']?.toInt() ?? '---'} кПа');
    sb.writeln('STFT: ${state.liveData['stft']?.toStringAsFixed(1) ?? '---'} %');
    sb.writeln('LTFT: ${state.liveData['ltft']?.toStringAsFixed(1) ?? '---'} %');
    
    final csvText = sb.toString();
    
    // 1. Копируем в буфер обмена
    await Clipboard.setData(ClipboardData(text: csvText));
    
    // 2. Сохраняем в файл
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filename = 'VestaScan_${DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19)}.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csvText);
      return '✅ Экспортировано:\n${file.path}';
    } catch (e) {
      return '⚠️ В буфер скопировано, но файл не сохранен: $e';
    }
  }
}
// lib/providers/obd_provider.dart — OBD-сессия: подключение, опрос, журнал.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ecu_profile.dart';
import '../services/ai_prompt_builder.dart';
import '../services/bluetooth_service.dart';
import '../services/dtc_service.dart';
import '../services/obd_parser.dart';
import '../services/trip_calculator.dart';
import 'obd_state.dart';

final bluetoothServiceProvider = Provider((ref) => BluetoothService.instance);

final obdProvider = StateNotifierProvider<ObdNotifier, ObdState>(
  (ref) => ObdNotifier(ref.read(bluetoothServiceProvider)),
);

class ObdNotifier extends StateNotifier<ObdState> {
  ObdNotifier(this._bt) : super(ObdState()) {
    _loadProfile();
  }

  final BluetoothService _bt;
  final TripCalculator tripCalculator = TripCalculator();

  bool _isCycleBusy = false;
  int _cycle = 0;
  int _errStreak = 0;
  EcuProfile? _ecuProfile;
  final Map<String, DateTime> _lastNuanceTimes = {};

  Future<void> _loadProfile() async {
    try {
      final jsonString =
          await rootBundle.loadString('lib/data/json_profiles/m86_uds.json');
      _ecuProfile = EcuProfile.fromJson(jsonDecode(jsonString));
    } catch (e) {
      debugPrint('[OBD] профиль ЭБУ не загружен: $e');
    }
  }

  // ── Подключение и определение ЭБУ ──────────────────────────────────────
  Future<bool> connect(String macAddress) async {
    state = state.copyWith(statusText: 'Подключение к $macAddress...');
    final ok = await _bt.connect(macAddress);
    if (!ok) {
      final reason = _bt.lastError ?? 'неизвестная причина';
      state = state.copyWith(isConnected: false, statusText: 'Ошибка подключения: $reason');
      return false;
    }

    final initOk = await _bt.initializeAdapter();

    // Паспорт ЭБУ: 0904 (multi-frame → 2000/250)
    String ecuId = state.ecuId;
    final idBytes = ObdParser.extractBytes(
        await _bt.sendCommand('0904', timeoutMs: 2000, postDelayMs: 250), '4904');
    if (idBytes != null && idBytes.isNotEmpty) {
      final chars = idBytes
          .where((b) => b >= 32 && b <= 126)
          .map((b) => String.fromCharCode(b))
          .join()
          .trim();
      if (chars.isNotEmpty) ecuId = chars;
    }

    // Протокол: KWP (1081) или UDS (1003)
    bool isUds = false;
    final r81 = await _bt.sendCommand('1081', timeoutMs: 800);
    if (!r81.replaceAll(' ', '').contains('5081')) {
      final r03 = await _bt.sendCommand('1003', timeoutMs: 800);
      if (r03.replaceAll(' ', '').contains('5003')) isUds = true;
    }

    state = state.copyWith(
      isConnected: true, connectedDevice: macAddress, ecuId: ecuId,
      ecuType: _detectEcuType(ecuId), isUds: isUds, initOk: initOk,
      statusText:
          'На связи · $ecuId · ${isUds ? 'UDS' : 'KWP'}${initOk ? '' : ' · init!'}',
      lastError: null,
    );
    _logNuance(
        'session_start',
        'Сессия открыта',
        'Протокол: ${isUds ? 'UDS (1003)' : 'KWP-CAN (1081)'} · Калибровка: $ecuId'
            '${initOk ? '' : ' · ВНИМАНИЕ: init частичный'}',
        initOk ? NuanceSeverity.info : NuanceSeverity.warning);
    return true;
  }

  String _detectEcuType(String id) {
    final upper = id.toUpperCase();
    if (upper.contains('I785')) return 'Итэлма М86 (1.8л · UDS)';
    if (upper.contains('765') || upper.contains('M86') || upper.contains('I86')) return 'Итэлма М86 (1.6л · UDS)';
    if (upper.contains('M74')) return 'Итэлма М74';
    if (upper.contains('ME17')) return 'Bosch ME17.9.7';
    return 'ЭБУ не определён';
  }

  Future<void> disconnect() async {
    stopPolling();
    await _bt.disconnect();
    state = state.copyWith(
        isConnected: false, isPolling: false, statusText: 'Отключено');
  }

  void startPolling() {
    if (!state.isConnected || state.isPolling) return;
    _errStreak = 0;
    state = state.copyWith(isPolling: true);
    _runPollingLoop();
  }

  void stopPolling() {
    if (!state.isPolling) return;
    state = state.copyWith(isPolling: false);
  }

  void resetTrip() {
    tripCalculator.reset();
    state = state.copyWith();
  }

  // ── Пауза опроса для сниффера (экран «Анализ») ─────────────────────────
  Future<bool> pauseForSniffer() async {
    final wasPolling = state.isPolling;
    if (wasPolling) stopPolling();
    while (_isCycleBusy) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    return wasPolling;
  }

  void resumeAfterSniffer(bool wasPolling) {
    if (wasPolling && state.isConnected) startPolling();
  }

  Future<String> sendCommandForSniffer(String cmd,
          {int timeoutMs = 1600, int postDelayMs = 120}) =>
      _bt.sendCommand(cmd, timeoutMs: timeoutMs, postDelayMs: postDelayMs);

  // ── Цикл опроса ────────────────────────────────────────────────────────
  void _pushTrace(List<double> trace, Map<String, double> d, String key, double v) {
    d[key] = v;
    trace.add(v);
    if (trace.length > 80) trace.removeAt(0);
  }

  Future<void> _runPollingLoop() async {
    while (state.isPolling && _bt.isConnected) {
      if (_isCycleBusy) {
        await Future.delayed(const Duration(milliseconds: 40));
        continue;
      }
      _isCycleBusy = true;
      var gotAny = false;
      try {
        final d = Map<String, double>.from(state.liveData);
        final t1 = List<double>.from(state.trace1);
        final t2 = List<double>.from(state.trace2);
        String rawBlock = state.rawLastBlock1;

        // TesterPresent (UDS 3E00) каждые ~5 циклов для поддержания 1003 сессии
        if (_cycle % 5 == 0 && state.isUds) {
          await _bt.sendCommand('3E00', timeoutMs: 500);
        }

        // Бортсеть (ATRV)
        final mV = RegExp(r'(\d+[.,]\d+)')
            .firstMatch(await _bt.sendCommand('ATRV', timeoutMs: 500));
        final v = mV == null ? null : double.tryParse(mV.group(1)!.replaceAll(',', '.'));
        if (v != null && v > 4.5 && v < 18.5) {
          d['volt'] = v;
          if (d['min_volt'] == null || v < d['min_volt']!) d['min_volt'] = v;
          gotAny = true;
        }
        if (!state.isPolling) break;

        // Быстрые PID (на I765BJ56v3 работают гарантированно)
        final bRpm = ObdParser.extractBytes(
            await _bt.sendCommand('010C', timeoutMs: 600), '410C');
        if (bRpm != null && bRpm.length >= 2) {
          d['rpm'] = ((bRpm[0] * 256) + bRpm[1]) / 4;
          gotAny = true;
        }
        
        final bStft = ObdParser.extractBytes(
            await _bt.sendCommand('0106', timeoutMs: 600), '4106');
        if (bStft != null && bStft.isNotEmpty) d['stft'] = (bStft[0] - 128) * 100.0 / 128.0;
        
        final bLtft = ObdParser.extractBytes(
            await _bt.sendCommand('0107', timeoutMs: 600), '4107');
        if (bLtft != null && bLtft.isNotEmpty) d['ltft'] = (bLtft[0] - 128) * 100.0 / 128.0;

        if (_cycle % 2 == 0) {
          // ТОЖ / дроссель / ДК1 / ДК2
          final bEct = ObdParser.extractBytes(
              await _bt.sendCommand('0105', timeoutMs: 600), '4105');
          if (bEct != null && bEct.isNotEmpty && bEct[0] > 20 && bEct[0] < 170) {
            d['ect'] = (bEct[0] - 40).toDouble();
          }
          if (!state.isPolling) break;
          
          final bTps = ObdParser.extractBytes(
              await _bt.sendCommand('0111', timeoutMs: 600), '4111');
          if (bTps != null && bTps.isNotEmpty) {
            d['tps'] = bTps[0] * 100.0 / 255.0;
          }
          
          final bUdk = ObdParser.extractBytes(
              await _bt.sendCommand('0114', timeoutMs: 600), '4114');
          if (bUdk != null && bUdk.isNotEmpty) _pushTrace(t1, d, 'udk', bUdk[0] / 200.0);
          
          final bDdk = ObdParser.extractBytes(
              await _bt.sendCommand('0115', timeoutMs: 600), '4115');
          if (bDdk != null && bDdk.isNotEmpty) _pushTrace(t2, d, 'ddk', bDdk[0] / 200.0);
        } else {
          // Скорость / нагрузка / Заводской блок M86
          final bSpd = ObdParser.extractBytes(
              await _bt.sendCommand('010D', timeoutMs: 600), '410D');
          if (bSpd != null && bSpd.isNotEmpty) {
            d['speed'] = bSpd[0].toDouble();
            gotAny = true;
          }
          if (!state.isPolling) break;
          
          // MAP (010B) не поддерживается на M86, используем Нагрузку (0104)
          final bLoad = ObdParser.extractBytes(
              await _bt.sendCommand('0104', timeoutMs: 600), '4104');
          if (bLoad != null && bLoad.isNotEmpty) {
            final loadPct = bLoad[0] * 100.0 / 255.0;
            d['load'] = loadPct;
            d['map'] = (loadPct * 0.95 + 12.0).roundToDouble().clamp(20.0, 105.0);
          }

          // ГЛАВНЫЙ БЛОК ТЕЛЕМЕТРИИ UDS (220001) - 80 байт
          if (state.isUds) {
            final raw = await _bt.sendCommand('220001', timeoutMs: 2000, postDelayMs: 250);
            rawBlock = raw.replaceAll('\n', ' ');
            final bytes = ObdParser.extractBytes(raw, '620001');
            if (bytes != null && bytes.length > 16) {
              gotAny = true;
            }
          }
        }

        // Бортовой компьютер и Массовый расход воздуха (Speed-Density)
        final rpm = d['rpm']?.toInt() ?? 0;
        final map = d['map'];
        if (map != null) {
          final iatK = (d['iat'] ?? 30.0) + 273.15;
          final cyclicAir = (map * 3.05 * (293.15 / iatK)).clamp(40.0, 520.0);
          final air = rpm > 300 ? ((cyclicAir * rpm * 2 * 60) / 1000000.0).clamp(1.0, 180.0) : 0.0;
          d['air_mass_kgh'] = air;
          final tps = d['tps'] ?? 0.0;
          
          tripCalculator.update(
            rpm: rpm,
            speedKmh: d['speed'] ?? 0.0,
            airMassKgH: air,
            tpsPct: tps,
            isDfcoActive: rpm > 1500 && tps < 2.0,
            stftPct: d['stft'] ?? 0.0,
            ltftPct: d['ltft'] ?? 0.0,
          );
        }

        // Контроль живости
        _errStreak = gotAny ? 0 : _errStreak + 1;
        if (_errStreak >= 3 || !_bt.isConnected) {
          stopPolling();
          state = state.copyWith(
              isConnected: _bt.isConnected,
              statusText: 'Связь потеряна — переподключитесь',
              lastError: 'ERR_STREAK');
          _logNuance('bt_drop', 'Обрыв связи',
              'Три цикла опроса без единого ответа ЭБУ', NuanceSeverity.critical);
          break;
        }

        _cycle++;
        state = state.copyWith(
            liveData: d, trace1: t1, trace2: t2, rawLastBlock1: rawBlock);
      } finally {
        _isCycleBusy = false;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (state.isPolling) {
      final lost = !_bt.isConnected;
      state = state.copyWith(
          isPolling: false, isConnected: _bt.isConnected,
          statusText: lost ? 'Связь потеряна — переподключитесь' : 'Опрос остановлен',
          lastError: lost ? 'LINK_LOST' : state.lastError);
      if (lost) {
        _logNuance('bt_drop', 'Обрыв связи', 'Соединение с адаптером потеряно', NuanceSeverity.critical);
      }
    }
  }

  // ── DTC (делегировано DtcService) ──────────────────────────────────────
  Future<List<String>> readDtcs() async {
    final codes = await DtcService.readCodes(_bt);
    state = state.copyWith(dtcList: codes);
    return codes;
  }

  Future<void> clearDtcs() async {
    await _bt.sendCommand('04', timeoutMs: 2000);
    state = state.copyWith(dtcList: const []);
    _logNuance('dtc_clear', 'Сброс DTC', 'Mode 04 выполнен', NuanceSeverity.info);
  }

  Future<Map<String, double?>> getFreezeFrame(String code) =>
      DtcService.readFreezeFrame(_bt, code);

  // ── Журнал ─────────────────────────────────────────────────────────────
  void _logNuance(String id, String title, String desc, NuanceSeverity sev,
      {int cooldownSec = 25}) {
    final now = DateTime.now();
    if (_lastNuanceTimes.containsKey(id) &&
        now.difference(_lastNuanceTimes[id]!).inSeconds < cooldownSec) {
      return;
    }
    _lastNuanceTimes[id] = now;

    final snapshot = <String, String>{
      if (state.liveData['rpm'] != null) 'RPM': '${state.liveData['rpm']!.toInt()}',
      if (state.liveData['ect'] != null) 'ОЖ': '${state.liveData['ect']!.toInt()}°C',
      if (state.liveData['volt'] != null)
        'Сеть': '${state.liveData['volt']!.toStringAsFixed(2)}В',
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
      ex.snapshot = snapshot;
      list.insert(0, ex);
    } else {
      list.insert(
          0,
          NuanceEvent(
              id: id,
              timestamp: now,
              severity: sev,
              title: title,
              description: desc,
              snapshot: snapshot));
    }
    if (list.length > 500) list.removeRange(500, list.length);
    state = state.copyWith(nuances: list);
  }

  void clearJournal() {
    state = state.copyWith(nuances: const []);
  }

  // ── ИИ-Снапшот ─────────────────────────────────────────────────────────
  Future<void> copyAiSnapshotPrompt() async {
    final text = AiPromptBuilder.build(
      liveData: state.liveData,
      ecuId: state.ecuId,
      isUds: state.isUds,
      rawLastBlock: state.rawLastBlock1,
      trip: tripCalculator,
    );
    await Clipboard.setData(ClipboardData(text: text));
  }
}

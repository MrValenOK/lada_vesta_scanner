// lib/providers/obd_provider.dart — OBD-сессия: подключение, цикл опроса,
// DTC, ИИ-снапшот. Карта выносов: PID — services/pid_reader.dart, блок
// 220001 — services/m86_block_reader.dart (числовой DID, валидаторы,
// udsStatus), определение ЭБУ — services/ecu_detector.dart, DTC —
// services/dtc_service.dart, журнал — providers/journal_logger.dart.
// V2.0: реальный _errStreak; НЕТ фиктивного ДАД (010B → «—»); pauseForSniffer
// возвращает wasPolling; PID/блок читаются через сервисы, прошивка не нужна.
// П1: ATRV+010C каждый цикл (пост-пауза 50 мс), прочие PID — round-robin,
// блок 220001 — ≤0.2 Гц; интервал 010C >1 c (кроме циклов с блоком) →
// событие журнала rpm_lag — критерий отзывчивости проверяется в поле.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/ecu_parameter.dart';
import '../data/models/ecu_profile.dart';
import '../services/bluetooth_service.dart';
import '../services/dtc_service.dart';
import '../services/ecu_detector.dart';
import '../services/ecu_profile_loader.dart';
import '../services/health_monitor.dart';
import '../services/m86_block_reader.dart';
import '../services/pid_reader.dart';
import '../services/storage_service.dart';
import '../services/trip_calculator.dart';
import '../services/uds_sample.dart';
import 'journal_logger.dart';
import 'obd_state.dart';

final bluetoothServiceProvider = Provider((ref) => BluetoothService.instance);

final obdProvider = StateNotifierProvider<ObdNotifier, ObdState>(
  (ref) => ObdNotifier(ref.read(bluetoothServiceProvider)),
);

class ObdNotifier extends StateNotifier<ObdState> {
  ObdNotifier(this._bt) : super(ObdState()) {
    _init();
  }

  final BluetoothService _bt;
  final TripCalculator tripCalculator = TripCalculator();
  final StorageService _storage = StorageService();
  final HealthMonitor health = HealthMonitor();

  /// Последний успешный адаптер (автовыбор в списке на дашборде).
  String? lastAdapterAddress;
  String? lastAdapterName;

  bool _isCycleBusy = false;
  int _cycle = 0;
  int _errStreak = 0;
  final JournalLogger _journal = JournalLogger();

  late final PidReader _pids = PidReader(send: _bt.sendCommand);

  M86BlockReader? _blockReader; // чтение/валидация блока 220001
  final M86BlockWatcher _blockWatcher = M86BlockWatcher();
  String _udsStatus = '—';
  String _rpmXcheck = 'none'; // 'ok'/'fail'/'none' — последняя честная сверка

  /// DID блока (число) и его валидаторы — для экранов и тестов.
  int get blockDid => _blockReader?.block.did ?? 1;
  DidValidators? get blockValidators => _blockReader?.block.validators;

  /// Инициализация: профиль ЭБУ (asset → M86BlockReader), поездка/БК и журнал
  /// с последним адаптером — всё переживает перезапуск. Профиль не загрузился
  /// → null: в UI «НЕТ ДАННЫХ», без выдуманных значений. После загрузки —
  /// copyWith, чтобы UI сразу увидел восстановленные цифры.
  Future<void> _init() async {
    _blockReader = await EcuProfileLoader.loadBlockReader(_bt.sendCommand);
    await tripCalculator.load();
    _journal.loadJson(await _storage.loadJournal());
    final a = await _storage.loadLastAdapter();
    lastAdapterAddress = a?['address'];
    lastAdapterName = a?['name'];
    if (mounted) state = state.copyWith(nuances: _journal.entries);
  }

  // ── Подключение и определение ЭБУ ──────────────────────────────────────
  Future<bool> connect(String macAddress, {String? name}) async {
    state = state.copyWith(statusText: 'Подключение к $macAddress...');
    final ok = await _bt.connect(macAddress);
    if (!ok) {
      final reason = _bt.lastError ?? 'неизвестная причина';
      state = state.copyWith(
          isConnected: false, statusText: 'Ошибка подключения: $reason');
      return false;
    }

    final initOk = await _bt.initializeAdapter();

    // Паспорт и протокол — EcuDetector: 0904 (multi-frame → 2000/250) и
    // детекция 1081/1003; 2200xx читаются в DEFAULT SESSION (из extended
    // выходим сразу, 1001). Fallback — прежняя калибровка, если 0904 молчит.
    final det = await EcuDetector.detect(_bt, fallbackEcuId: state.ecuId);

    health.resetSession();
    await _storage.saveLastAdapter(macAddress, name ?? macAddress);
    lastAdapterAddress = macAddress;
    lastAdapterName = name ?? macAddress;

    state = state.copyWith(
      isConnected: true,
      connectedDevice: macAddress,
      ecuId: det.ecuId,
      ecuType: det.ecuType,
      isUds: det.isUds,
      initOk: initOk,
      passport: det.passport,
      statusText: 'На связи · ${det.ecuId} · ${det.isUds ? 'UDS' : 'KWP'}'
          '${initOk ? '' : ' · init!'}',
      lastError: null,
    );
    _logNuance(
        'session_start',
        'Сессия открыта',
        'Протокол: ${det.isUds ? 'UDS' : 'KWP-CAN'} · Калибровка: ${det.ecuId}'
            '${initOk ? '' : ' · ВНИМАНИЕ: init частичный'}',
        initOk ? NuanceSeverity.info : NuanceSeverity.warning);
    return true;
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
    _blockWatcher.resetPacing();
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

  /// Калибровка БК по чеку: поправка обновляется, накопители обнуляются
  /// (следующий замер — танк-в-танк). false — мало данных/неверный ввод.
  Future<bool> calibrateTripFromFill(double actualLiters) async {
    final ok = tripCalculator.calibrateFromActual(actualLiters);
    if (ok) {
      tripCalculator.reset();
      state = state.copyWith();
    }
    return ok;
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

  // ── Цикл опроса (П1: отзывчивость) ─────────────────────────────────────
  // Каждый цикл — ATRV+010C (пост-пауза 50 мс); прочие PID — строго по
  // одному за цикл (round-robin, полный круг ~3 с); блок 220001 — не чаще
  // 1 раза в 5 с (≤0.2 Гц): обороты не ждут ни пачку PID, ни блок → 010C ≪1 с.
  DateTime? _lastBlockAt;

  bool get _blockDue => _lastBlockAt == null ||
      DateTime.now().difference(_lastBlockAt!) >= const Duration(seconds: 5);

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

        // TesterPresent (UDS 3E00 / KWP 3E) каждые ~20 циклов (~6 с —
        // прежняя реальная частота при более коротком цикле опроса)
        if (_cycle % 20 == 0) {
          await _bt.sendCommand(state.isUds ? '3E00' : '3E', timeoutMs: 500);
        }

        // Ядро каждого цикла: ATRV + 010C; onRpm — только при реальном 010C
        // в этом цикле (для честной сверки с 220001[4..5]).
        if (await _pids.readCoreInto(d,
            isCancelled: () => !state.isPolling,
            onRpm: _blockWatcher.noteEngineRpm)) {
          gotAny = true;
        }
        if (!state.isPolling) break;

        // Критерий П1 «010C ≤ 1 c» — проверяемо по журналу в поле.
        final rpmGap = _blockWatcher.lastRpmGapMs;
        if (rpmGap != null && rpmGap > 1000) {
          _logNuance('rpm_lag', 'Обороты реже 1 с', '010C: $rpmGap мс', NuanceSeverity.warning);
        }

        // Прочие PID (round-robin): один за цикл, полный круг ~3 с.
        if (await _pids.readAuxInto(_cycle, d, t1, t2)) {
          gotAny = true;
        }
        if (!state.isPolling) break;

        // Блок 2200xx (220001) — DEFAULT SESSION: 1003 перед чтением НЕ
        // отправлять; не чаще 1 раза в 5 с. DID — число; запрос/валидация —
        // единственным путём (M86BlockReader); отказ НЕ обнуляет значения.
        final reader = _blockReader;
        if (reader != null && state.isUds && _blockDue) {
          _lastBlockAt = DateTime.now();
          final r = await reader.read();
          rawBlock = r.raw;
          if (r.sample.accepted) {
            final merged = applySample(d, r.sample, reader.block.parameters);
            d
              ..clear()
              ..addAll(merged);
            gotAny = true;
            final xr = _blockWatcher.evaluate(r.udsRpm);
            _rpmXcheck = xr;
            _udsStatus = 'OK · сверка 010C: '
                '${xr == 'ok' ? 'OK' : xr == 'fail' ? 'РАСХОЖДЕНИЕ' : '—'}';
            if (xr == 'fail') {
              _logNuance(
                  'uds_xcheck_fail',
                  'UDS: расхождение RPM',
                  '220001[4..5]=${r.udsRpm?.toInt()} vs 010C=${_blockWatcher.lastRpm?.toInt()}',
                  NuanceSeverity.warning);
            }
          } else {
            _udsStatus = 'отказ: ${r.sample.rejectReason}';
            if (reader.rejects == 1 || reader.rejects % 10 == 0) {
              _logNuance(
                  'uds_reject',
                  'UDS 220001: сэмпл отклонён',
                  '${r.sample.rejectReason} · подряд: ${reader.rejects}',
                  NuanceSeverity.warning);
            }
          }
          // Цикл с блоком исключаем из замера интервала 010C (это не «лаг»
          // отзывчивости, а наша же пауза на чтение блока).
          _blockWatcher.resetPacing();
        }

        // Бортовой компьютер. MAP (010B) не поддерживается — константы НЕ
        // подставляем. Воздух — расчётный по нагрузке 0104: наполнение ≈
        // load/100; масса = 0.000945 · VE · rpm · 60, где 0.000945 =
        // (Vd/2 = 0.8 л → 8e-4 м³) · ρ(25 °C) = 1.181 кг/м³ для 1.6 л (21129);
        // нормы ДАД остаются в справке, в UI — «НЕТ ДАННЫХ».
        final rpm = d['rpm']?.toInt() ?? 0;
        final loadPct = d['load'];
        final ve = (loadPct ?? 0.0) / 100.0;
        final air =
            rpm > 300 ? (0.000945 * ve * rpm * 60).clamp(1.0, 180.0) : 0.0;
        d['air_mass_kgh'] = air;
        final tps = d['tps'] ?? 0.0;
        // Коррекции — парой: Mode 01 0106+0107, иначе UDS-пара (не смешиваем).
        double stft = d['stft'] ?? double.nan;
        double ltft = d['ltft'] ?? double.nan;
        if (stft.isNaN || ltft.isNaN) {
          stft = d['uds_stft'] ?? 0.0;
          ltft = d['uds_ltft'] ?? 0.0;
        }
        // БК обновляем КАЖДЫЙ цикл: пробег/скорость не зависят от того, читался
        // ли 0104 в этом цикле (последняя нагрузка остаётся в d).
        tripCalculator.update(
          rpm: rpm,
          speedKmh: d['speed'] ?? 0.0,
          airMassKgH: air,
          tpsPct: tps,
          isDfcoActive: rpm > 1500 && tps < 2.0,
          stftPct: stft,
          ltftPct: ltft,
        );

        // Сессионный контроль: мин. АКБ/макс. ТОЖ + критические события
        // (просадка при пуске, перегрев) — пороги M86Specs, кулдаун по типу.
        health.observe(d);
        health.checkInto(d, (a) => _logNuance(
            a.id, a.title, a.description, JournalLogger.severityOf(a.severity)));

        // Контроль живости: цикл без единого ответа ЭБУ считаем отказом
        _errStreak = gotAny ? 0 : _errStreak + 1;
        if (_errStreak >= 3 || !_bt.isConnected) {
          stopPolling();
          state = state.copyWith(
              isConnected: _bt.isConnected,
              statusText: 'Связь потеряна — переподключитесь',
              lastError: 'ERR_STREAK');
          _logNuance(
              'bt_drop',
              'Обрыв связи',
              'Три цикла опроса без единого ответа ЭБУ',
              NuanceSeverity.critical);
          break;
        }

        _cycle++;
        state = state.copyWith(
            liveData: d,
            trace1: t1,
            trace2: t2,
            rawLastBlock1: rawBlock,
            udsStatus: _udsStatus);
      } finally {
        _isCycleBusy = false;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    // Выход из цикла: Стоп пользователя или потеря связи. При потере приводим
    // состояние в порядок (иначе UI показывал «Стоп» без данных).
    if (state.isPolling) {
      final lost = !_bt.isConnected;
      state = state.copyWith(
          isPolling: false,
          isConnected: _bt.isConnected,
          statusText:
              lost ? 'Связь потеряна — переподключитесь' : 'Опрос остановлен',
          lastError: lost ? 'LINK_LOST' : state.lastError);
      if (lost) {
        _logNuance('bt_drop', 'Обрыв связи', 'Соединение с адаптером потеряно',
            NuanceSeverity.critical);
      }
    }
  }

  // ── DTC (делегировано DtcService; транспорт — send-функция) ────────────
  Future<List<String>> readDtcs() async {
    final codes = await DtcService.readCodes(_bt.sendCommand);
    health.dtcInto(codes, (a) => _logNuance(
        a.id, a.title, a.description, JournalLogger.severityOf(a.severity)));
    state = state.copyWith(dtcList: codes);
    return codes;
  }

  Future<void> clearDtcs() async {
    await _bt.sendCommand('04', timeoutMs: 2000);
    state = state.copyWith(dtcList: const []);
    _logNuance(
        'dtc_clear', 'Сброс DTC', 'Mode 04 выполнен', NuanceSeverity.info);
  }

  Future<Map<String, double?>> getFreezeFrame(String code) =>
      DtcService.readFreezeFrame(_bt.sendCommand, code);

  // ── Журнал — делегирован JournalLogger (cooldown/HZ/снимок/лимит 500) ──
  void _logNuance(String id, String title, String desc, NuanceSeverity sev,
      {int? cooldownSec}) {
    final logged = _journal.log(id, title, desc, sev,
        JournalLogger.snapshotOf(state.liveData), cooldownSec: cooldownSec);
    // Подавленный повтором-кулдауном событие не дёргает UI, но HZ учтён.
    if (logged) {
      state = state.copyWith(nuances: _journal.entries);
      unawaited(_storage.saveJournal(_journal.toJson()));
    }
  }

  void clearJournal() {
    _journal.clear();
    unawaited(_storage.clearJournal());
    state = state.copyWith(nuances: const []);
  }

  // ── ИИ-Снапшот: данные сессии для providers/ai_snapshot_provider.dart ──
  // Сборка текста — в провайдере (нужен и trimMatrixProvider); здесь только
  // честные счётчики блока и последняя сверка.
  int get blockAccepted => _blockReader?.accepted ?? 0;
  int get blockRejected => _blockReader?.rejected ?? 0;
  List<EcuParameter> get blockParams =>
      _blockReader?.block.parameters ?? const [];
  String get rpmXcheck => _rpmXcheck;
}

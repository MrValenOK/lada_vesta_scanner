// lib/providers/trim_matrix_provider.dart — состояние матрицы коррекций.
// Провайдер сам подписан на obdProvider: каждый новый liveData цикла опроса
// даёт попытку замера (Total Trim = STFT + LTFT; пара Mode 01 0106+0107
// приоритетно, иначе пара uds_stft+uds_ltft — источники не смешиваются).
// От старта опроса отсчитываются первые секунды пуска (grace) — не копим.
// Накопленное пишется в shared_preferences (debounce 800 мс, как в источнике).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../services/trim_matrix.dart';
import 'obd_provider.dart';

final trimMatrixProvider =
    StateNotifierProvider<TrimMatrixNotifier, TrimMatrix>((ref) {
  final notifier = TrimMatrixNotifier();
  ref.listen(obdProvider, (prev, next) {
    final wasPolling = prev?.isPolling ?? false;
    if (next.isPolling && !wasPolling) notifier.notePollStart();
    if (!next.isPolling && wasPolling) notifier.notePollStop();
    if (next.isPolling) notifier.ingest(next.liveData);
  });
  return notifier;
});

class TrimMatrixNotifier extends StateNotifier<TrimMatrix> {
  TrimMatrixNotifier() : super(TrimMatrix()) {
    _load();
  }

  final TrimMatrixStore _store = TrimMatrixStore();
  Timer? _saveDebounce;
  DateTime? _pollStartedAt;

  /// Старт опроса: точка отсчёта «первых секунд пуска»; стоп — сброс.
  void notePollStart() => _pollStartedAt = DateTime.now();
  void notePollStop() => _pollStartedAt = null;

  Future<void> _load() async {
    await _store.loadInto(state);
    if (!mounted) return;
    state = state.copy();
  }

  /// Принять телеметрию цикла. Источники НЕ смешиваются: если пары Mode 01
  /// нет целиком — берём пару UDS; иначе замер пропускается.
  /// Возвращает true, если замер прошёл гейты и учтён.
  bool ingest(Map<String, double> d) {
    final rpm = d['rpm'];
    double? stft = d['stft'];
    double? ltft = d['ltft'];
    if (stft == null || ltft == null) {
      stft = d['uds_stft'];
      ltft = d['uds_ltft'];
    }
    if (rpm == null || stft == null || ltft == null) return false;

    final tps = d['tps'];
    final udk = d['udk'];
    final dfco = rpm > M86Specs.trimDfcoRpmMin &&
        (tps ?? 100.0) < M86Specs.trimDfcoTpsMax;
    final o2Cold = udk != null &&
        udk >= M86Specs.o2ColdRefMinV &&
        udk <= M86Specs.o2ColdRefMaxV;
    final started = _pollStartedAt;
    final pollSeconds = started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds / 1000.0;

    final added = state.addSample(
      rpm: rpm,
      stftPct: stft,
      ltftPct: ltft,
      ectC: d['ect'],
      tpsPct: tps,
      dfcoCutoff: dfco,
      o2Cold: o2Cold,
      pollSeconds: pollSeconds,
    );
    if (added) {
      state = state.copy();
      _scheduleSave();
    }
    return added;
  }

  void reset() {
    state.reset();
    state = state.copy();
    _store.clear();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      _store.save(state);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

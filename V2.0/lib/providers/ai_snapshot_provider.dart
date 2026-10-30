// lib/providers/ai_snapshot_provider.dart — сборка текста ИИ-Снапшота (П6).
// Слой providers: видит obdProvider (сессия, журнал, здоровье, счётчики
// блока) и trimMatrixProvider (накопленная матрица) — UI только копирует.
// Текст формирует services/ai_prompt_builder.dart (он о провайдерах не знает).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_prompt_builder.dart';
import 'obd_provider.dart';
import 'trim_matrix_provider.dart';

/// Функция сборки снапшота: считается по требованию (в UI — по нажатию),
/// а не на каждом тике опроса.
final aiSnapshotProvider = Provider<String Function()>((ref) {
  return () {
    final st = ref.read(obdProvider);
    final notifier = ref.read(obdProvider.notifier);
    final matrix = ref.read(trimMatrixProvider);
    return AiPromptBuilder.build(
      liveData: st.liveData,
      ecuId: st.ecuId,
      ecuType: st.ecuType,
      isConnected: st.isConnected,
      isPolling: st.isPolling,
      isUds: st.isUds,
      udsStatus: st.udsStatus,
      rpmXcheck: notifier.rpmXcheck,
      udsAccepted: notifier.blockAccepted,
      udsRejected: notifier.blockRejected,
      udsParams: notifier.blockParams,
      passport: st.passport,
      minVoltage: notifier.health.minVoltage,
      maxEct: notifier.health.maxEct,
      matrix: matrix,
      trip: notifier.tripCalculator,
      dtcCodes: st.dtcList,
      journal: [
        for (final e in st.nuances.take(AiPromptBuilder.journalLimit))
          AiJournalEntry(
            time: e.timeStr,
            severity: e.severity.name,
            title: e.title,
            description: e.description,
          ),
      ],
    );
  };
});

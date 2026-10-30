// lib/services/ai_uds_section.dart — раздел 3 ИИ-Снапшота: блок UDS 220001
// со статусом достоверности КАЖДОГО поля (вынесено из ai_prompt_builder,
// лимит 400 строк/файл). Смещения/формулы/статусы берутся из профиля
// (m86_uds.json → EcuParameter), а не дублируются в коде промпта.
// Значение есть только то, что реально пришло в принятом пакете; иначе «—».
import '../data/models/ecu_parameter.dart';
import 'ai_prompt_format.dart';

class AiUdsSection {
  AiUdsSection._();

  /// Строки раздела: валидатор, кросс-проверка оборотов, поля профиля,
  /// эпистемическая сводка (подтверждено / ждут сверки / кандидаты).
  static List<String> lines({
    required List<EcuParameter> params,
    required Map<String, double> data,
    required String udsStatus,
    required String rpmXcheck,
    required int accepted,
    required int rejected,
  }) {
    final out = <String>[
      '• Валидатор 220001: $udsStatus; пакетов принято: $accepted, '
          'отклонено: $rejected',
      '• Кросс-проверка 010C ↔ 220001[4..5]: ${_xcheckText(rpmXcheck)}',
    ];
    if (params.isEmpty) {
      out.add('• Поля блока: профиль не загружен — значения UDS не '
          'подставляются.');
      return out;
    }
    out.add('• Поля блока (смещение — DATA после 62 00 01, формула — '
        'каноническая value = raw × multiplier + addend):');
    for (final p in params) {
      out.add(_fieldLine(p, data));
    }
    out.add(_epistemics(params));
    return out;
  }

  static String _fieldLine(EcuParameter p, Map<String, double> d) =>
      '   – ${p.id} @${p.byteOffset} (${p.width} Б, ${_formula(p)}): '
      '${AiFmt.val(d[p.id], p.decimals, p.unit)} | ${_statusRu(p.status)}';

  /// Формула профиля в человекочитаемом виде: raw × m ± a.
  static String _formula(EcuParameter p) {
    final sign = p.addend < 0 ? '−' : '+';
    return 'raw × ${AiFmt.trim(p.multiplier, 5)} $sign '
        '${AiFmt.trim(p.addend.abs(), 5)}';
  }

  static String _statusRu(String status) => switch (status) {
        'confirmed' => 'статус: ПОДТВЕРЖДЁН',
        'observed_pending_synchronous_crosscheck' =>
          'статус: КАНДИДАТ (observed_pending — ждёт синхронной сверки ≤1 c)',
        'candidate' => 'статус: КАНДИДАТ (не доказан)',
        'raw' => 'статус: СЫРЫЕ БАЙТЫ (не интерпретировано)',
        '' => 'статус: НЕ УКАЗАН В ПРОФИЛЕ',
        _ => 'статус: ${status.toUpperCase()}',
      };

  static String _epistemics(List<EcuParameter> ps) {
    String ids(bool Function(EcuParameter) f) {
      final l = ps.where(f).map((p) => p.id).toList();
      return l.isEmpty ? 'нет' : l.join(', ');
    }

    return '• Достоверность: подтверждено — '
        '${ids((p) => p.status == 'confirmed')}; ждут синхронной сверки — '
        '${ids((p) => p.awaitingSyncCrosscheck)}; кандидаты — '
        '${ids((p) => p.status == 'candidate')}. Кандидаты НЕ доказаны: '
        'выводы по ним — только гипотезы.';
  }

  static String _xcheckText(String x) => switch (x) {
        'ok' => 'OK — пара в пределах ≤1 c и ≤50 об/мин',
        'fail' => 'РАСХОЖДЕНИЕ — пара ≤1 c есть, разница > 50 об/мин '
            '(поле uds_rpm под вопросом)',
        _ => '— (синхронной пары ≤1 c нет — сверка не выполнена)',
      };
}

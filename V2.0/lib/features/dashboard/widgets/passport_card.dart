// lib/features/dashboard/widgets/passport_card.dart — паспорт ЭСУД:
// калибровка 0904 и вендорские DID М86 (220091 — номер применения,
// 220097 — модель/ДВС, 22009A — укороченный ID ПО). Показывается только
// реально прочитанное, иначе «—». VIN-подобный 0x0090 не читается (M1).
// Цвета — только токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/obd_provider.dart';

class EcuPassportCard extends ConsumerWidget {
  const EcuPassportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final st = ref.watch(obdProvider);
    final p = st.passport;

    return Container(
      padding: const EdgeInsets.all(S.s4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('ПАСПОРТ ЭСУД',
                    style: TextStyle(
                        color: c.text3, fontWeight: FontWeight.bold)),
              ),
              if (st.isConnected)
                Text(st.ecuType,
                    style: TextStyle(fontSize: T.cap, color: c.text3)),
            ],
          ),
          Divider(color: c.border),
          _row(c, 'Калибровка (0904)', st.isConnected ? st.ecuId : '—'),
          _row(c, 'Номер применения (220091)', p['part'] ?? '—'),
          _row(c, 'Модель/ДВС (220097)', p['model'] ?? '—'),
          _row(c, 'ПО, краткий ID (22009A)', p['sw_short'] ?? '—'),
          if (p.isEmpty)
            Text(
                st.isConnected
                    ? 'Паспортные DID не ответили — поля останутся «—» (никаких заглушек).'
                    : 'Паспорт читается при подключении к ЭБУ.',
                style: TextStyle(fontSize: T.cap, color: c.text3))
          else
            Text(
                '22009A — укороченный дубль калибровки; расхождение с 0904 — '
                'известный открытый вопрос (бэклог), не ошибка чтения.',
                style: TextStyle(fontSize: T.cap, color: c.text3)),
        ],
      ),
    );
  }

  Widget _row(AppColors c, String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: T.sm, color: c.text2)),
          Text(val, style: AppTheme.mono(size: T.sm, color: c.accent)),
        ],
      ),
    );
  }
}

// lib/features/dashboard/widgets/sensor_card.dart — плашка телеметрии:
// значение, признак «живой» (точка), ориентир нормы и индикация выхода
// за допуск (AppColors); тап — шторка справки (spec_sheet). Вынесено из
// dashboard_cards.dart (лимит 400 строк: карточка получила свою логику).
import 'package:flutter/material.dart';

import '../../../core/spec_notes.dart';
import '../../../core/theme.dart';
import 'spec_sheet.dart';

class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.isLive,
    this.specKey,
    this.specData,
  });

  final String title;
  final String value;
  final String unit;
  final bool isLive;

  /// Ключ справки (kSpecNotes); null — норма и тап не показываются.
  final String? specKey;

  /// Данные опроса — для оценки нормы (checkSpec) и шторки справки.
  final Map<String, double>? specData;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final key = specKey;
    final check =
        (key != null && specData != null) ? checkSpec(key, specData!) : null;
    final note = key != null ? kSpecNotes[key] : null;
    final rangeText = key != null ? specRangeText(key) : null; // '90–103'
    final isOut = check?.status == SpecStatus.out;

    final card = Container(
      padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border(
          // Левая полоса — допуск: в норме success, вне нормы warning,
          // иначе нейтрально (нет выдуманных «зелёных»).
          left: BorderSide(
              color: switch (check?.status) {
            SpecStatus.ok => c.success,
            SpecStatus.out => c.warning,
            _ => c.border,
          }, width: 4),
          top: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: T.cap,
                        fontWeight: FontWeight.bold,
                        color: c.text3)),
              ),
              if (isLive)
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: c.success, shape: BoxShape.circle)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: AppTheme.mono(size: value.length > 6 ? T.sm : T.lg)),
              const SizedBox(width: S.s1),
              Text(unit, style: TextStyle(fontSize: T.cap, color: c.text3)),
            ],
          ),
          if (note != null)
            Text(
              rangeText != null ? 'норма $rangeText ${note.unit}' : 'нормы нет',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: T.cap, color: isOut ? c.warning : c.text3),
            ),
        ],
      ),
    );

    if (key == null || specData == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(R.md),
      onTap: () => showSpecSheet(context,
          specKey: key,
          data: specData!,
          currentText: unit.isEmpty ? value : '$value $unit'),
      child: card,
    );
  }
}

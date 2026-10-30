// lib/features/dashboard/widgets/spec_sheet.dart — шторка справки по параметру:
// норма (ТИ 3100.25100.12056, табл. 2.4-01), условие проверки и типичные
// причины отклонения. Цвета — только токены AppColors.
import 'package:flutter/material.dart';

import '../../../core/spec_notes.dart';
import '../../../core/theme.dart';

void showSpecSheet(
  BuildContext context, {
  required String specKey,
  required Map<String, double> data,
  required String currentText,
}) {
  final note = kSpecNotes[specKey];
  if (note == null) return;
  final check = checkSpec(specKey, data);
  final rangeText = specRangeText(specKey);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl))),
    builder: (ctx) {
      final c = ctx.appColors;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(S.s6, S.s4, S.s6, S.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(note.title,
                        style: TextStyle(
                            fontSize: T.lg,
                            fontWeight: FontWeight.w800,
                            color: c.text1)),
                  ),
                  _StatusChip(status: check.status),
                ],
              ),
              const SizedBox(height: S.s2),
              Text('сейчас: $currentText',
                  style: AppTheme.mono(size: T.sm, color: c.text2)),
              const SizedBox(height: S.s4),
              _Line(
                  c: c,
                  label: 'Норма ХХ',
                  value: rangeText != null
                      ? '$rangeText ${note.unit}'
                      : 'не нормируется'),
              if (note.extraNorm != null)
                _Line(c: c, label: 'Дополнительно', value: note.extraNorm!),
              _Line(c: c, label: 'Условие проверки', value: note.condition),
              if (note.causes.isNotEmpty) ...[
                const SizedBox(height: S.s4),
                Text('Типичные причины отклонения',
                    style: TextStyle(
                        fontSize: T.sm,
                        fontWeight: FontWeight.w800,
                        color: c.text1)),
                const SizedBox(height: S.s2),
                for (final cause in note.causes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.s2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(color: c.text3)),
                        Expanded(
                          child: Text(cause,
                              style: TextStyle(
                                  fontSize: T.sm, color: c.text2, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
              ],
              if (note.caveat != null) ...[
                const SizedBox(height: S.s2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(S.s3),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(note.caveat!,
                      style: TextStyle(
                          fontSize: T.cap, color: c.text3, height: 1.35)),
                ),
              ],
              const SizedBox(height: S.s5),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.surface2, foregroundColor: c.text1),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SpecStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (label, fg, bg) = switch (status) {
      SpecStatus.ok => ('в норме', c.success, c.successSoft),
      SpecStatus.out => ('вне нормы', c.warning, c.warningSoft),
      SpecStatus.pending => ('условие не выполнено', c.text3, c.surface2),
      SpecStatus.none => ('нормы нет', c.text3, c.surface2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(R.sm)),
      child: Text(label,
          style: TextStyle(
              fontSize: T.cap, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.c, required this.label, required this.value});

  final AppColors c;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: TextStyle(fontSize: T.sm, color: c.text3)),
          ),
          Expanded(
            child: Text(value,
                style: AppTheme.mono(size: T.sm, color: c.text1)),
          ),
        ],
      ),
    );
  }
}

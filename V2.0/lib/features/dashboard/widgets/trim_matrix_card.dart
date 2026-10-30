// lib/features/dashboard/widgets/trim_matrix_card.dart — «МАТРИЦА
// САМООБУЧЕНИЯ (ЛИСТ 19 ТИ АВТОВАЗ)»: 4 зоны (среднее Total Trim = STFT+LTFT,
// число замеров) + строкa вердикта; сброс — с подтверждением.
// Порт _buildTrimMapCard (5335a2e), переработан в П3. Цвета — AppColors.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../providers/trim_matrix_provider.dart';
import '../../../services/trim_matrix.dart';

class TrimMatrixCard extends ConsumerWidget {
  const TrimMatrixCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final m = ref.watch(trimMatrixProvider);
    final verdict = m.verdict();

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
              Icon(Icons.grid_on_rounded, color: c.accent, size: 20),
              const SizedBox(width: S.s2),
              Expanded(
                child: Text('4 зоны самообучения М86 (Total Trim = STFT+LTFT)',
                    style: TextStyle(
                        fontSize: T.sm,
                        fontWeight: FontWeight.w800,
                        color: c.text1)),
              ),
              IconButton(
                icon: Icon(Icons.restart_alt_rounded, size: 18, color: c.text2),
                tooltip: 'Сбросить матрицу',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmReset(context, ref),
              ),
            ],
          ),
          const SizedBox(height: S.s1),
          Row(
            children: [
              for (final z in TrimZone.values)
                Expanded(child: _zoneTile(context, m.bins[z]!)),
            ],
          ),
          const SizedBox(height: S.s3),
          Text(verdict.text,
              style: TextStyle(fontSize: T.cap, color: c.text2, height: 1.35)),
        ],
      ),
    );
  }

  /// Сброс с подтверждением: накопленные средние и счётчики теряются навсегда.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить матрицу?'),
        content: const Text('Накопленные замеры по 4 зонам (средние и '
            'счётчики) будут удалены. Отменить это нельзя.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.lightImpact();
      ref.read(trimMatrixProvider.notifier).reset();
    }
  }

  Widget _zoneTile(BuildContext context, TrimBin bin) {
    final c = context.appColors;
    final hasData = bin.isNotEmpty;
    final mean = bin.mean;
    // Цвет допуска: норма (±7 %) — success; заметное отклонение — warning;
    // сильное (> 15 %) — error.
    final color = !hasData
        ? c.text3
        : (mean.abs() <= M86Specs.trimNormOkPct
            ? c.success
            : (mean.abs() <= 15.0 ? c.warning : c.error));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(R.md),
        border:
            hasData ? Border.all(color: color.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        children: [
          Text(bin.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w700, color: c.text2)),
          const SizedBox(height: 5),
          Text(
            hasData
                ? '${mean >= 0 ? '+' : ''}${mean.toStringAsFixed(1)}%'
                : '---',
            style: AppTheme.mono(size: T.sm, color: color),
          ),
          const SizedBox(height: 2),
          Text('${bin.count} зам.',
              style: TextStyle(fontSize: 9, color: c.text3)),
        ],
      ),
    );
  }
}

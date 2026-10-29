// lib/features/journal/journal_screen.dart — журнал событий (HZ-группировка).
// Портировано из lada_vesta_scanner; цвета — только токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/obd_provider.dart';
import '../../providers/obd_state.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  bool _isExporting = false;

  Future<void> _exportCsv() async {
    final st = ref.read(obdProvider);
    setState(() => _isExporting = true);
    final sb = StringBuffer();
    sb.writeln('=== VestaScan Pro V2.0 · Экспорт ===');
    sb.writeln('Устройство: ${st.connectedDevice}');
    sb.writeln('ЭБУ: ${st.ecuType} · Калибровка: ${st.ecuId}');
    sb.writeln('Протокол: ${st.isUds ? 'UDS' : 'KWP-CAN'}');
    sb.writeln('');
    sb.writeln('--- ЖУРНАЛ ---');
    for (final e in st.nuances) {
      sb.writeln('[${e.timeStr}] [HZ:${e.hzCount}] '
          '[${e.severity.name.toUpperCase()}] ${e.title}: ${e.description}');
    }
    sb.writeln('');
    sb.writeln('--- ПАРАМЕТРЫ ---');
    st.liveData.forEach((k, v) => sb.writeln('$k: $v'));
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!mounted) return;
    setState(() => _isExporting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ Экспорт скопирован в буфер обмена'),
      duration: Duration(seconds: 5),
    ));
  }

  Future<void> _clearJournal() async {
    final c = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Очистить журнал?'),
        content: const Text(
            'Все события будут удалены из памяти. Это действие нельзя отменить.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(obdProvider.notifier).clearJournal();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final nuances = ref.watch(obdProvider).nuances;

    return Scaffold(
      appBar: AppBar(
        title: Text('Журнал событий (${nuances.length})'),
        actions: [
          IconButton(
            icon: _isExporting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                  )
                : Icon(Icons.save_alt_rounded, color: c.accent),
            tooltip: 'Экспорт в CSV',
            onPressed: _isExporting ? null : _exportCsv,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: c.text3),
            tooltip: 'Очистить журнал',
            onPressed: _clearJournal,
          ),
        ],
      ),
      body: nuances.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(S.s8),
                child: Text(
                  'Журнал чист.\nАномалии будут автоматически регистрироваться '
                  'здесь со счётчиком HZ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.text3, fontSize: T.sm, height: 1.5),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(S.s4),
              itemCount: nuances.length,
              itemBuilder: (ctx, i) {
                final e = nuances[i];
                final color = e.severity == NuanceSeverity.critical
                    ? c.error
                    : (e.severity == NuanceSeverity.warning ? c.warning : c.accent);

                return Card(
                  color: c.surface,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md),
                    side: BorderSide(color: color.withAlpha(80)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              e.severity == NuanceSeverity.critical
                                  ? Icons.error_outline
                                  : Icons.warning_amber_rounded,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: S.s2),
                            Expanded(
                              child: Text(
                                e.title,
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: T.sm),
                              ),
                            ),
                            if (e.hzCount > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: color.withAlpha(40),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('HZ: ${e.hzCount}',
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(e.description,
                            style:
                                TextStyle(color: c.text2, fontSize: T.cap, height: 1.4)),
                        if (e.snapshot.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: e.snapshot.entries
                                .map((entry) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: c.surface2,
                                          borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        '${entry.key}: ${entry.value}',
                                        style: TextStyle(
                                            color: c.text2,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: S.s2),
                        Text(e.timeStr, style: AppTheme.mono(size: 10, color: c.text3)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

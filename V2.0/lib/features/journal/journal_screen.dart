// lib/features/journal/journal_screen.dart — журнал событий (HZ-группировка).
// Экспорт П5 — настоящий CSV-файл (UTF-8 BOM, ';' — Excel ru-RU) через
// path_provider; без share_plus: путь в SnackBar + копия в буфер обмена.
// Портировано из lada_vesta_scanner; цвета — только токены AppColors.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../../providers/obd_provider.dart';
import '../../providers/obd_state.dart';
import 'journal_csv.dart';

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
    final csv = JournalCsv.build(st.nuances);
    try {
      Directory? dir;
      try {
        dir = await getExternalStorageDirectory(); // Android: видимая папка
      } catch (_) {
        // Не Android — берём документы приложения.
      }
      dir ??= await getApplicationDocumentsDirectory();
      final stamp = _stamp(DateTime.now());
      final file = File('${dir.path}/vestascan_journal_$stamp.csv');
      await file.writeAsBytes(JournalCsv.bytes(csv), flush: true);
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV сохранён: ${file.path}\n'
            'Копия CSV — в буфере обмена.'),
        duration: const Duration(seconds: 8),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить CSV: $e')));
    }
  }

  static String _stamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}_'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}'
      '${t.second.toString().padLeft(2, '0')}';

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

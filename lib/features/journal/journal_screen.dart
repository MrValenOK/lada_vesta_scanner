import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../core/theme.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  bool _isExporting = false;

  Future<void> _exportCsv() async {
    final obdNotifier = ref.read(obdProvider.notifier);
    setState(() => _isExporting = true);
    
    final result = await obdNotifier.exportJournalToCsv();
    
    if (!mounted) return;
    setState(() => _isExporting = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: result.startsWith('✅') ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _clearJournal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Очистить журнал?', style: TextStyle(color: Colors.white)),
        content: const Text('Все события будут удалены из памяти. Это действие нельзя отменить.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      ref.read(obdProvider.notifier).clearJournal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(obdProvider);
    final nuances = state.nuances;

    return Scaffold(
      appBar: AppBar(
        title: Text('Журнал событий (${nuances.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: _isExporting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.darkAccent))
                : const Icon(Icons.save_alt_rounded, color: AppColors.darkAccent),
            tooltip: 'Экспорт в CSV',
            onPressed: _isExporting ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            tooltip: 'Очистить журнал',
            onPressed: _clearJournal,
          ),
        ],
      ),
      body: nuances.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Журнал чист.\nАномалии будут автоматически регистрироваться здесь с счетчиком HZ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: nuances.length,
              itemBuilder: (ctx, i) {
                final e = nuances[i];
                final color = e.severity == NuanceSeverity.critical 
                    ? AppColors.error
                    : (e.severity == NuanceSeverity.warning 
                        ? AppColors.warning 
                        : AppColors.darkAccent);
                
                return Card(
                  color: AppColors.darkSurface,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.title,
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            if (e.hzCount > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(6)),
                                child: Text('HZ: ${e.hzCount}', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(e.description, style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4)),
                        if (e.snapshot.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: e.snapshot.entries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.darkSurface2, borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  '${entry.key}: ${entry.value}',
                                  style: const TextStyle(color: AppColors.darkText2, fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(e.timeStr, style: const TextStyle(color: AppColors.darkText3, fontSize: 10, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
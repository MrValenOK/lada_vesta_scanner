import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../services/ai_prompt_builder.dart';
import '../../services/trip_calculator.dart';

class JournalScreen extends ConsumerWidget {
  final TripCalculator tripCalculator;

  const JournalScreen({super.key, required this.tripCalculator});

  void _generateAndCopyPrompt(BuildContext context, WidgetRef ref) {
    final state = ref.read(obdProvider);
    
    final prompt = AiPromptBuilder.generateSnapshot(
      liveData: state.liveData,
      tripDistance: tripCalculator.totalDistanceKm,
      fuelConsumed: tripCalculator.totalFuelLiters,
    );

    // Копируем в буфер обмена
    Clipboard.setData(ClipboardData(text: prompt));

    // Показываем красивое уведомление
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Умный снапшот скопирован в буфер!'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал сессий', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Карточка создания снапшота
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withAlpha(178), // ~0.7 opacity
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'AI Анализ',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Сгенерируйте подробный текстовый отчет о текущем состоянии двигателя, чтобы отправить его нейросети для поиска неисправностей.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _generateAndCopyPrompt(context, ref),
                      icon: const Icon(Icons.copy),
                      label: const Text('Скопировать Снапшот', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('ИСТОРИЯ (ДЕМО)', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _buildHistoryCard(context, 'Утро, Холодный пуск', '12 Окт 2026', 'Ошибок нет'),
                  _buildHistoryCard(context, 'Трасса М4, под нагрузкой', '10 Окт 2026', 'Высокий LTFT (+12%)', isWarning: true),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, String title, String date, String status, {bool isWarning = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isWarning ? Theme.of(context).colorScheme.error.withAlpha(25) : Theme.of(context).colorScheme.primary.withAlpha(25), // ~0.1 opacity
            shape: BoxShape.circle,
          ),
          child: Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: isWarning ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(date),
        trailing: Text(
          status,
          style: TextStyle(
            color: isWarning ? Theme.of(context).colorScheme.error : Theme.of(context).textTheme.bodyMedium?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';

class TestsScreen extends ConsumerWidget {
  const TestsScreen({super.key});

  void _runTest(BuildContext context, WidgetRef ref, String testName, String command) async {
    // ignore: unused_local_variable
    final obdNotifier = ref.read(obdProvider.notifier);
    final state = ref.read(obdProvider);

    if (!state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Сначала подключитесь к автомобилю на главном экране!'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Показываем диалог загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text('Выполняется: $testName...')),
          ],
        ),
      ),
    );

    // В реальном приложении здесь будет отправка UDS Routine Control (например, 31 01 xx xx)
    // Имитируем задержку теста
    await Future.delayed(const Duration(seconds: 2));
    
    // Закрываем диалог
    if (context.mounted) Navigator.of(context).pop();

    // Показываем результат
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Тест "$testName" успешно завершен!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активные тесты', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ИСПОЛНИТЕЛЬНЫЕ МЕХАНИЗМЫ', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _buildTestCard(
                    context,
                    ref,
                    title: 'Вентилятор охлаждения (Скорость 1)',
                    subtitle: 'Принудительный запуск реле малой скорости',
                    icon: Icons.mode_fan_off,
                    command: '31010201', // Пример UDS команды RoutineControl
                  ),
                  _buildTestCard(
                    context,
                    ref,
                    title: 'Тест топливной форсунки Цил. 1',
                    subtitle: 'Отключение форсунки для проверки падения оборотов',
                    icon: Icons.water_drop,
                    command: '31010301',
                  ),
                  _buildTestCard(
                    context,
                    ref,
                    title: 'Сброс адаптаций дросселя',
                    subtitle: 'Очистка памяти обучения электронной заслонки',
                    icon: Icons.settings_backup_restore,
                    command: '31010400',
                    isDanger: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard(BuildContext context, WidgetRef ref, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String command,
    bool isDanger = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: () => _runTest(context, ref, title, command),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDanger ? Theme.of(context).colorScheme.error.withAlpha(25) : Theme.of(context).colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isDanger ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.primary, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
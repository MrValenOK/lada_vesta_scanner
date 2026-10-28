import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../core/theme.dart';

class TestsScreen extends ConsumerStatefulWidget {
  const TestsScreen({super.key});

  @override
  ConsumerState<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends ConsumerState<TestsScreen> {
  bool _isTestRunning = false;
  String _adaptStatus = 'Готов к адаптации';

  Future<void> _runAdaptation() async {
    final obdNotifier = ref.read(obdProvider.notifier);
    if (!ref.read(obdProvider).isConnected) return;

    setState(() {
      _isTestRunning = true;
      _adaptStatus = 'Запуск...';
    });

    final result = await obdNotifier.runThrottleAdaptation((msg) {
      if (mounted) setState(() => _adaptStatus = msg);
    });

    if (mounted) {
      setState(() {
        _isTestRunning = false;
        _adaptStatus = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Активные тесты', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTestCard(
            title: 'Адаптация нуля ДЗ',
            subtitle: '30 секунд покоя + 10 сек главное реле',
            icon: Icons.timer_outlined,
            onTap: _isTestRunning ? () {} : _runAdaptation,
            isDanger: true,
          ),
          if (_adaptStatus != 'Готов к адаптации')
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_adaptStatus, style: const TextStyle(color: AppColors.darkAccent, fontWeight: FontWeight.bold)),
            ),
          const Divider(color: AppColors.darkBorder),
          _buildTestCard(
            title: 'Вентилятор 1 (Малая)',
            subtitle: 'Конт. X1.1/H2 (6 сек)',
            icon: Icons.wind_power_rounded,
            onTap: () => _runTest('Вентилятор 1', '2F02010301', '2F020100', 6),
          ),
          _buildTestCard(
            title: 'Вентилятор 2 (Макс.)',
            subtitle: 'Конт. X1.1/H3 (6 сек)',
            icon: Icons.cyclone_rounded,
            onTap: () => _runTest('Вентилятор 2', '2F02020301', '2F020200', 6),
            isDanger: true,
          ),
          _buildTestCard(
            title: 'Реле бензонасоса',
            subtitle: 'Конт. X1.1/J4 (10 сек)',
            icon: Icons.local_gas_station_rounded,
            onTap: () => _runTest('Реле ЭБН', '2F02030301', '2F020300', 10, requireEngineStopped: true),
            isDanger: true,
          ),
        ],
      ),
    );
  }

  Future<void> _runTest(String title, String cmdOn, String cmdOff, int holdSec, {bool requireEngineStopped = false}) async {
    final obdNotifier = ref.read(obdProvider.notifier);
    setState(() => _isTestRunning = true);
    try {
      await obdNotifier.runActuatorTest(
        testName: title,
        cmdOn: cmdOn,
        cmdOff: cmdOff,
        holdSeconds: holdSec,
        requireEngineStopped: requireEngineStopped,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _isTestRunning = false);
    }
  }

  Widget _buildTestCard({required String title, required String subtitle, required IconData icon, required VoidCallback onTap, bool isDanger = false}) {
    return Card(
      color: AppColors.darkSurface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDanger ? AppColors.error.withAlpha(100) : AppColors.darkBorder)),
      child: ListTile(
        onTap: _isTestRunning ? null : onTap,
        leading: Icon(icon, color: isDanger ? AppColors.error : AppColors.darkAccent),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.play_circle_fill, color: AppColors.darkAccent),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../core/theme.dart';

class TestsScreen extends ConsumerStatefulWidget {
  const TestsScreen({super.key});

  @override
  ConsumerState<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends ConsumerState<TestsScreen> {
  bool _isRunningSniffer = false;
  String _snifferDump = 'Нажмите кнопку ниже, чтобы опросить ЭБУ.';

  Future<void> _runSniffer() async {
    final notifier = ref.read(obdProvider.notifier);
    if (!ref.read(obdProvider).isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет связи!')));
      return;
    }

    setState(() {
      _isRunningSniffer = true;
      _snifferDump = 'Опрос...';
    });

    // ВАЖНО: Ставим поллинг на паузу
    await notifier.pauseForSniffer();

    try {
      final sb = StringBuffer();
      sb.writeln('=== ДАМП ОТВЕТОВ ЭБУ М86 ===');
      
      final cmds = ['0904', '0100', '010B', '0104', '012E', '222001', '222002', '222003'];
      
      for (final cmd in cmds) {
        // Отправляем напрямую через сервис
        final r = await notifier.sendCommandForSniffer(cmd);
        sb.writeln('$cmd => ${r.replaceAll('\n', ' | ')}');
      }

      final dumpStr = sb.toString().trim();
      await Clipboard.setData(ClipboardData(text: dumpStr));
      
      if (mounted) {
        setState(() {
          _snifferDump = '$dumpStr\n\n✅ Скопировано в буфер!';
        });
      }
    } finally {
      setState(() => _isRunningSniffer = false);
      // ВАЖНО: Возобновляем поллинг
      notifier.resumeAfterSniffer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Анализ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isRunningSniffer ? null : _runSniffer,
              icon: const Icon(Icons.radar),
              label: Text(_isRunningSniffer ? 'Идет опрос...' : 'Снять HEX-дамп'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.darkBorder)
                ),
                child: SingleChildScrollView(
                  child: Text(_snifferDump, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: Colors.white70)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

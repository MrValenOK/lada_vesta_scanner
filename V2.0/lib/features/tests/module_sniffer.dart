// lib/features/tests/module_sniffer.dart — сниффер блоков ABS и Приборки.
//
// Порт из lada_vesta_scanner@c44b3d8 (кнопка «Сканировать блоки ABS и Приборки»
// + ObdNotifier.runModuleSniffer; в 8e2b216 кнопка переработана — адреса те же).
//
// Адаптация под V2.0: транспорт защищённого bluetooth_service не имеет
// switchModule, поэтому переключение адресов выполняется через
// sendCommandForSniffer теми же AT-командами, что и в источнике:
//   ATSH<tx> → ATCRA<rx> → ATFCSH<tx> → 1003 (extended session блока).
// После сканирования — возврат на двигатель (ATSH7E0/ATCRA7E8/ATFCSH7E0) и
// выход в default session (1001), иначе основной опрос Mode 01 даст 7F 01 7F.
// Опрос на время прогона ставится на паузу (pauseForSniffer/resumeAfterSniffer).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/obd_provider.dart';
import '../../services/bluetooth_service.dart';

typedef SnifferSend = Future<String> Function(String cmd,
    {int timeoutMs, int postDelayMs});

/// Логика опроса одного блока: переключение адресов, перебор DID, возврат.
class ModuleSniffer {
  ModuleSniffer({required this.send, required this.log});

  final SnifferSend send;
  final void Function(String line) log;

  /// Блоки и адреса (из c44b3d8): (имя, TX, RX).
  static const List<(String, String, String)> modules = [
    ('ABS', '740', '748'),
    ('Приборка', '743', '74B'),
  ];

  /// Популярные DID, где может лежать пробег/топливо/VIN (из источника).
  static const List<String> testDids = [
    '22F190',
    '22F187',
    '22F18C',
    '22DD01',
    '22DD02',
    '222001',
    '222002',
    '222003',
    '220401',
    '220402',
  ];

  /// Прогон по обоим блокам (ABS → Приборка). Возвращает сводку для буфера.
  Future<String> runAll() async {
    final sb = StringBuffer();
    for (final (name, tx, rx) in modules) {
      sb.writeln(await run(name, tx, rx));
    }
    return sb.toString().trim();
  }

  Future<String> run(String name, String txId, String rxId) async {
    final sb = StringBuffer();
    final head = '=== СНИФФЕР БЛОКА: $name (TX: $txId, RX: $rxId) ===';
    sb.writeln(head);
    log(head);

    await _switchTo(txId, rxId);

    for (final did in testDids) {
      final resp = await send(did, timeoutMs: 1000, postDelayMs: 100);
      final clean = resp.replaceAll('\n', ' | ').trim();
      // Честный ✅ — только реальные данные: NO DATA/ERROR/? и отказ 7F это ❌.
      final upper = resp.toUpperCase();
      final isFailure = upper.contains('7F') ||
          upper.contains('NO DATA') ||
          upper.contains('ERROR') ||
          upper.contains('UNABLE') ||
          upper.trim() == '?';
      final line = (!isFailure && clean.isNotEmpty)
          ? '✅ $did => $clean'
          : '❌ $did => Отказ/Нет данных';
      sb.writeln(line);
      log(line);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    await _restoreEngine();
    return sb.toString();
  }

  Future<void> _switchTo(String txId, String rxId) async {
    await send('ATSH$txId', timeoutMs: 800, postDelayMs: 60);
    await send('ATCRA$rxId', timeoutMs: 800, postDelayMs: 60);
    await send('ATFCSH$txId', timeoutMs: 800, postDelayMs: 60);
    await send('1003', timeoutMs: 1200, postDelayMs: 120);
  }

  Future<void> _restoreEngine() async {
    await send('ATSH7E0', timeoutMs: 800, postDelayMs: 60);
    await send('ATCRA7E8', timeoutMs: 800, postDelayMs: 60);
    await send('ATFCSH7E0', timeoutMs: 800, postDelayMs: 60);
    await send('1001', timeoutMs: 1200, postDelayMs: 120);
  }
}

/// Кнопка «Сканировать блоки ABS и Приборки»: пауза опроса → прогон →
/// буфер обмена → возобновление опроса. Логика — в [ModuleSniffer].
class ModuleSnifferButton extends ConsumerWidget {
  const ModuleSnifferButton({
    super.key,
    required this.busy,
    required this.onBusy,
    required this.log,
  });

  final bool busy;
  final void Function(bool) onBusy;
  final void Function(String) log;

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (busy || !BluetoothService.instance.isConnected) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Сначала подключитесь к адаптеру')));
      return;
    }
    onBusy(true);
    final provider = ref.read(obdProvider.notifier);
    final wasPolling = await provider.pauseForSniffer();
    log('=== СНИФФЕР ABS/ПРИБОРКА (ЭКСПЕРИМЕНТАЛЬНО) ${DateTime.now().toIso8601String()} ===');
    try {
      final dump = await ModuleSniffer(
        send: provider.sendCommandForSniffer,
        log: log,
      ).runAll();
      await Clipboard.setData(ClipboardData(text: dump));
      messenger.showSnackBar(const SnackBar(
          content: Text('Результат сниффера блоков скопирован в буфер')));
    } finally {
      provider.resumeAfterSniffer(wasPolling);
      onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : () => _run(context, ref),
          icon: const Icon(Icons.radar),
          label: const Text('Сканировать блоки ABS и Приборки'),
        ),
        const SizedBox(height: S.s1),
        Text(
          'Экспериментально: адреса блоков не подтверждены — ответ NO DATA ожидаем',
          style: TextStyle(color: c.text3, fontSize: T.cap),
        ),
      ],
    );
  }
}

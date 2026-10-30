// lib/features/tests/tests_screen.dart — инженерный UDS/KWP HEX-сниффер.
// V2.0: команды идут через obdProvider (на время AUTO-DUMP опрос ставится
// на паузу и возобновляется), кнопки/чипы/буфер — по финальной спеке заказчика.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/obd_provider.dart';
import '../../services/bluetooth_service.dart';
import 'auto_dump_runner.dart';
import 'module_sniffer.dart';
import 'monitor_220001.dart';
import 'sniffer_console.dart';

class TestsScreen extends ConsumerStatefulWidget {
  const TestsScreen({super.key});

  @override
  ConsumerState<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends ConsumerState<TestsScreen> {
  final BluetoothService _bt = BluetoothService.instance;
  final TextEditingController _cmd = TextEditingController(text: '222001');
  final List<String> _log = [];
  final ScrollController _scroll = ScrollController();

  List<Map<String, String>> _devices = const [];
  String? _selectedAddress;
  bool _busy = false;

  /// Мониторинг 220001 (реверс структуры блока): null = выключен.
  Monitor220001? _monitor;
  bool _monitorWasPolling = false;
  bool get _monitorOn => _monitor != null;

  static const List<String> _quick = [
    '222001',
    '220401',
    '010C',
    '010D',
    '1003',
    '3E00',
    '22F190',
    '22F187',
    '22F188',
  ];

  /// Multi-frame (ответ длиннее 7 байт payload): тайминг 2000/250 —
  /// дефолт 1200/120 может обрезать склейку ISO-TP на медленных клонах.
  static const Set<String> _multiFrame = {
    '0904',
    '220001',
    '22F190',
    '22F187',
    '22F188',
    '22F191',
    '22F195',
    '222001',
    '222002',
    '222003',
    '220401',
    '220402',
    '220403',
  };

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  @override
  void dispose() {
    // dispose() сервиса НЕ вызываем: синглтон живёт всё приложение.
    _monitor?.stop();
    _cmd.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPairedDevices() async {
    final list = await _bt.getPairedDevices();
    if (!mounted) return;
    setState(() {
      _devices = list;
      _selectedAddress = _autoSelectAddress(list);
    });
  }

  /// Боевой автовыбор: имя содержит OBD/ELM; иначе — первое устройство.
  String? _autoSelectAddress(List<Map<String, String>> list) {
    if (list.isEmpty) return null;
    for (final d in list) {
      final name = (d['name'] ?? '').toUpperCase();
      if (name.contains('OBD') || name.contains('ELM')) return d['address'];
    }
    return list.first['address'];
  }

  bool get _allNamesUnknown =>
      _devices.isNotEmpty &&
      _devices.every((d) => (d['name'] ?? 'Unknown') == 'Unknown');

  Future<void> _openBtSettings() async {
    try {
      final ok = await launchUrl(Uri.parse('android-settings://bluetooth'));
      if (!ok) _toast('Откройте настройки Bluetooth вручную');
    } catch (_) {
      _toast('Откройте настройки Bluetooth вручную');
    }
  }

  Future<void> _connect() async {
    final addr = _selectedAddress;
    if (addr == null) return;
    setState(() => _busy = true);
    final ok = await ref.read(obdProvider.notifier).connect(addr);
    final st = ref.read(obdProvider);
    _append(ok
        ? '[BT] Подключено: $addr · ${st.initOk ? 'init OK' : '⚠️ init частичный'}'
            '${st.ecuId != '---' ? ' · ${st.ecuId}' : ''}'
        : '[BT] Ошибка подключения: $addr — ${_bt.lastError ?? st.statusText}');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    await ref.read(obdProvider.notifier).disconnect();
    _append('[BT] Отключено');
  }

  Future<void> _send([String? cmd]) async {
    final c = (cmd ?? _cmd.text).trim().toUpperCase();
    if (c.isEmpty) return;
    setState(() => _busy = true);
    final multi = _multiFrame.contains(c);
    final resp = await ref.read(obdProvider.notifier).sendCommandForSniffer(
          c,
          timeoutMs: multi ? 2000 : 1200,
          postDelayMs: multi ? 250 : 120,
        );
    _append('→ $c\n← $resp');
    if (mounted) setState(() => _busy = false);
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      while (_log.length > AppConsts.snifferBufferMaxLines) {
        _log.removeAt(0);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copyDump() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    _toast('Дамп скопирован в буфер обмена');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// АВТО-ДАМП М86: цепочка и NRC-расшифровка — в auto_dump_runner.dart.
  /// На время прогона опрос на паузе, итог — в буфер обмена.
  Future<void> _runAutoDump() async {
    if (_busy || !_bt.isConnected) {
      _toast('Сначала подключитесь к адаптеру');
      return;
    }
    setState(() => _busy = true);
    final provider = ref.read(obdProvider.notifier);
    final wasPolling = await provider.pauseForSniffer();
    _append('=== AUTO-DUMP M86 ${DateTime.now().toIso8601String()} ===');
    try {
      await AutoDumpRunner(send: provider.sendCommandForSniffer, log: _append)
          .run();
      await _copyDump();
    } finally {
      provider.resumeAfterSniffer(wasPolling);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// МОНИТОРИНГ 220001 (1 Гц, default session — без 1003): HEX байт-за-байтом,
  /// изменившиеся байты помечаются Δ. Для реверса структуры блока.
  Future<void> _toggleMonitor() async {
    if (_monitor != null) {
      _stopMonitor();
      return;
    }
    if (!_bt.isConnected) {
      _toast('Сначала подключитесь к адаптеру');
      return;
    }
    final provider = ref.read(obdProvider.notifier);
    _monitorWasPolling = await provider.pauseForSniffer();
    _monitor = Monitor220001(
      send: provider.sendCommandForSniffer,
      log: _append,
      isConnected: () => _bt.isConnected,
      did: provider.blockDid,
      validators: provider.blockValidators,
    );
    _append('=== МОНИТОРИНГ 220001 (1 Гц, default session) ===');
    setState(() {});
    _monitor!.start();
  }

  void _stopMonitor() {
    _monitor?.stop();
    _monitor = null;
    if (mounted) setState(() {});
    _append('=== МОНИТОРИНГ остановлен ===');
    ref.read(obdProvider.notifier).resumeAfterSniffer(_monitorWasPolling);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final ecuId = ref.watch(obdProvider).ecuId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Анализ · HEX-сниффер'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _runAutoDump,
            icon: const Icon(Icons.science_rounded),
            tooltip: 'АВТО-ДАМП М86 (в буфер)',
          ),
          IconButton(
            onPressed: _busy ? null : _toggleMonitor,
            icon: Icon(
              _monitorOn
                  ? Icons.stop_circle_outlined
                  : Icons.monitor_heart_outlined,
              color: _monitorOn ? c.error : null,
            ),
            tooltip: _monitorOn
                ? 'Остановить мониторинг 220001'
                : 'МОНИТОРИНГ 220001 (1 Гц)',
          ),
          IconButton(
            onPressed: _busy ? null : _loadPairedDevices,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить список устройств',
          ),
          IconButton(
            onPressed: _log.isEmpty ? null : _copyDump,
            icon: const Icon(Icons.copy_all),
            tooltip: 'Копировать дамп',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(S.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder(
              valueListenable: _bt.stateNotifier,
              builder: (context, state, _) => Row(
                children: [
                  Text('BT: ${state.name}',
                      style: AppTheme.mono(size: T.sm, color: c.text2)),
                  const SizedBox(width: S.s3),
                  if (ecuId != '---')
                    Text('М86 · $ecuId',
                        style: AppTheme.mono(size: T.sm, color: c.text1)),
                ],
              ),
            ),
            const SizedBox(height: S.s2),
            if (_devices.isEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text('Сопряжённых устройств нет',
                        style: AppTheme.mono(size: T.sm, color: c.warning)),
                  ),
                  OutlinedButton(
                      onPressed: _openBtSettings,
                      child: const Text('Настройки BT')),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      value:
                          _devices.any((d) => d['address'] == _selectedAddress)
                              ? _selectedAddress
                              : null,
                      isExpanded: true,
                      itemHeight: null,
                      hint: Text('Устройство',
                          style: AppTheme.mono(size: T.sm, color: c.text3)),
                      items: [
                        for (final d in _devices)
                          DropdownMenuItem<String>(
                            value: d['address'],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(d['name'] ?? 'Unknown',
                                    style: AppTheme.mono(
                                        size: T.sm, color: c.text1)),
                                if (_allNamesUnknown ||
                                    (d['name'] ?? 'Unknown') == 'Unknown')
                                  Text(d['address'] ?? '',
                                      style: AppTheme.mono(
                                          size: T.cap, color: c.text3)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _selectedAddress = v),
                    ),
                  ),
                  const SizedBox(width: S.s2),
                  FilledButton(
                      onPressed: _busy ? null : _connect,
                      child: const Text('Connect')),
                  const SizedBox(width: S.s2),
                  OutlinedButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text('Disc')),
                ],
              ),
            const SizedBox(height: S.s2),
            ModuleSnifferButton(
                busy: _busy,
                onBusy: (v) => setState(() => _busy = v),
                log: _append),
            const SizedBox(height: S.s2),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmd,
                    decoration: const InputDecoration(
                      labelText: 'Команда (HEX, без пробелов)',
                      isDense: true,
                    ),
                    style: AppTheme.mono(size: T.sm),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: S.s2),
                FilledButton(
                    onPressed: _busy ? null : _send, child: const Text('Send')),
              ],
            ),
            const SizedBox(height: S.s2),
            Wrap(
              spacing: S.s2,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q, style: AppTheme.mono(size: T.cap)),
                    onPressed: _busy ? null : () => _send(q),
                  ),
              ],
            ),
            const SizedBox(height: S.s3),
            Expanded(child: SnifferConsole(lines: _log, scroll: _scroll)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../core/theme.dart';

class DtcScreen extends ConsumerStatefulWidget {
  const DtcScreen({super.key});

  @override
  ConsumerState<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends ConsumerState<DtcScreen> {
  bool _isLoading = false;
  bool _hasScanned = false;
  List<String> _dtcs = []; // Теперь храним просто строки кодов
  Map<String, double?> _freezeFrameData = {};

  void _scanDtc() async {
    final obdNotifier = ref.read(obdProvider.notifier);
    if (!ref.read(obdProvider).isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала подключитесь к автомобилю!'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Вызываем реальный опрос ЭБУ
    final codes = await obdNotifier.readDtcs();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasScanned = true;
        _dtcs = codes;
      });
    }
  }

  void _clearDtc() async {
    final obdNotifier = ref.read(obdProvider.notifier);
    setState(() => _isLoading = true);
    
    // Отправляем команду стирания (04 для OBD2, 14FFFFFF для UDS)
    await obdNotifier.clearDtcs();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _dtcs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Коды ошибок успешно стерты!'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Коды неисправностей', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkSurface,
                      foregroundColor: AppColors.darkAccent,
                      side: const BorderSide(color: AppColors.darkAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isLoading ? null : _scanDtc,
                    icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                    label: const Text('ПРОЧИТАТЬ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error.withAlpha(25),
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (_isLoading || _dtcs.isEmpty) ? null : _clearDtc,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('СБРОСИТЬ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: !_hasScanned 
                  ? const Center(child: Text('Нажмите "Прочитать", чтобы опросить ЭБУ', style: TextStyle(color: Colors.grey)))
                  : _dtcs.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, color: AppColors.success, size: 64),
                              SizedBox(height: 16),
                              Text('Ошибок не обнаружено', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _dtcs.length,
                          itemBuilder: (context, index) {
                            final code = _dtcs[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: AppColors.darkSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: AppColors.error),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showFreezeFrame(code),
                                child: ListTile(
                                  leading: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                                  title: Text(code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.error)),
                                  subtitle: const Text('Нажмите для просмотра стоп-кадра', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFreezeFrame(String code) async {
    final obdNotifier = ref.read(obdProvider.notifier);
    
    // Показываем шторку с загрузкой
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Запускаем чтение один раз
            if (!_isLoading && _dtcs.isNotEmpty) {
              Future.microtask(() async {
                final data = await obdNotifier.getFreezeFrame(code);
                if (mounted) {
                  setSheetState(() {
                    _freezeFrameData = data;
                  });
                }
              });
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                        child: Text(code, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Стоп-кадр', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                      if (_freezeFrameData.isEmpty) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_freezeFrameData.isEmpty)
                    const Text('Запрос данных у ЭБУ...', style: TextStyle(color: Colors.grey))
                  else
                    ..._freezeFrameData.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          Text(e.value?.toStringAsFixed(2) ?? '---', style: const TextStyle(color: AppColors.darkAccent, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace')),
                        ],
                      ),
                    )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkSurface2),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Закрыть', style: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

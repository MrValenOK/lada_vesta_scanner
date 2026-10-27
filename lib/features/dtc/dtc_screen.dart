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
  List<Map<String, String>> _dtcs = []; // Список найденных ошибок

  void _scanDtc() async {
    final state = ref.read(obdProvider);
    if (!state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Сначала подключитесь к автомобилю!'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // В реальном приложении здесь отправляем UDS-команду 19 02 08
    // Пока имитируем задержку ответа от ЭБУ
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasScanned = true;
        // Демо-данные (позже прикрутим базу данных расшифровок)
        _dtcs = [
          {'code': 'P0134', 'desc': 'Датчик кислорода 1 (до нейтрализатора), обрыв цепи сигнала', 'status': 'Активная (Текущая)'},
          {'code': 'P0300', 'desc': 'Обнаружены случайные/множественные пропуски воспламенения', 'status': 'Сохраненная (Историческая)'},
        ];
      });
    }
  }

  void _clearDtc() async {
    setState(() => _isLoading = true);
    
    // UDS-команда сброса: 14 FF FF FF
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isLoading = false;
        _dtcs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cleaning_services, color: Colors.white),
              SizedBox(width: 12),
              Text('Коды ошибок успешно стерты из памяти ЭБУ!'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Коды неисправностей', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(color: Theme.of(context).colorScheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _scanDtc,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.search),
                    label: const Text('ПРОЧИТАТЬ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error.withAlpha(25), // ~0.1 opacity
                      foregroundColor: Theme.of(context).colorScheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  ? Center(
                      child: Text('Нажмите "Прочитать", чтобы опросить ЭБУ', 
                          style: Theme.of(context).textTheme.bodyMedium))
                  : _dtcs.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
                              SizedBox(height: 16),
                              Text('Ошибок не обнаружено', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _dtcs.length,
                          itemBuilder: (context, index) {
                            final dtc = _dtcs[index];
                            final isStored = dtc['status']!.contains('Сохраненная');
                            final statusColor = isStored ? AppColors.warning : Theme.of(context).colorScheme.error;
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: Theme.of(context).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: statusColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          dtc['code']!,
                                          style: TextStyle(
                                            fontSize: 20, 
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withAlpha(25), // ~0.1 opacity
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(dtc['status']!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(dtc['desc']!, style: Theme.of(context).textTheme.bodyLarge),
                                  ],
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
}
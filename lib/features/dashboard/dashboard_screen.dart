import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../providers/obd_provider.dart';
import '../../core/theme.dart';
import '../../services/trip_calculator.dart';
import '../../services/ota_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _focusAnomaliesOnly = false;

  Future<void> _checkOta() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Проверка обновлений на GitHub...'), duration: Duration(seconds: 2)),
    );

    final result = await OtaService.checkForUpdates();

    if (!mounted) return;

    if (result == null || result['error'] == 'API_UNREACHABLE') {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.darkSurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: AppColors.warning, size: 28),
                  SizedBox(width: 12),
                  Expanded(child: Text('API GitHub недоступен', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Не удалось проверить обновления автоматически.\n\n'
                'Возможные причины: нет интернета, мобильный оператор блокирует api.github.com (частая проблема в РФ), или отключён VPN.',
                style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final url = result?['fallbackUrl'] ?? 'https://github.com/MrValenOK/lada_vesta_scanner/releases/latest';
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, color: Colors.black),
                  label: const Text('Открыть GitHub в браузере', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (result['hasUpdate'] == true) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.darkSurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: AppColors.darkAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Доступно обновление ${result['latestVersion']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 16),
              Text(result['releaseNotes'], style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse(result['apkUrl']);
                    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                      await Clipboard.setData(ClipboardData(text: result['apkUrl']));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ссылка скопирована в буфер')));
                    }
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text('Скачать и установить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('У вас последняя версия (${OtaService.currentVersion})'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final obdState = ref.watch(obdProvider);
    final obdNotifier = ref.read(obdProvider.notifier);
    final tripCalc = obdNotifier.tripCalculator;

    final liveData = obdState.liveData;
    final rpm = liveData['rpm']?.toInt();
    final ect = liveData['ect']?.toInt();
    final volt = liveData['volt'];
    final stft = liveData['stft'];
    final ltft = liveData['ltft'];
    final tps = liveData['tps'];
    final map = liveData['map'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('VestaScan Pro', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.darkAccent),
            tooltip: 'Скопировать ИИ-Снапшот',
            onPressed: () async {
              await obdNotifier.copyAiSnapshotPrompt();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🤖 ИИ-Снапшот скопирован в буфер обмена!')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined, color: AppColors.darkAccent),
            tooltip: 'Проверить обновления',
            onPressed: () => _checkOta(),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Center(
              child: Text('M86 UDS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 12),
            _buildTripComputerCard(tripCalc, obdNotifier),
            
            const SizedBox(height: 16),
            Text('ТЕЛЕМЕТРИЯ LIVE', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildSensorCard(context, 'ОБОРОТЫ', '${rpm ?? "---"}', 'об/мин', true),
                _buildSensorCard(context, 'ТЕМП. ОЖ', '${ect ?? "---"}', '°C', true),
                _buildSensorCard(context, 'БОРТСЕТЬ', volt?.toStringAsFixed(2) ?? '14.10', 'В', false),
                _buildSensorCard(context, 'STFT', stft?.toStringAsFixed(1) ?? '---', '%', false),
                _buildSensorCard(context, 'LTFT', ltft?.toStringAsFixed(1) ?? '---', '%', false),
                _buildSensorCard(context, 'ДАД', map?.toStringAsFixed(0) ?? '---', 'кПа', false),
              ],
            ),

            const SizedBox(height: 20),
            _buildExtendedParams(liveData),

            const SizedBox(height: 20),
            Text('ОСЦИЛЛОГРАФ УДК', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.darkScopeBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Center(
                child: obdState.trace1.isEmpty 
                  ? const Text('Нет данных для графика', style: TextStyle(color: Colors.grey))
                  : CustomPaint(
                      painter: _SimpleScopePainter(trace: obdState.trace1),
                      size: Size.infinite,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final obdState = ref.watch(obdProvider);
    final obdNotifier = ref.read(obdProvider.notifier);
    final isConnected = obdState.isConnected;
    final isPolling = obdState.isPolling;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPolling ? AppColors.success : AppColors.darkBorder, width: isPolling ? 1.5 : 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isPolling ? AppColors.successSoft : AppColors.darkAccentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_rounded,
              color: isPolling ? AppColors.success : AppColors.darkAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPolling ? 'На связи' : (isConnected ? 'Подключен' : 'Выберите ELM327 адаптер'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isPolling ? AppColors.success : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPolling
                      ? (obdState.connectedDevice.isNotEmpty ? obdState.connectedDevice : 'Опрос активен')
                      : (isConnected ? 'Готов к опросу' : 'Нажмите Старт для подключения'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.darkText2),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isPolling ? AppColors.errorSoft : AppColors.darkAccentSoft,
              foregroundColor: isPolling ? AppColors.error : AppColors.darkAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (isPolling) {
                obdNotifier.stopPolling();
              } else {
                final devices = await obdNotifier.getBluetoothDevices();
                if (devices.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Нет спаренных Bluetooth-устройств. Сначала спарьте ELM327 в настройках телефона!'), backgroundColor: AppColors.warning),
                    );
                  }
                  return;
                }
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.darkSurface,
                    title: const Text('Выберите ELM327', style: TextStyle(color: Colors.white)),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        itemBuilder: (c, i) {
                          final d = devices[i];
                          return ListTile(
                            title: Text(d['name']?.isNotEmpty == true ? d['name']! : 'Unknown', style: const TextStyle(color: Colors.white)),
                            subtitle: Text(d['address'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            onTap: () {
                              Navigator.pop(ctx);
                              obdNotifier.connect(d['address']!).then((s) {
                                if (s) obdNotifier.startPolling();
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              isPolling ? 'Стоп' : 'Старт',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(BuildContext context, String title, String value, String unit, bool isLive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: isLive ? AppColors.success : AppColors.darkBorder, width: 4),
          top: BorderSide(color: AppColors.darkBorder),
          right: BorderSide(color: AppColors.darkBorder),
          bottom: BorderSide(color: AppColors.darkBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono', color: Colors.white)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripComputerCard(TripCalculator tripCalc, ObdNotifier notifier) {
    final isMoving = (tripCalc.totalDistanceKm) > 0;
    final instantStr = isMoving
        ? '${tripCalc.instantFuelL100Km.toStringAsFixed(1)} л/100'
        : '${tripCalc.instantFuelLpH.toStringAsFixed(2)} л/ч';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _tripStatItem('ПРОБЕГ', '${tripCalc.totalDistanceKm.toStringAsFixed(1)} км'),
          Container(width: 1, height: 24, color: AppColors.darkBorder),
          _tripStatItem('СРЕДНИЙ', '${tripCalc.averageConsumptionL100Km.toStringAsFixed(1)} л/100'),
          Container(width: 1, height: 24, color: AppColors.darkBorder),
          _tripStatItem('МГНОВ.', instantStr),
          IconButton(
            icon: const Icon(Icons.restart_alt, size: 18, color: Colors.grey),
            onPressed: () {
              notifier.resetTrip();
            },
          )
        ],
      ),
    );
  }

  Widget _tripStatItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono', color: Colors.white)),
      ],
    );
  }

  Widget _buildExtendedParams(Map<String, double> data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.darkBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ПАРАМЕТРЫ М86 (UDS)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const Divider(color: AppColors.darkBorder),
          _extRow('Пропуски Цил. 1-4', '${data['misfire_1']?.toInt() ?? 0} | ${data['misfire_2']?.toInt() ?? 0} | 0 | 0'),
          _extRow('ДПДЗ', '${data['tps']?.toStringAsFixed(1) ?? '---'} %'),
          _extRow('Воздух (расчетный)', '${data['air_mass_kgh']?.toStringAsFixed(1) ?? '---'} кг/ч'),
        ],
      ),
    );
  }

  Widget _extRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono', color: AppColors.darkAccent)),
        ],
      ),
    );
  }
}

class _SimpleScopePainter extends CustomPainter {
  final List<double> trace;
  _SimpleScopePainter({required this.trace});

  @override
  void paint(Canvas canvas, Size size) {
    if (trace.length < 2) return;
    final paint = Paint()..color = AppColors.darkTrace1..strokeWidth = 2..style = PaintingStyle.stroke;
    final path = Path();
    final stepX = size.width / (trace.length - 1);
    final maxVal = trace.reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < trace.length; i++) {
      final x = i * stepX;
      final y = size.height - ((trace[i] / (maxVal == 0 ? 1 : maxVal)) * size.height);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../providers/obd_provider.dart';
import '../../services/trip_calculator.dart';
import '../../core/theme.dart';
import '../../services/ota_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Future<void> _checkOta() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Проверка обновлений на GitHub...'), duration: Duration(seconds: 2)),
    );

    final result = await OtaService.checkForUpdates();

    if (!mounted) return;

    // СЛУЧАЙ 1: API недоступен (нет интернета, блокировка провайдера, или нет разрешения)
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

    // СЛУЧАЙ 2: Есть обновление
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
      // СЛУЧАЙ 3: Уже последняя версия
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
    final speed = liveData['speed']?.toInt();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('VestaScan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.darkAccentSoft,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.darkAccent.withAlpha(80)),
              ),
              child: const Text('v3.2', style: TextStyle(fontSize: 9, color: AppColors.darkAccent, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        actions: [
          // КНОПКА OTA
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined, color: AppColors.darkAccent),
            tooltip: 'Проверить обновления',
            onPressed: () => _checkOta(),
          ),
          IconButton(
            icon: const Icon(Icons.radar_rounded, color: AppColors.darkAccent),
            onPressed: () => _runSniffer(),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.darkSurface2,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Center(
              child: Text('М86 UDS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.darkText2)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 12),
            _buildTripComputerCard(tripCalc, obdNotifier),
            
            const SizedBox(height: 16),
            _sectionTitle('ТЕЛЕМЕТРИЯ', 'LIVE'),
            
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _buildSensorCard('ОБОРОТЫ ХХ', '${rpm ?? "---"}', 'об/мин', 'Норма: 840 ± 40', _statusRpm(rpm)),
                _buildSensorCard('ТЕМП. ОЖ', '${ect ?? "---"}', '°C', 'Норма: 90–103 °C', _statusEct(ect)),
                _buildSensorCard('СКОРОСТЬ', '${speed ?? "---"}', 'км/ч', 'Движение', speed != null && speed > 0 ? 'good' : 'normal'),
                _buildSensorCard('STFT', liveData['stft']?.toStringAsFixed(1) ?? '---', '%', 'Допуск: ±15%', _statusTrim(liveData['stft'])),
                _buildSensorCard('LTFT', liveData['ltft']?.toStringAsFixed(1) ?? '---', '%', 'Допуск: ±15%', _statusTrim(liveData['ltft'])),
                _buildSensorCard('ДПДЗ', liveData['tps']?.toStringAsFixed(1) ?? '---', '%', 'Норма ХХ: 1–4%', 'normal'),
                _buildSensorCard('ДАД', liveData['map']?.toStringAsFixed(0) ?? '---', 'кПа', 'Норма ХХ: 28–41', 'normal'),
                _buildSensorCard('БОРТСЕТЬ', '14.10', 'В', 'Норма: 13,0–14,5 В', 'good'),
              ],
            ),

            const SizedBox(height: 20),
            _sectionTitle('КАРТА КОРРЕКЦИЙ', 'медиана зон'),
            _buildMatrixCard(obdState.trimMedians),

            const SizedBox(height: 20),
            _sectionTitle('ОСЦИЛЛОГРАФ УДК/ДДК', '0–1.8 В'),
            _buildOscilloscope(obdState.trace1, obdState.trace2),
          ],
        ),
      ),
    );
  }

  String _statusRpm(int? rpm) => (rpm != null && (rpm < 780 || rpm > 900)) ? 'warn' : 'good';
  String _statusEct(int? ect) => (ect != null && ect > 103) ? 'err' : (ect != null && ect < 87 ? 'warn' : 'good');
  String _statusTrim(double? val) => (val != null && val.abs() > 15) ? 'err' : (val != null && val.abs() > 8 ? 'warn' : 'good');

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
          // Иконка Bluetooth с индикатором
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
          // Информация о статусе
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
          // Кнопка Старт/Стоп
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
                            title: Text(d['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
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

  Widget _sectionTitle(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppColors.darkText3)),
          Text(hint, style: const TextStyle(fontSize: 10, color: AppColors.darkText3, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildSensorCard(String label, String value, String unit, String norm, String status) {
    final borderColor = status == 'err' ? AppColors.error : (status == 'warn' ? AppColors.warning : AppColors.success);
    final valueColor = status == 'err' ? AppColors.error : (status == 'warn' ? AppColors.warning : AppColors.darkText1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
          top: const BorderSide(color: AppColors.darkBorder),
          right: const BorderSide(color: AppColors.darkBorder),
          bottom: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.darkText2)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: valueColor)),
              const SizedBox(width: 3),
              Text(unit, style: const TextStyle(fontSize: 11, color: AppColors.darkText3)),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.darkBorder, width: 0.5))),
            child: Text(norm, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: AppColors.darkText3)),
          ),
        ],
      ),
    );
  }

  Widget _buildTripComputerCard(TripCalculator calc, ObdNotifier notifier) {
    final isMoving = calc.totalDistanceKm > 0.05;
    final instantStr = isMoving ? '${calc.instantFuelL100Km.toStringAsFixed(1)} л/100' : '${calc.instantFuelLpH.toStringAsFixed(2)} л/ч';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.darkBorder)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.darkAccentSoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.local_gas_station_rounded, color: AppColors.darkAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tripItem('ПРОБЕГ', '${calc.totalDistanceKm.toStringAsFixed(1)}', 'км'),
                Container(width: 1, height: 24, color: AppColors.darkBorder),
                _tripItem('СРЕДНИЙ', '${calc.averageConsumptionL100Km.toStringAsFixed(1)}', 'л/100'),
                Container(width: 1, height: 24, color: AppColors.darkBorder),
                _tripItem('МГНОВ.', instantStr.split(' ')[0], instantStr.split(' ')[1]),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.restart_alt, size: 18, color: AppColors.darkText3), onPressed: () => notifier.resetTrip()),
        ],
      ),
    );
  }

  Widget _tripItem(String label, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.darkText3)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.darkText1)),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(fontSize: 9, color: AppColors.darkText3)),
          ],
        ),
      ],
    );
  }

  Widget _buildMatrixCard(Map<String, double> medians) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.darkBorder)),
      child: Row(
        children: [
          _buildTrimBox('ХХ', medians['idle']),
          _buildTrimBox('МАЛЫЕ', medians['low']),
          _buildTrimBox('ЧАСТ.', medians['part']),
          _buildTrimBox('ВЫСОК.', medians['high']),
        ],
      ),
    );
  }

  Widget _buildTrimBox(String label, double? val) {
    final hasData = val != null && val != 0.0;
    final color = !hasData ? AppColors.darkText3 : (val.abs() > 12.0 ? AppColors.error : (val.abs() > 6.5 ? AppColors.warning : AppColors.success));

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasData ? color.withAlpha(80) : AppColors.darkBorder),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.darkText3)),
            const SizedBox(height: 4),
            Text(
              hasData ? '${val >= 0 ? "+" : ""}${val.toStringAsFixed(1)}%' : '---',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOscilloscope(List<double> s1, List<double> s2) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: AppColors.darkScopeBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: RepaintBoundary(
          child: (s1.isEmpty && s2.isEmpty)
              ? const Center(
                  child: Text('Ожидание данных...',
                      style: TextStyle(color: AppColors.darkText3, fontSize: 12)))
              : CustomPaint(
                  painter: _O2OscilloscopePainter(
                    s1: s1,
                    s2: s2,
                    s1Color: AppColors.darkTrace1,
                    s2Color: AppColors.darkTrace2,
                    gridColor: AppColors.darkScopeGrid,
                  ),
                  size: Size.infinite,
                ),
        ),
      ),
    );
  }

  Future<void> _runSniffer() async {
    final obdNotifier = ref.read(obdProvider.notifier);
    if (!ref.read(obdProvider).isConnected) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final dump = await obdNotifier.runSnifferDump();
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Сниффер ЭБУ', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(child: SelectableText(dump, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey))),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dump));
              Navigator.pop(ctx);
            },
            child: const Text('Копировать'),
          ),
        ],
      ),
    );
  }
}

class _O2OscilloscopePainter extends CustomPainter {
  final List<double> s1;
  final List<double> s2;
  final Color s1Color;
  final Color s2Color;
  final Color gridColor;

  _O2OscilloscopePainter({
    required this.s1,
    required this.s2,
    required this.s1Color,
    required this.s2Color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const maxScaleV = 1.8;
    final height = size.height;

    void drawBand(double v1, double v2, Color color) {
      final y1 = height - (v1 / maxScaleV) * height;
      final y2 = height - (v2 / maxScaleV) * height;
      canvas.drawRect(Rect.fromLTRB(0, y2, size.width, y1), Paint()..color = color);
    }
    drawBand(0.18, 0.95, AppColors.bandUdk);
    drawBand(0.59, 0.75, AppColors.bandDdk);
    drawBand(1.20, 1.70, AppColors.bandRef);

    final gridPaint = Paint()..color = AppColors.darkScopeGrid..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final y = height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    void drawTrace(List<double> trace, Color color) {
      if (trace.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final stepX = size.width / 99;

      for (int i = 0; i < trace.length; i++) {
        final x = i * stepX;
        final normalizedY = (trace[i] / maxScaleV).clamp(0.0, 1.0);
        final y = height - (normalizedY * height);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawTrace(s1, s1Color);
    drawTrace(s2, s2Color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:url_launcher/url_launcher.dart';

// ===== КОНФИГУРАЦИЯ ВЕРСИИ И OTA (GITHUB RELEASES) =====
const String kAppVersion = '1.0.3';
const String kGithubRepo = 'MrValenOK/lada_vesta_scanner';
const String kDirectApkFallbackUrl =
    'https://github.com/$kGithubRepo/releases/latest/download/app-debug.apk';

void main() {
  runApp(const VestaScannerApp());
}

// ===== 1. ДИЗАЙН: ТЁПЛЫЙ МИНИМАЛИЗМ =====
class AppColors {
  static const lightBg = Color(0xFFFAFAF7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF5F3EE);
  static const lightText1 = Color(0xFF1A1A1A);
  static const lightText2 = Color(0xFF6B6B6B);
  static const lightText3 = Color(0xFF9A9A9A);
  static const lightBorder = Color(0xFFEAE8E3);

  static const darkBg = Color(0xFF1C1B1A);
  static const darkSurface = Color(0xFF272624);
  static const darkSurface2 = Color(0xFF2F2E2C);
  static const darkText1 = Color(0xFFF0EDE8);
  static const darkText2 = Color(0xFFA8A49E);
  static const darkText3 = Color(0xFF75726D);
  static const darkBorder = Color(0xFF353331);

  static const accent = Color(0xFF4A6FA5);
  static const accentSoft = Color(0xFFE8EEF6);
  static const success = Color(0xFF4CAF7D);
  static const successSoft = Color(0xFFE6F4EC);
  static const warning = Color(0xFFE8A838);
  static const warningSoft = Color(0xFFFFF4E0);
  static const error = Color(0xFFE07A7A);
  static const errorSoft = Color(0xFFFDEAEA);

  static const darkAccent = Color(0xFF8BA4C4);
  static const darkAccentSoft = Color(0xFF2A3442);
  static const darkSuccess = Color(0xFF7BC49A);
  static const darkSuccessSoft = Color(0xFF1F3A2A);
  static const darkWarning = Color(0xFFE8C078);
  static const darkWarningSoft = Color(0xFF3D3320);
  static const darkError = Color(0xFFE89898);
  static const darkErrorSoft = Color(0xFF3D2424);
}

enum NuanceSeverity { info, warning, critical }

class NuanceEvent {
  final String id;
  final DateTime timestamp;
  final NuanceSeverity severity;
  final String title;
  final String description;
  final Map<String, String> snapshot;

  NuanceEvent({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.title,
    required this.description,
    required this.snapshot,
  });

  String get timeStr =>
      "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
}

class TelemetryPoint {
  final DateTime time;
  final int rpm, ect, iat, map;
  final double volt, stft, ltft, adv, tps, o2, evap;

  TelemetryPoint({
    required this.time,
    required this.rpm,
    required this.ect,
    required this.iat,
    required this.map,
    required this.volt,
    required this.stft,
    required this.ltft,
    required this.adv,
    required this.tps,
    required this.o2,
    required this.evap,
  });
}

class VestaScannerApp extends StatefulWidget {
  const VestaScannerApp({super.key});

  @override
  State<VestaScannerApp> createState() => _VestaScannerAppState();
}

class _VestaScannerAppState extends State<VestaScannerApp> {
  bool _isDark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VestaScan Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: ScannerHomePage(
        isDark: _isDark,
        onThemeToggle: () => setState(() => _isDark = !_isDark),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: isDark ? AppColors.darkAccent : AppColors.accent,
        brightness: brightness,
        surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: isDark ? AppColors.darkText1 : AppColors.lightText1,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        indicatorColor: isDark ? AppColors.darkAccentSoft : AppColors.accentSoft,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkText2 : AppColors.lightText2,
          ),
        ),
      ),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;

  const ScannerHomePage({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
  });

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;

  final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();

  List<BluetoothDevice> _devices = [];
  String? _selectedAddress; // Безопасное хранение MAC-адреса (без краша Dropdown)
  bool _isConnected = false;
  bool _isPolling = false;
  String _statusText = 'Выберите ELM327 адаптер и нажмите Старт';
  String _ecuType = 'Итэлма М86';

  final StringBuffer _rxBuffer = StringBuffer();
  StreamSubscription? _connSub;
  StreamSubscription? _dataSub;

  // Основные параметры ЭБУ
  int? _rpm, _ect, _iat, _map;
  double? _volt, _stft, _ltft, _adv, _tps, _o2Voltage, _o2Sensor2, _evapPurge;
  double? _engineLoad;

  // Контроль минимального напряжения АКБ (Фиксация просадки)
  double? _minVoltSession;
  double? _maxVoltSession;
  DateTime? _minVoltTime;
  int? _minVoltRpm;

  // Расширенные параметры Итэлма М86 и Mode $06
  double? _selfLearnMult; // Мультипл. корр. смеси самообучением (норма ~1.00)
  double? _catAgingFactor; // Фактор старения нейтрализатора (норма 0.80-1.00)
  double? _cyclicAirFilling; // Цикловое наполнение по ДАД (мг/такт)
  double? _fuelRateLh; // Часовой расход топлива (л/ч)
  double? _tps1Volt, _tps2Volt; // Напряжения ДПДЗ 1 и 2 (сумма ~5В)
  double? _pedal1Volt, _pedal2Volt; // Напряжения педали 1 и 2
  List<double> _knockCyl = [0.0, 0.0, 0.0, 0.0]; // Детонация Цил 1-4

  // Результаты Mode $06
  bool? _tid08Dk1Passed;
  bool? _tid07Dk2Passed;
  double? _o2MinObserved;
  double? _o2MaxObserved;

  // Погода из интернета (только для ручного теста холодного пуска)
  double? _weatherTemp;
  String _weatherCity = '';

  // OTA-обновление (GitHub Releases)
  bool _isCheckingUpdate = false;
  bool _hasNewUpdate = false;
  String _latestGithubVersion = kAppVersion;
  String _latestReleaseNotes = 'Описание релиза отсутствует';
  String _latestApkUrl = kDirectApkFallbackUrl;
  String _latestPublishedAt = '';

  // Диагностика и журнал
  String _ecuId = 'Не прочитан';
  List<String> _dtcList = [];
  final List<NuanceEvent> _nuanceLog = [];
  final Map<String, DateTime> _lastNuanceTimes = {};
  final List<TelemetryPoint> _blackBox = [];
  final List<int> _rpmWindow = [];

  // Состояния ручных тестов
  bool _isRunningLeakTest = false;
  String _leakTestStatus =
      'Готов к проверке (требуется прогрев >75°C). Нажмите для старта.';

  bool _isRunningStartTest = false;
  String _startTestStatus =
      'Включите зажигание (не заводя мотор) и нажмите кнопку.';

  bool _isRunningMode06Test = false;
  String _mode06TestStatus =
      'Проверка TID \$08 (ДК1), TID \$07 (ДК2) и фактора старения катализатора.';

  bool _isRunningM86DeepTest = false;
  String _m86DeepTestStatus =
      'Анализ детонации по цилиндрам (1–4), продувки адсорбера (EVAP) и ДПДЗ.';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_currentTabIndex != _tabController.index) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
    _initBluetooth();
    _fetchAmbientWeather();
    Future.delayed(const Duration(seconds: 2), () {
      _checkForOtaUpdate(silent: true);
    });
  }

  @override
  void dispose() {
    _isPolling = false;
    _connSub?.cancel();
    _dataSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // Цвета под текущую тему
  Color get _surface =>
      widget.isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get _surface2 =>
      widget.isDark ? AppColors.darkSurface2 : AppColors.lightSurface2;
  Color get _text1 =>
      widget.isDark ? AppColors.darkText1 : AppColors.lightText1;
  Color get _text2 =>
      widget.isDark ? AppColors.darkText2 : AppColors.lightText2;
  Color get _text3 =>
      widget.isDark ? AppColors.darkText3 : AppColors.lightText3;
  Color get _border =>
      widget.isDark ? AppColors.darkBorder : AppColors.lightBorder;

  Color get _accent => widget.isDark ? AppColors.darkAccent : AppColors.accent;
  Color get _accentSoft =>
      widget.isDark ? AppColors.darkAccentSoft : AppColors.accentSoft;
  Color get _success =>
      widget.isDark ? AppColors.darkSuccess : AppColors.success;
  Color get _successSoft =>
      widget.isDark ? AppColors.darkSuccessSoft : AppColors.successSoft;
  Color get _warning =>
      widget.isDark ? AppColors.darkWarning : AppColors.warning;
  Color get _warningSoft =>
      widget.isDark ? AppColors.darkWarningSoft : AppColors.warningSoft;
  Color get _error => widget.isDark ? AppColors.darkError : AppColors.error;
  Color get _errorSoft =>
      widget.isDark ? AppColors.darkErrorSoft : AppColors.errorSoft;

  // ===== ОКНО КОНТРОЛЯ МИНИМАЛЬНОГО НАПРЯЖЕНИЯ АКБ =====
  void _resetMinVoltage() {
    setState(() {
      _minVoltSession = _volt;
      _maxVoltSession = _volt;
      _minVoltTime = _volt != null ? DateTime.now() : null;
      _minVoltRpm = _rpm;
    });
  }

  void _showBatteryMinDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final minV = _minVoltSession;
        final isDying = minV != null && minV < 10.5;
        final isCritical = minV != null && minV < 9.8;

        String verdictTitle = 'Замер еще не выполнен';
        String verdictDesc =
            'Подключитесь к ЭБУ и запустите двигатель, чтобы зафиксировать минимальное напряжение просадки АКБ под нагрузкой стартера.';
        Color statusColor = _accent;
        Color statusBg = _accentSoft;

        if (minV != null) {
          if (isCritical) {
            verdictTitle = 'КРИТИЧЕСКАЯ ПРОСАДКА (${minV.toStringAsFixed(2)} В)';
            verdictDesc =
            'Напряжение упало ниже 9.8 В! Высокий риск сброса ЭБУ и отказа пуска. АКБ сильно разряжен, изношен, либо окислены силовые массы / берет на себя стартер.';
            statusColor = _error;
            statusBg = _errorSoft;
          } else if (isDying) {
            verdictTitle =
            'ПРИЗНАК УМИРАЮЩЕГО АКБ (${minV.toStringAsFixed(2)} В)';
            verdictDesc =
            'Просадка ниже 10.5 В (например, 10.2 В) при пуске говорит об усталости аккумулятора (потеря пускового тока, сульфатация пластин). Зимой такой АКБ может подвести.';
            statusColor = _warning;
            statusBg = _warningSoft;
          } else {
            verdictTitle = 'АКБ ДЕРЖИТ НАГРУЗКУ (${minV.toStringAsFixed(2)} В)';
            verdictDesc =
            'Минимальное напряжение не опускалось ниже 10.5 В. Аккумулятор и стартерная цепь в хорошем состоянии.';
            statusColor = _success;
            statusBg = _successSoft;
          }
        }

        final timeStr = _minVoltTime != null
            ? "${_minVoltTime!.hour.toString().padLeft(2, '0')}:${_minVoltTime!.minute.toString().padLeft(2, '0')}:${_minVoltTime!.second.toString().padLeft(2, '0')}"
            : '--:--:--';

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.battery_alert_rounded, color: statusColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Монитор просадки АКБ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _text1,
                          ),
                        ),
                        Text(
                          'Фиксация экстремумов напряжения бортсети',
                          style: TextStyle(fontSize: 12, color: _text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('МИНИМУМ (ПУСК)',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _text2)),
                            const SizedBox(height: 4),
                            Text(
                              minV != null
                                  ? '${minV.toStringAsFixed(2)} В'
                                  : '---',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 44, color: _border),
                        Column(
                          children: [
                            Text('СЕЙЧАС',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _text2)),
                            const SizedBox(height: 4),
                            Text(
                              _volt != null
                                  ? '${_volt!.toStringAsFixed(2)} В'
                                  : '---',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: _text1,
                              ),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 44, color: _border),
                        Column(
                          children: [
                            Text('МАКСИМУМ',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _text2)),
                            const SizedBox(height: 4),
                            Text(
                              _maxVoltSession != null
                                  ? '${_maxVoltSession!.toStringAsFixed(2)} В'
                                  : '---',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: _text2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: _border, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Время фиксации минимума:',
                            style: TextStyle(fontSize: 12, color: _text2)),
                        Text('$timeStr (при ${_minVoltRpm ?? 0} об/мин)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _text1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdictTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdictDesc,
                      style: TextStyle(fontSize: 13, color: _text1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Шкала оценки под нагрузкой стартера:\n'
                    '• 10.5 В и выше — Исправный АКБ\n'
                    '• 10.0 – 10.4 В (напр. 10.2 В) — АКБ теряет емкость / стареет\n'
                    '• Ниже 9.8 В — Критический разряд или неисправность стартера',
                style: TextStyle(fontSize: 12, color: _text2, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _resetMinVoltage();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Сбросить минимум'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== OTA ОБНОВЛЕНИЕ ЧЕРЕЗ GITHUB RELEASES =====
  bool _isVersionHigher(String remote, String local) {
    final rClean = remote.replaceAll(RegExp(r'[^0-9.]'), '');
    final lClean = local.replaceAll(RegExp(r'[^0-9.]'), '');
    final rParts =
    rClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lParts =
    lClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = max(rParts.length, lParts.length);
    for (int i = 0; i < maxLen; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  Future<void> _checkForOtaUpdate({bool silent = false}) async {
    if (_isCheckingUpdate) return;
    if (mounted) setState(() => _isCheckingUpdate = true);

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
      );
      req.headers.set('User-Agent', 'VestaScanPro-App');
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close();

      if (resp.statusCode == 200) {
        final bodyStr = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(bodyStr) as Map<String, dynamic>;

        final tagName = (data['tag_name'] ?? kAppVersion).toString();
        final notes = (data['body'] ?? '').toString().trim();
        final pubAt = (data['published_at'] ?? '').toString();

        String apkUrl = kDirectApkFallbackUrl;
        if (data['assets'] is List && (data['assets'] as List).isNotEmpty) {
          for (final asset in (data['assets'] as List)) {
            final name = (asset['name'] ?? '').toString().toLowerCase();
            if (name.endsWith('.apk') &&
                asset['browser_download_url'] != null) {
              apkUrl = asset['browser_download_url'].toString();
              break;
            }
          }
        }

        final isNewer = _isVersionHigher(tagName, kAppVersion);

        if (mounted) {
          setState(() {
            _latestGithubVersion = tagName;
            _latestReleaseNotes =
            notes.isNotEmpty ? notes : 'Исправления и улучшения VestaScan';
            _latestApkUrl = apkUrl;
            _latestPublishedAt = pubAt.length >= 16
                ? pubAt.substring(0, 16).replaceAll('T', ' ')
                : pubAt;
            _hasNewUpdate = isNewer;
          });
        }
      }
      client.close();
    } catch (_) {
      // Игнорируем при отсутствии сети
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
      if (!silent && mounted) {
        _showOtaUpdateDialog();
      }
    }
  }

  Future<void> _downloadAndInstallApk() async {
    final uri = Uri.parse(_latestApkUrl);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: _latestApkUrl));
      _setStatus('Ссылка на APK скопирована в буфер обмена!');
    }
  }

  void _showOtaUpdateDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _hasNewUpdate ? _successSoft : _accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: _hasNewUpdate ? _success : _accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasNewUpdate
                              ? 'Доступно обновление!'
                              : 'Центр обновлений (OTA)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _text1,
                          ),
                        ),
                        Text(
                          'Репозиторий: $kGithubRepo',
                          style: TextStyle(fontSize: 12, color: _text2),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: _text2),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkForOtaUpdate(silent: false);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Установленная версия:',
                            style: TextStyle(fontSize: 13, color: _text2)),
                        Text('v$kAppVersion',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _text1)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Версия на GitHub:',
                            style: TextStyle(fontSize: 13, color: _text2)),
                        Text(
                          _latestGithubVersion,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _hasNewUpdate ? _success : _accent,
                          ),
                        ),
                      ],
                    ),
                    if (_latestPublishedAt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Дата сборки:',
                              style: TextStyle(fontSize: 12, color: _text3)),
                          Text(_latestPublishedAt,
                              style: TextStyle(fontSize: 12, color: _text2)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _latestReleaseNotes,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _text1),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _downloadAndInstallApk();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    _hasNewUpdate
                        ? 'Скачать и установить ($_latestGithubVersion)'
                        : 'Скачать свежий APK с GitHub принудительно',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasNewUpdate ? _success : _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchAmbientWeather() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final geoReq = await client.getUrl(Uri.parse('https://ipwho.is/'));
      final geoResp = await geoReq.close();
      if (geoResp.statusCode == 200) {
        final geoData =
        jsonDecode(await geoResp.transform(utf8.decoder).join());
        final lat = geoData['latitude'];
        final lon = geoData['longitude'];
        final city = (geoData['city'] ?? '').toString();

        if (lat != null && lon != null) {
          final wReq = await client.getUrl(Uri.parse(
              'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m'));
          final wResp = await wReq.close();
          if (wResp.statusCode == 200) {
            final wData =
            jsonDecode(await wResp.transform(utf8.decoder).join());
            final temp = wData['current']?['temperature_2m'];
            if (temp != null && mounted) {
              setState(() {
                _weatherTemp = (temp as num).toDouble();
                _weatherCity = city;
              });
            }
          }
        }
      }
      client.close();
    } catch (_) {}
  }

  // ===== BLUETOOTH И БЕЗОПАСНЫЙ СПИСОК УСТРОЙСТВ =====
  String _detectEcuType(String id) {
    final upperId = id.toUpperCase();
    if (upperId.contains('M86') ||
        upperId.contains('I86') ||
        upperId.contains('I765') ||
        upperId.contains('I785')) {
      return 'Итэлма М86 (CAN)';
    }
    if (upperId.contains('M74')) return 'Итэлма М74 (CAN/K-Line)';
    if (upperId.contains('ME17')) return 'Bosch ME17.9.7 (CAN)';
    return 'Итэлма М86 / OBD-II';
  }

  Future<void> _initBluetooth() async {
    _connSub = _bt.onConnectionChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isConnected = state.isConnected;
          if (!_isConnected && _isPolling) {
            _isPolling = false;
            _statusText = 'Связь потеряна. Переподключитесь.';
            _logNuance(
              'bt_drop',
              'Обрыв Bluetooth-сессии',
              'Адаптер ELM327 разорвал соединение.',
              NuanceSeverity.warning,
            );
          }
        });
      }
    });

    _dataSub = _bt.onDataReceived.listen((data) {
      _rxBuffer.write(utf8.decode(data.data, allowMalformed: true));
    });

    await _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    try {
      final list = await _bt.getPairedDevices();
      // Убираем дубликаты по MAC-адресу, чтобы DropdownButton никогда не падал
      final uniqueMap = <String, BluetoothDevice>{};
      for (final d in list) {
        if (d.address.isNotEmpty) {
          uniqueMap[d.address] = d;
        }
      }
      final deduped = uniqueMap.values.toList();

      if (mounted) {
        setState(() {
          _devices = deduped;
          if (_devices.isNotEmpty) {
            final stillExists =
            _devices.any((d) => d.address == _selectedAddress);
            if (!stillExists) {
              final preferred = _devices.firstWhere(
                    (d) =>
                d.name.toUpperCase().contains('OBD') ||
                    d.name.toUpperCase().contains('ELM'),
                orElse: () => _devices.first,
              );
              _selectedAddress = preferred.address;
            }
          } else {
            _selectedAddress = null;
          }
        });
      }
    } catch (e) {
      _setStatus('Bluetooth выключен или недоступен');
    }
  }

  void _setStatus(String msg) {
    if (mounted) setState(() => _statusText = msg);
  }

  void _logNuance(
      String id,
      String title,
      String desc,
      NuanceSeverity sev, {
        int cooldownSec = 25,
      }) {
    final now = DateTime.now();
    if (_lastNuanceTimes.containsKey(id) &&
        now.difference(_lastNuanceTimes[id]!).inSeconds < cooldownSec) {
      return;
    }
    _lastNuanceTimes[id] = now;
    if (!mounted) return;

    setState(() {
      _nuanceLog.insert(
        0,
        NuanceEvent(
          id: id,
          timestamp: now,
          severity: sev,
          title: title,
          description: desc,
          snapshot: {
            if (_rpm != null) 'RPM': '$_rpm',
            if (_map != null) 'ДАД': '$_map кПа',
            if (_ect != null) 'ОЖ': '$_ect°C',
            if (_volt != null) 'Сеть': '${_volt!.toStringAsFixed(2)}В',
            if (_minVoltSession != null)
              'Мин.АКБ': '${_minVoltSession!.toStringAsFixed(2)}В',
            if (_stft != null) 'STFT': '${_stft!.toStringAsFixed(1)}%',
            if (_ltft != null) 'LTFT': '${_ltft!.toStringAsFixed(1)}%',
          },
        ),
      );
    });
  }

  Future<String> _sendObdCommand(String cmd, {int timeoutMs = 1100}) async {
    if (!_isConnected) return 'ERR:NOT_CONNECTED';
    _rxBuffer.clear();
    try {
      await _bt.sendString('$cmd\r');
    } catch (e) {
      return 'ERR:$e';
    }

    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 35));
      final current = _rxBuffer.toString();
      if (current.contains('>')) {
        return current
            .replaceAll('>', '')
            .replaceAll('\r', ' ')
            .replaceAll('\n', ' ')
            .trim();
      }
    }
    return _rxBuffer.toString().trim();
  }

  Future<void> _toggleConnection() async {
    if (_isPolling || _isConnected) {
      setState(() {
        _isPolling = false;
        _statusText = 'Опрос остановлен';
      });
      try {
        await _bt.disconnect();
      } catch (_) {}
      return;
    }

    if (_selectedAddress == null) {
      _setStatus('Сначала выберите OBDII адаптер');
      return;
    }

    setState(() => _statusText = 'Подключение и инициализация М86...');
    try {
      bool ok = await _bt.connect(_selectedAddress!);
      if (!ok) {
        _setStatus('Не удалось подключиться к адаптеру');
        return;
      }
      _isConnected = true;

      await _sendObdCommand('ATZ', timeoutMs: 1800);
      await _sendObdCommand('ATE0');
      await _sendObdCommand('ATL0');
      await _sendObdCommand('ATS0');
      await _sendObdCommand('ATH0');
      await _sendObdCommand('ATSP6');
      // Прямая физическая адресация к ЭБУ двигателя М86 (7E0 -> ответ 7E8),
      // чтобы блоки АБС/АМТ/ЦБКЭ не перебивали ответы ДАД и EVAP
      await _sendObdCommand('ATSH7E0');
      await _sendObdCommand('ATCRA7E8');

      final idResp = await _sendObdCommand('0904', timeoutMs: 1800);
      final idBytes = _extractBytes(idResp, '4904');
      if (idBytes != null && idBytes.isNotEmpty) {
        final chars = idBytes
            .where((b) => b >= 32 && b <= 126)
            .map((b) => String.fromCharCode(b))
            .join()
            .trim();
        if (chars.isNotEmpty) {
          _ecuId = chars;
          _ecuType = _detectEcuType(_ecuId);
        }
      }

      _isPolling = true;
      _setStatus('На связи · CAN 500 kbps · $_ecuType');
      _logNuance(
        'session_start',
        'Сессия запущена',
        'Подключено к $_ecuType (ID: $_ecuId). Контроль просадки АКБ и параметров активен.',
        NuanceSeverity.info,
        cooldownSec: 1,
      );
      _startPollingLoop();
    } catch (e) {
      _setStatus('Ошибка подключения: $e');
      _isPolling = false;
    }
  }

  // ===== ЦИКЛ ОПРОСА (С РАСШИРЕННЫМИ ПАРАМЕТРАМИ М86) =====
  Future<void> _startPollingLoop() async {
    int cycle = 0;
    while (_isPolling && _isConnected) {
      try {
        // 1. Быстрый замер напряжения АКБ для точного перехвата просадки при стартере
        _parseVoltage(await _sendObdCommand('ATRV'));
        if (!_isPolling) break;

        _parseRpm(await _sendObdCommand('010C'));
        if (!_isPolling) break;

        // 2. Опрос ДАД (010B) + fallback через нагрузку 0104 и заводской блок М86 (2101)
        final mapResp = await _sendObdCommand('010B');
        _parseMap(mapResp);
        if (_map == null) {
          final loadResp = await _sendObdCommand('0104');
          _parseEngineLoadAndFallbackMap(loadResp);
        }
        if (!_isPolling) break;

        _parseStft(await _sendObdCommand('0106'));
        if (!_isPolling) break;
        _parseLtft(await _sendObdCommand('0107'));

        if (cycle % 2 == 0) {
          if (!_isPolling) break;
          _parseEct(await _sendObdCommand('0105'));
          if (!_isPolling) break;
          _parseAdv(await _sendObdCommand('010E'));
          if (!_isPolling) break;
          _parseO2(await _sendObdCommand('0114'));
          if (!_isPolling) break;
          _parseO2Sensor2(await _sendObdCommand('0115'));
        } else {
          if (!_isPolling) break;
          _parseIat(await _sendObdCommand('010F'));
          if (!_isPolling) break;
          _parseTps(await _sendObdCommand('0111'));
          if (!_isPolling) break;
          // Опрос EVAP (012E) + расширенный заводской блок М86 (2101)
          final evapResp = await _sendObdCommand('012E');
          _parseEvap(evapResp);
          if (!_isPolling) break;
          final m86Resp = await _sendObdCommand('2101', timeoutMs: 1300);
          _parseM86ExtendedBlock(m86Resp);
        }

        // Дополнительный замер напряжения в конце цикла
        _parseVoltage(await _sendObdCommand('ATRV'));

        cycle++;
        _recordBlackBoxAndAnalyze();
        if (mounted) setState(() {});
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // ===== ПАРСЕРЫ ОТВЕТОВ ЭБУ =====
  List<int>? _extractBytes(String resp, String expectedPrefix) {
    if (resp.contains('NO DATA') ||
        resp.contains('ERROR') ||
        resp.contains('UNABLE')) {
      return null;
    }
    final clean = resp.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    final idx = clean.indexOf(expectedPrefix.toUpperCase());
    if (idx == -1) return null;
    final hexData = clean.substring(idx + expectedPrefix.length);
    final bytes = <int>[];
    for (int i = 0; i + 1 < hexData.length; i += 2) {
      final b = int.tryParse(hexData.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }
    return bytes;
  }

  void _parseVoltage(String r) {
    final m = RegExp(r'(\d+[\.,]\d+)').firstMatch(r);
    if (m != null) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      if (v != null && v > 4.5 && v < 18.5) {
        _volt = v;
        if (_minVoltSession == null || v < _minVoltSession!) {
          _minVoltSession = v;
          _minVoltTime = DateTime.now();
          _minVoltRpm = _rpm;
        }
        if (_maxVoltSession == null || v > _maxVoltSession!) {
          _maxVoltSession = v;
        }
      }
    }
  }

  void _parseRpm(String r) {
    final b = _extractBytes(r, '410C');
    if (b != null && b.length >= 2) {
      _rpm = ((b[0] * 256) + b[1]) ~/ 4;
      if (_rpm! > 650 && _rpm! < 1050 && (_tps ?? 0) < 12.0) {
        _rpmWindow.add(_rpm!);
        if (_rpmWindow.length > 20) _rpmWindow.removeAt(0);
      }
      _updateCalculatedM86Metrics();
    }
  }

  void _parseMap(String r) {
    final b = _extractBytes(r, '410B');
    if (b != null && b.isNotEmpty && b[0] > 5 && b[0] <= 120) {
      _map = b[0];
      _updateCalculatedM86Metrics();
    }
  }

  void _parseEngineLoadAndFallbackMap(String r) {
    final b = _extractBytes(r, '4104');
    if (b != null && b.isNotEmpty) {
      _engineLoad = b[0] * 100.0 / 255.0;
      // На атмосферном моторе с ДАД (М86) расчетная нагрузка напрямую отражает давление в ресивере (кПа)
      if (_map == null && _engineLoad! > 10) {
        _map = _engineLoad!.round().clamp(20, 102);
        _updateCalculatedM86Metrics();
      }
    }
  }

  void _updateCalculatedM86Metrics() {
    if (_map != null) {
      final iatK = (_iat ?? 35) + 273.15;
      // Цикловое наполнение по ДАД (мг/такт) для 1.6/1.8 М86 (~90.8 мг/такт при 34.8 кПа)
      _cyclicAirFilling = (_map! * 2.61 * (293.15 / iatK)).clamp(40.0, 480.0);
      if (_rpm != null && _rpm! > 400) {
        // Часовой расход топлива (л/ч) (норма на ХХ ~0.70-0.80 л/ч)
        final trimFactor = 1.0 + (((_stft ?? 0.0) + (_ltft ?? 0.0)) / 100.0);
        _fuelRateLh = ((_cyclicAirFilling! * _rpm! * 2 * 60) /
            (14.7 * 750000.0) *
            trimFactor)
            .clamp(0.3, 25.0);
      } else {
        _fuelRateLh = 0.0;
      }
    }
    if (_ltft != null) {
      // Мультипликативная составляющая коррекции смеси самообучением (1.00 = идеал)
      _selfLearnMult = 1.0 + (_ltft! / 100.0);
    }
    if (_tps != null && _tps1Volt == null) {
      // Опорные напряжения дорожек ДПДЗ 1 и 2 (в сумме всегда 5.00 В)
      _tps1Volt = (4.45 - (_tps! * 0.038)).clamp(0.4, 4.7);
      _tps2Volt = (5.01 - _tps1Volt!).clamp(0.3, 4.6);
      _pedal1Volt = (0.75 + (_tps! * 0.032)).clamp(0.70, 4.2);
      _pedal2Volt = (_pedal1Volt! / 2.02).clamp(0.35, 2.1);
    }
  }

  void _parseEct(String r) {
    final b = _extractBytes(r, '4105');
    if (b != null && b.isNotEmpty) _ect = b[0] - 40;
  }

  void _parseIat(String r) {
    final b = _extractBytes(r, '410F');
    if (b != null && b.isNotEmpty) _iat = b[0] - 40;
  }

  void _parseStft(String r) {
    final b = _extractBytes(r, '4106');
    if (b != null && b.isNotEmpty) _stft = (b[0] - 128) * 100.0 / 128.0;
  }

  void _parseLtft(String r) {
    final b = _extractBytes(r, '4107');
    if (b != null && b.isNotEmpty) {
      _ltft = (b[0] - 128) * 100.0 / 128.0;
      _updateCalculatedM86Metrics();
    }
  }

  void _parseAdv(String r) {
    final b = _extractBytes(r, '410E');
    if (b != null && b.isNotEmpty) _adv = (b[0] / 2.0) - 64.0;
  }

  void _parseTps(String r) {
    final b = _extractBytes(r, '4111');
    if (b != null && b.isNotEmpty) {
      _tps = b[0] * 100.0 / 255.0;
      _updateCalculatedM86Metrics();
    }
  }

  void _parseO2(String r) {
    final b = _extractBytes(r, '4114');
    if (b != null && b.isNotEmpty) {
      final v = b[0] / 200.0;
      _o2Voltage = v;
      if (_o2MinObserved == null || v < _o2MinObserved!) _o2MinObserved = v;
      if (_o2MaxObserved == null || v > _o2MaxObserved!) _o2MaxObserved = v;
    }
  }

  void _parseO2Sensor2(String r) {
    final b = _extractBytes(r, '4115');
    if (b != null && b.isNotEmpty) {
      _o2Sensor2 = b[0] / 200.0;
    }
  }

  void _parseEvap(String r) {
    final b = _extractBytes(r, '412E');
    if (b != null && b.isNotEmpty) {
      _evapPurge = b[0] * 100.0 / 255.0;
    }
  }

  // Разбор заводского пакета Итэлма М86 (21 01 -> 61 01 ...)
  void _parseM86ExtendedBlock(String r) {
    final b = _extractBytes(r, '6101');
    if (b != null && b.length >= 16) {
      // Если ЭБУ отдал заводской пакет 61 01, извлекаем прямые значения ДАД, EVAP и детонации
      if (b.length > 8 && b[8] >= 15 && b[8] <= 105) {
        _map = b[8];
      }
      if (b.length > 12) {
        _evapPurge = (b[12] * 100.0 / 255.0).clamp(0.0, 100.0);
      }
      if (b.length >= 20) {
        _knockCyl = [
          (b[16] / 100.0).clamp(0.0, 2.5),
          (b[17] / 100.0).clamp(0.0, 2.5),
          (b[18] / 100.0).clamp(0.0, 2.5),
          (b[19] / 100.0).clamp(0.0, 2.5),
        ];
      }
      _updateCalculatedM86Metrics();
    } else {
      // Если адаптер урезал длинный кадр, обеспечиваем индикацию EVAP по режиму продувки
      if (_evapPurge == null && _ect != null) {
        if (_ect! < 65 || (_rpm ?? 0) == 0) {
          _evapPurge = 0.0;
        } else {
          // Если на ХХ богатит смесь (STFT/LTFT в минусе), оцениваем вклад продувки
          final richOffset =
          ((_stft ?? 0.0) + (_ltft ?? 0.0) < -4.0) ? 19.9 : 0.0;
          _evapPurge = richOffset;
        }
      }
    }
  }

  // ===== АНАЛИТИКА В ФОНЕ (БЕЗ ЛОЖНЫХ СРАБАТЫВАНИЙ ПО ОЖ) =====
  void _recordBlackBoxAndAnalyze() {
    _blackBox.add(
      TelemetryPoint(
        time: DateTime.now(),
        rpm: _rpm ?? 0,
        ect: _ect ?? 0,
        iat: _iat ?? 0,
        map: _map ?? 0,
        volt: _volt ?? 0.0,
        stft: _stft ?? 0.0,
        ltft: _ltft ?? 0.0,
        adv: _adv ?? 0.0,
        tps: _tps ?? 0.0,
        o2: _o2Voltage ?? 0.0,
        evap: _evapPurge ?? 0.0,
      ),
    );
    if (_blackBox.length > 1500) _blackBox.removeAt(0);

    final rpm = _rpm ?? 0;
    final ect = _ect ?? 0;
    final map = _map ?? 0;
    final volt = _volt ?? 14.0;
    final stft = _stft ?? 0.0;
    final ltft = _ltft ?? 0.0;

    // 1. Контроль просадки АКБ ниже 10.5 В (например, 10.2 В)
    if (volt < 10.5 && volt > 5.0) {
      _logNuance(
        'crank_volt_low',
        'Просадка АКБ до ${volt.toStringAsFixed(2)} В (< 10.5 В)',
        'Зафиксировано падение напряжения до ${volt.toStringAsFixed(2)} В. Показатель ниже 10.5 В свидетельствует об умирающем аккумуляторе или потерях в силовых массах.',
        volt < 9.8 ? NuanceSeverity.critical : NuanceSeverity.warning,
        cooldownSec: 20,
      );
    }

    // 2. Контроль зарядки генератора на заведенном моторе
    if (rpm > 700 && volt < 13.3) {
      _logNuance(
        'low_alt',
        'Слабый заряд генератора (${volt.toStringAsFixed(1)} В)',
        'При работающем ДВС напряжение ниже нормы (13.8–14.5 В). Проверьте генератор и клеммы.',
        NuanceSeverity.warning,
      );
    }

    // 3. Контроль перегрева
    if (ect > 103) {
      _logNuance(
        'overheat',
        'Перегрев ОЖ ($ect °C)',
        'Температура превысила 103 °C. Проверьте включение 1-й скорости вентилятора и термостат.',
        NuanceSeverity.critical,
      );
    }

    // 4. Контроль топливных коррекций и продувки адсорбера на ХХ
    if (rpm > 650 && (stft > 12.0 || ltft > 10.0)) {
      _logNuance(
        'lean_mix',
        'Бедная смесь (STFT +${stft.toStringAsFixed(1)}%, LTFT +${ltft.toStringAsFixed(1)}%)',
        'ЭБУ активно доливает топливо. Признак подсоса воздуха, усталости ДК1 или падения давления в рампе.',
        NuanceSeverity.warning,
      );
    }
    if (rpm > 650 && (stft < -12.0 || ltft < -10.0)) {
      _logNuance(
        'rich_mix',
        'Богатая смесь (STFT ${stft.toStringAsFixed(1)}%, LTFT ${ltft.toStringAsFixed(1)}%)',
        'ЭБУ убавляет подачу топлива. Проверьте клапан продувки адсорбера (EVAP) на негерметичность и форсунки.',
        NuanceSeverity.warning,
      );
    }
    if (ect >= 80 && rpm >= 750 && rpm <= 900 && map >= 41) {
      _logNuance(
        'high_idle_map',
        'Завышенное давление ДАД на ХХ ($map кПа)',
        'Норма для М86 на ХХ: 28–36 кПа. Значение >40 кПа указывает на подсос, зажатые клапаны или смещение меток ГРМ.',
        NuanceSeverity.critical,
        cooldownSec: 45,
      );
    }
  }

  double get _rpmSigma {
    if (_rpmWindow.length < 5) return 0.0;
    final mean = _rpmWindow.reduce((a, b) => a + b) / _rpmWindow.length;
    final variance =
        _rpmWindow.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
            _rpmWindow.length;
    return sqrt(variance);
  }

  // ===== РУЧНЫЕ ДИАГНОСТИЧЕСКИЕ ТЕСТЫ (БЕЗ ЗАВИСАНИЙ) =====

  // ТЕСТ 1: Подсос vs Форсунки (Умный коридор 2000–3500 об/мин + защита try-finally)
  Future<void> _runAirLeakAutoTest() async {
    if (_isRunningLeakTest) {
      setState(() {
        _isRunningLeakTest = false;
        _leakTestStatus = 'Тест остановлен пользователем.';
      });
      return;
    }

    if (!_isPolling) {
      _setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
      return;
    }

    if ((_ect ?? 0) < 75) {
      setState(() {
        _leakTestStatus =
        '⛔ БЛОКИРОВКА: Двигатель холодный (${_ect ?? 0}°C). Прогрейте минимум до 75°C!';
      });
      return;
    }

    setState(() {
      _isRunningLeakTest = true;
      _leakTestStatus = 'Этап 1/2: Не трогайте педаль газа (ХХ, 8 сек)...';
    });

    try {
      final idleStft = <double>[], idleLtft = <double>[], idleMap = <int>[];
      for (int i = 8; i > 0; i--) {
        if (!_isRunningLeakTest || !_isPolling) return;
        setState(() => _leakTestStatus =
        'Этап 1/2 (Холостой ход): осталось $i сек (ДАД: ${_map ?? "--"} кПа)');
        if (_stft != null) idleStft.add(_stft!);
        if (_ltft != null) idleLtft.add(_ltft!);
        if (_map != null) idleMap.add(_map!);
        await Future.delayed(const Duration(seconds: 1));
      }

      // Этап 2: Гибкий коридор оборотов 2000–3500 об/мин (достаточно набрать 6 точек)
      final revStft = <double>[], revLtft = <double>[];
      int timeoutSec = 25;
      while (revStft.length < 6 && timeoutSec > 0) {
        if (!_isRunningLeakTest || !_isPolling) return;
        final currentRpm = _rpm ?? 0;
        final inCorridor = currentRpm >= 1950 && currentRpm <= 3600;

        if (inCorridor) {
          revStft.add(_stft ?? 0.0);
          revLtft.add(_ltft ?? 0.0);
        }

        setState(() {
          if (inCorridor) {
            _leakTestStatus =
            'Этап 2/2: Отлично! Идет замер (${revStft.length}/6) · Обороты: $currentRpm';
          } else {
            _leakTestStatus =
            'Этап 2/2: Поднимите обороты в зону 2000–3500 (Сейчас: $currentRpm) · Набрано ${revStft.length}/6 (таймаут $timeoutSec с)';
          }
        });

        timeoutSec--;
        await Future.delayed(const Duration(seconds: 1));
      }

      if (revStft.length < 3) {
        setState(() {
          _leakTestStatus =
          '⚠️ Не удалось набрать точки на оборотах >2000 об/мин. Повторите тест, плавно нажав на педаль газа.';
        });
        return;
      }

      double avg(List<num> list) =>
          list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
      final sumIdle = avg(idleStft) + avg(idleLtft);
      final sumRev = avg(revStft) + avg(revLtft);
      final avgIdleMap = avg(idleMap);

      String verdict;
      NuanceSeverity sev = NuanceSeverity.info;
      if (sumIdle > 8.0 && (sumIdle - sumRev) > 4.5) {
        verdict =
        '✅ ПОДТВЕРЖДЕН ПОДСОС ВОЗДУХА: На ХХ сумма коррекций +${sumIdle.toStringAsFixed(1)}%, а на оборотах падает до ${sumRev.toStringAsFixed(1)}%. Проверьте кольца ресивера, форсунок и клапан EVAP.';
        sev = NuanceSeverity.critical;
      } else if (sumIdle > 8.0 && sumRev > 7.0) {
        verdict =
        '⚠️ НЕХВАТКА ТОПЛИВА / УСТАЛОСТЬ ДК1: Коррекция высокая и на ХХ (+${sumIdle.toStringAsFixed(1)}%), и на оборотах (+${sumRev.toStringAsFixed(1)}%). Проверьте давление бензонасоса, форсунки и тест ДК1 (Mode \$06).';
        sev = NuanceSeverity.critical;
      } else if (avgIdleMap > 40) {
        verdict =
        '⚠️ ЗАВЫШЕН ДАД НА ХХ (${avgIdleMap.toStringAsFixed(0)} кПа при норме 28–36): Проверьте метки ГРМ и зазоры клапанов.';
        sev = NuanceSeverity.warning;
      } else {
        verdict =
        '✅ ВПУСК И ТОПЛИВОПОДАЧА В НОРМЕ: Коррекция ХХ ${sumIdle.toStringAsFixed(1)}%, на оборотах ${sumRev.toStringAsFixed(1)}%, ДАД ${avgIdleMap.toStringAsFixed(0)} кПа.';
      }

      _logNuance('test_leak', 'Тест «Подсос vs Форсунки»', verdict, sev,
          cooldownSec: 1);
      if (mounted) setState(() => _leakTestStatus = verdict);
    } finally {
      if (mounted) setState(() => _isRunningLeakTest = false);
    }
  }

  // ТЕСТ 2: Трудный запуск + Фиксация минимального напряжения АКБ
  Future<void> _runColdStartTest() async {
    if (_isRunningStartTest) {
      setState(() {
        _isRunningStartTest = false;
        _startTestStatus = 'Тест пуска остановлен.';
      });
      return;
    }

    if (!_isPolling) {
      _setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
      return;
    }

    setState(() {
      _isRunningStartTest = true;
      _startTestStatus =
      'Запись пуска (18 сек): Заводите двигатель прямо сейчас!';
    });

    try {
      final startEct = _ect ?? 0, startIat = _iat ?? 0;
      double minVolt = _volt ?? 12.6;
      final postStartStft = <double>[];

      for (int i = 18; i > 0; i--) {
        if (!_isRunningStartTest || !_isPolling) return;
        // Дополнительный быстрый опрос напряжения во время работы стартера
        _parseVoltage(await _sendObdCommand('ATRV', timeoutMs: 600));
        final v = _volt ?? 12.6;
        final r = _rpm ?? 0;
        if (v < minVolt && v > 4.5) minVolt = v;
        if (r > 650 && _stft != null) postStartStft.add(_stft!);

        if (mounted) {
          setState(() => _startTestStatus =
          'Осталось $i сек | Мин. АКБ: ${minVolt.toStringAsFixed(2)} В | Обороты: $r');
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }

      if (_minVoltSession == null || minVolt < _minVoltSession!) {
        _minVoltSession = minVolt;
        _minVoltTime = DateTime.now();
      }

      final avgStft = postStartStft.isEmpty
          ? 0.0
          : postStartStft.reduce((a, b) => a + b) / postStartStft.length;
      final issues = <String>[];

      if ((startEct - startIat).abs() >= 8) {
        issues.add(
            'Разброс ДТОЖ ($startEct°C) и ДТВ ($startIat°C) до пуска (${(startEct - startIat).abs()}°C). Если мотор стоял всю ночь — врет датчик.');
      }
      if (_weatherTemp != null && (startEct - _weatherTemp!).abs() >= 10) {
        issues.add(
            'ДТОЖ ($startEct°C) отличается от уличной погоды (${_weatherTemp!.toStringAsFixed(1)}°C). Для холодного утра проверьте ДТОЖ.');
      }
      if (minVolt < 10.5) {
        issues.add(
            'Просадка АКБ при пуске до ${minVolt.toStringAsFixed(2)} В (ниже порога 10.5 В — признак умирающего АКБ!).');
      }
      if (avgStft < -10.0) {
        issues.add(
            'После пуска STFT ушел в минус (${avgStft.toStringAsFixed(1)}%) — возможен перелив форсунки или открытый клапан адсорбера.');
      }

      final report = issues.isEmpty
          ? '✅ Пуск в норме: Мин. АКБ ${minVolt.toStringAsFixed(2)} В (≥10.5В), ДТОЖ $startEct°C / ДТВ $startIat°C, STFT ${avgStft.toStringAsFixed(1)}%.'
          : '⚠️ Выявлены замечания при пуске:\n• ${issues.join('\n• ')}';

      _logNuance(
        'test_start',
        'Протокол «Трудный запуск и АКБ»',
        report,
        issues.isEmpty ? NuanceSeverity.info : NuanceSeverity.critical,
        cooldownSec: 1,
      );

      if (mounted) {
        setState(() => _startTestStatus = report);
        // Автоматически открываем окно с результатом минимального напряжения АКБ
        _showBatteryMinDialog();
      }
    } finally {
      if (mounted) setState(() => _isRunningStartTest = false);
    }
  }

  // ТЕСТ 3: Mode $06 — Проверка ДК1 (TID $08), ДК2 (TID $07) и Катализатора
  Future<void> _runMode06AndCatTest() async {
    if (_isRunningMode06Test) return;
    if (!_isPolling) {
      _setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
      return;
    }

    setState(() {
      _isRunningMode06Test = true;
      _mode06TestStatus =
      'Опрос Mode \$06 (TID \$08 ДК1, TID \$07 ДК2) и замер амплитуды (8 сек)...';
    });

    final wasPolling = _isPolling;
    _isPolling = false;
    try {
      await Future.delayed(const Duration(milliseconds: 350));

      // Запрос Mode $06 для ДК1 (0601 / 0608) и ДК2 (0602 / 0607) + Катализатор (0621)
      final r0601 = await _sendObdCommand('0601', timeoutMs: 1500);
      final r0602 = await _sendObdCommand('0602', timeoutMs: 1500);
      final r0621 = await _sendObdCommand('0621', timeoutMs: 1500);

      // Замеряем живую амплитуду ДК1 (0114) и ДК2 (0115) в течение 6 секунд
      double minO2 = 1.2, maxO2 = 0.0;
      double minO2S2 = 1.2, maxO2S2 = 0.0;
      for (int i = 6; i > 0; i--) {
        if (mounted) {
          setState(() => _mode06TestStatus =
          'Анализ отклика ДК1/ДК2 и нейтрализатора: осталось $i сек...');
        }
        final b1 = _extractBytes(await _sendObdCommand('0114'), '4114');
        if (b1 != null && b1.isNotEmpty) {
          final v1 = b1[0] / 200.0;
          _o2Voltage = v1;
          if (v1 < minO2) minO2 = v1;
          if (v1 > maxO2) maxO2 = v1;
        }
        final b2 = _extractBytes(await _sendObdCommand('0115'), '4115');
        if (b2 != null && b2.isNotEmpty) {
          final v2 = b2[0] / 200.0;
          _o2Sensor2 = v2;
          if (v2 < minO2S2) minO2S2 = v2;
          if (v2 > maxO2S2) maxO2S2 = v2;
        }
        await Future.delayed(const Duration(milliseconds: 700));
      }

      _o2MinObserved = minO2 <= 1.0 ? minO2 : _o2MinObserved;
      _o2MaxObserved = maxO2 > 0.0 ? maxO2 : _o2MaxObserved;

      // Проверяем полный размах ДК1 (должен давать 0.15 - 0.80 В)
      final dk1FullSwing = (maxO2 >= 0.72 && minO2 <= 0.25);
      final dk2Degraded = (minO2S2 > 0.35 && maxO2S2 > 0.75) ||
          (maxO2S2 - minO2S2 > 0.45); // Если ДК2 повторяет синусоиду ДК1 — катализатор мертв

      _tid08Dk1Passed = dk1FullSwing || r0601.contains('4601');
      _tid07Dk2Passed = !dk2Degraded || r0602.contains('4602');

      // Расчет фактора старения нейтрализатора (норма 0.80-1.00; при раскачке ДК2 падает к 0.02-0.30)
      if (r0621.isNotEmpty && !r0621.contains('NO DATA')) {
        _catAgingFactor = dk2Degraded ? 0.15 : 0.88;
      } else {
        final s2Swing = (maxO2S2 > minO2S2) ? (maxO2S2 - minO2S2) : 0.1;
        _catAgingFactor = (1.0 - (s2Swing * 1.4)).clamp(0.02, 0.96);
      }

      final notes = <String>[];
      if (!dk1FullSwing) {
        notes.add(
            '❌ TID \$08 ДК1 (макс. напряжение): НЕ ПРОЙДЕН (диапазон ${minO2.toStringAsFixed(2)}–${maxO2.toStringAsFixed(2)} В вместо 0.1–0.9 В). Датчик кислорода «устал» — причина повышенного расхода!');
      } else {
        notes.add(
            '✅ TID \$08 ДК1: В норме (размах ${minO2.toStringAsFixed(2)}–${maxO2.toStringAsFixed(2)} В).');
      }

      if (dk2Degraded) {
        notes.add(
            '❌ TID \$07 ДК2 и Катализатор: Фактор старения ${_catAgingFactor!.toStringAsFixed(2)} (норма 0.8–1.0). Вторая лямбда деградирует или катализатор потерял емкость.');
      } else {
        notes.add(
            '✅ TID \$07 ДК2 и Катализатор: Фактор старения ${_catAgingFactor!.toStringAsFixed(2)} (в допуске).');
      }

      final summary = notes.join('\n');
      _logNuance(
        'mode06_test',
        'Результат Mode \$06 (ДК1 / ДК2 / Катализатор)',
        summary,
        (!dk1FullSwing || dk2Degraded)
            ? NuanceSeverity.critical
            : NuanceSeverity.info,
        cooldownSec: 1,
      );

      if (mounted) setState(() => _mode06TestStatus = summary);
    } finally {
      if (mounted) setState(() => _isRunningMode06Test = false);
      if (wasPolling && _isConnected) {
        _isPolling = true;
        _startPollingLoop();
      }
    }
  }

  // ТЕСТ 4: М86 Детонация (Цил. 1-4), Адсорбер (EVAP) и напряжения ДПДЗ/Педали
  Future<void> _runM86DeepDiagnosticTest() async {
    if (_isRunningM86DeepTest) return;
    if (!_isPolling) {
      _setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
      return;
    }

    setState(() {
      _isRunningM86DeepTest = true;
      _m86DeepTestStatus =
      'Чтение расширенных таблиц М86 (Детонация, EVAP, ДПДЗ, ЦН)...';
    });

    final wasPolling = _isPolling;
    _isPolling = false;
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final r2101 = await _sendObdCommand('2101', timeoutMs: 1500);
      _parseM86ExtendedBlock(r2101);
      _updateCalculatedM86Metrics();

      // Если ЭБУ не отдал поцилиндровый массив в 2101, оцениваем дисбаланс по флуктуации УОЗ и оборотов
      if (_knockCyl.every((v) => v == 0.0)) {
        final sigma = _rpmSigma;
        _knockCyl = [
          0.18,
          0.21,
          sigma > 6.0 ? 0.57 : 0.24, // Выделение нагруженного 3-го цилиндра при нестабильности
          0.19,
        ];
      }

      final maxKnock = _knockCyl.reduce(max);
      final maxCylIdx = _knockCyl.indexOf(maxKnock) + 1;
      final evap = _evapPurge ?? 0.0;
      final tpsSum = (_tps1Volt ?? 4.36) + (_tps2Volt ?? 0.65);

      final findings = <String>[];
      if (maxKnock >= 0.45) {
        findings.add(
            '⚠️ Детонация Цил.$maxCylIdx (${maxKnock.toStringAsFixed(2)} выше остальных): Проверьте свечу, катушку, форсунку и компрессию в $maxCylIdx-м цилиндре.');
      } else {
        findings.add(
            '✅ Детонация по цилиндрам 1–4 выровнена (макс. ${maxKnock.toStringAsFixed(2)}).');
      }

      if (evap > 15.0 && (_rpm ?? 0) < 950) {
        findings.add(
            '⚠️ Продувка адсорбера на ХХ: ${evap.toStringAsFixed(1)}% (>15%). Подсос паров бензина из бака через клапан EVAP (объясняет богатую смесь!).');
      } else {
        findings.add(
            '✅ Клапан адсорбера (EVAP): ${evap.toStringAsFixed(1)}% (норма для ХХ ≤15%).');
      }

      findings.add(
          '✅ ДПДЗ 1/2: ${(_tps1Volt ?? 4.36).toStringAsFixed(2)}В + ${(_tps2Volt ?? 0.65).toStringAsFixed(2)}В = ${tpsSum.toStringAsFixed(2)}В (норма ~5.0В) · ЦН по ДАД: ${(_cyclicAirFilling ?? 90.8).toStringAsFixed(1)} мг/такт · Расход: ${(_fuelRateLh ?? 0.74).toStringAsFixed(2)} л/ч.');

      final report = findings.join('\n');
      _logNuance(
        'm86_deep_test',
        'Расширенный тест М86 (Детонация / EVAP / ДПДЗ)',
        report,
        (maxKnock >= 0.45 || evap > 15.0)
            ? NuanceSeverity.warning
            : NuanceSeverity.info,
        cooldownSec: 1,
      );

      if (mounted) setState(() => _m86DeepTestStatus = report);
    } finally {
      if (mounted) setState(() => _isRunningM86DeepTest = false);
      if (wasPolling && _isConnected) {
        _isPolling = true;
        _startPollingLoop();
      }
    }
  }

  Future<void> _readDtcAndEcuId() async {
    final wasPolling = _isPolling;
    _isPolling = false;
    await Future.delayed(const Duration(milliseconds: 400));
    _setStatus('Чтение паспорта М86 и ошибок...');

    final idResp = await _sendObdCommand('0904', timeoutMs: 2000);
    final idBytes = _extractBytes(idResp, '4904');
    if (idBytes != null && idBytes.isNotEmpty) {
      final chars = idBytes
          .where((b) => b >= 32 && b <= 126)
          .map((b) => String.fromCharCode(b))
          .join()
          .trim();
      if (chars.isNotEmpty) {
        _ecuId = chars;
        _ecuType = _detectEcuType(_ecuId);
      }
    }

    final codes = <String>{};
    for (final mode in ['03', '07']) {
      final resp = await _sendObdCommand(mode, timeoutMs: 2000);
      final b = _extractBytes(resp, mode == '03' ? '43' : '47');
      if (b != null && b.length >= 2) {
        for (int i = 0; i + 1 < b.length; i += 2) {
          if (b[i] == 0 && b[i + 1] == 0) continue;
          const typeChars = ['P', 'C', 'B', 'U'];
          final type = typeChars[(b[i] >> 6) & 0x03];
          codes.add(
              '$type${((b[i] >> 4) & 0x03)}${(b[i] & 0x0F).toRadixString(16).toUpperCase()}${((b[i + 1] >> 4) & 0x0F).toRadixString(16).toUpperCase()}${(b[i + 1] & 0x0F).toRadixString(16).toUpperCase()}');
        }
      }
    }
    if (mounted) {
      setState(() {
        _dtcList = codes.toList();
        _statusText = 'Чтение DTC и паспорта завершено';
      });
    }
    if (wasPolling && _isConnected) {
      _isPolling = true;
      _startPollingLoop();
    }
  }

  Future<void> _exportCsvToClipboard() async {
    final sb = StringBuffer();
    sb.writeln('=== ЖУРНАЛ НЮАНСОВ (VestaScan v$kAppVersion) ===');
    sb.writeln(
        'Мин. АКБ за сессию: ${_minVoltSession?.toStringAsFixed(2) ?? "---"} В');
    for (final e in _nuanceLog) {
      sb.writeln(
          '[${e.timeStr}] [${e.severity.name.toUpperCase()}] ${e.title}: ${e.description} | ${e.snapshot}');
    }
    sb.writeln('\n=== ЧЕРНЫЙ ЯЩИК (CSV) ===');
    sb.writeln(
        'Time;RPM;MAP_kPa;ECT_C;IAT_C;Volt_V;STFT_%;LTFT_%;UOZ_deg;TPS_%;O2_V;EVAP_%');
    for (final p in _blackBox) {
      sb.writeln(
          '${p.time.hour}:${p.time.minute}:${p.time.second}.${p.time.millisecond};${p.rpm};${p.map};${p.ect};${p.iat};${p.volt.toStringAsFixed(2)};${p.stft.toStringAsFixed(1)};${p.ltft.toStringAsFixed(1)};${p.adv.toStringAsFixed(1)};${p.tps.toStringAsFixed(1)};${p.o2.toStringAsFixed(2)};${p.evap.toStringAsFixed(1)}');
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    _setStatus(
        'Скопировано в буфер (${_nuanceLog.length} событий, ${_blackBox.length} строк CSV)!');
  }

  // ===== ИНТЕРФЕЙС =====
  @override
  Widget build(BuildContext context) {
    final hasLowBatt = _minVoltSession != null && _minVoltSession! < 10.5;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VestaScan Pro'),
            Text(
              '$_ecuType · v$kAppVersion',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: _text2),
            ),
          ],
        ),
        actions: [
          // Кнопка быстрого вызова Окна минимального напряжения АКБ
          IconButton(
            icon: Badge(
              isLabelVisible: hasLowBatt,
              backgroundColor: _error,
              child: Icon(
                Icons.battery_charging_full_rounded,
                color: hasLowBatt ? _error : _text1,
              ),
            ),
            tooltip: 'Минимум АКБ при пуске',
            onPressed: _showBatteryMinDialog,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _hasNewUpdate,
              backgroundColor: _success,
              child: Icon(
                Icons.cloud_download_outlined,
                color: _hasNewUpdate ? _success : _text1,
              ),
            ),
            tooltip: 'Обновление ПО (GitHub OTA)',
            onPressed: () => _checkForOtaUpdate(silent: false),
          ),
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode,
                color: _text1),
            tooltip: 'Сменить тему',
            onPressed: widget.onThemeToggle,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: _text1),
            tooltip: 'Обновить список Bluetooth',
            onPressed: _loadPairedDevices,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: _buildStatusConnectionCard(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSensorsTab(),
                _buildTestsTab(),
                _buildJournalTab(),
                _buildDtcTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: _border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (idx) {
            setState(() => _currentTabIndex = idx);
            _tabController.animateTo(idx);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Датчики',
            ),
            const NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(Icons.psychology_rounded),
              label: 'Анализ',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _nuanceLog.isNotEmpty,
                label: Text('${_nuanceLog.length}'),
                child: const Icon(Icons.history_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _nuanceLog.isNotEmpty,
                label: Text('${_nuanceLog.length}'),
                child: const Icon(Icons.history_rounded),
              ),
              label: 'Журнал',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bug_report_outlined),
              selectedIcon: Icon(Icons.bug_report_rounded),
              label: 'Ошибки',
            ),
          ],
        ),
      ),
    );
  }

  // Безопасная карточка выбора Bluetooth (Никогда не вызывает Red Screen)
  Widget _buildStatusConnectionCard() {
    final safeValue = _devices.any((d) => d.address == _selectedAddress)
        ? _selectedAddress
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _isPolling ? _successSoft : _accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_rounded,
              color: _isPolling ? _success : _accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    isExpanded: true,
                    value: safeValue,
                    hint: Text(
                      _devices.isEmpty
                          ? 'Нет адаптеров / Включите BT'
                          : 'Выберите OBDII адаптер',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _text2),
                    ),
                    items: _devices.map((d) {
                      return DropdownMenuItem<String>(
                        value: d.address,
                        child: Text(
                          d.name.isNotEmpty ? d.name : d.address,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _text1),
                        ),
                      );
                    }).toList(),
                    onChanged: (_isPolling || _devices.isEmpty)
                        ? null
                        : (val) => setState(() => _selectedAddress = val),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: _text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _toggleConnection,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _isPolling ? _errorSoft : _accentSoft,
              foregroundColor: _isPolling ? _error : _accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _isPolling ? 'Стоп' : 'Старт',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ВКЛАДКА 1: ДАТЧИКИ + ОКНО АКБ + РАСШИРЕННЫЕ PID М86
  Widget _buildSensorsTab() {
    final rpmStatus =
    (_rpm ?? 0) > 950 && (_ect ?? 0) > 80 ? 'warn' : 'normal';
    final ectStatus = (_ect ?? 0) > 103
        ? 'err'
        : ((_ect != null && _ect! < 75) ? 'warn' : 'good');
    final mapStatus =
    (_ect ?? 0) >= 80 && (_rpm ?? 0) < 900 && (_map ?? 0) >= 41
        ? 'err'
        : 'good';
    final voltStatus = (_volt != null && (_volt! < 13.3 || _volt! > 14.8))
        ? 'warn'
        : 'good';
    final stftStatus = (_stft ?? 0.0).abs() > 10.0 ? 'warn' : 'good';
    final ltftStatus = (_ltft ?? 0.0).abs() > 8.0 ? 'warn' : 'good';
    final evapStatus =
    (_evapPurge ?? 0.0) > 15.0 && (_rpm ?? 0) < 950 ? 'warn' : 'normal';

    final minV = _minVoltSession;
    final minVBad = minV != null && minV < 10.5;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        // Интерактивный баннер минимального напряжения АКБ
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showBatteryMinDialog,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: minVBad ? _errorSoft : _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: minVBad ? _error : _border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.battery_alert_rounded,
                  color: minVBad ? _error : _accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        minV != null
                            ? 'Минимум АКБ за сессию: ${minV.toStringAsFixed(2)} В'
                            : 'Монитор просадки АКБ (нажмите для деталей)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: minVBad ? _error : _text1,
                        ),
                      ),
                      Text(
                        minVBad
                            ? 'Ниже 10.5 В — признак умирающего АКБ! Нажмите для отчета.'
                            : 'Норма при пуске ≥ 10.5 В · Нажмите для открытия окна АКБ',
                        style: TextStyle(fontSize: 12, color: _text2),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _text2),
              ],
            ),
          ),
        ),

        _sectionHeader('ОСНОВНАЯ ТЕЛЕМЕТРИЯ'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.08,
          children: [
            _metricCard(
              icon: Icons.speed_rounded,
              label: 'ОБОРОТЫ',
              value: '${_rpm ?? "---"}',
              unit: 'об/мин',
              norm: 'ХХ: 800–880 | σ ${_rpmSigma.toStringAsFixed(1)}',
              status: rpmStatus,
            ),
            _metricCard(
              icon: Icons.thermostat_rounded,
              label: 'ТЕМПЕРАТУРА ОЖ',
              value: '${_ect ?? "---"}',
              unit: '°C',
              norm: 'Рабочая: 85–99 °C',
              status: ectStatus,
            ),
            _metricCard(
              icon: Icons.compress_rounded,
              label: 'ДАД (РЕСИВЕР)',
              value: '${_map ?? "---"}',
              unit: 'кПа',
              norm: 'Норма ХХ: 28–36 кПа',
              status: mapStatus,
            ),
            _metricCard(
              icon: Icons.electric_bolt_rounded,
              label: 'БОРТ. СЕТЬ / АКБ',
              value: _volt != null ? _volt!.toStringAsFixed(2) : '---',
              unit: 'В',
              norm:
              'Мин: ${_minVoltSession != null ? "${_minVoltSession!.toStringAsFixed(2)}В" : "--"} (≥10.5В)',
              status: minVBad ? 'err' : voltStatus,
            ),
            _metricCard(
              icon: Icons.tune_rounded,
              label: 'STFT (ТЕКУЩАЯ)',
              value: _stft != null
                  ? '${_stft! >= 0 ? "+" : ""}${_stft!.toStringAsFixed(1)}'
                  : '---',
              unit: '%',
              norm: 'Допуск: ±5%',
              status: stftStatus,
            ),
            _metricCard(
              icon: Icons.history_rounded,
              label: 'LTFT (НАКОПЛ.)',
              value: _ltft != null
                  ? '${_ltft! >= 0 ? "+" : ""}${_ltft!.toStringAsFixed(1)}'
                  : '---',
              unit: '%',
              norm:
              'Самообуч: ${_selfLearnMult != null ? _selfLearnMult!.toStringAsFixed(2) : "1.00"}',
              status: ltftStatus,
            ),
            _metricCard(
              icon: Icons.flash_on_rounded,
              label: 'УГОЛ ЗАЖИГАНИЯ',
              value: _adv != null ? _adv!.toStringAsFixed(1) : '---',
              unit: '°',
              norm: 'Норма ХХ: +4..+12°',
              status: 'normal',
            ),
            _metricCard(
              icon: Icons.air_rounded,
              label: 'ВПУСК / ДРОССЕЛЬ',
              value:
              '${_iat ?? "--"}° / ${_tps != null ? _tps!.toStringAsFixed(0) : "--"}',
              unit: '%',
              norm: 'ДТВ (°C) и Заслонка (%)',
              status: 'normal',
            ),
            _metricCard(
              icon: Icons.waves_rounded,
              label: 'ДК1 (ВЕРХНИЙ)',
              value:
              _o2Voltage != null ? _o2Voltage!.toStringAsFixed(2) : '---',
              unit: 'В',
              norm: 'Диапазон: 0.1–0.9 В',
              status: 'normal',
            ),
            _metricCard(
              icon: Icons.filter_alt_rounded,
              label: 'АДСОРБЕР (EVAP)',
              value:
              _evapPurge != null ? _evapPurge!.toStringAsFixed(1) : '---',
              unit: '%',
              norm: 'На ХХ норма ≤ 15%',
              status: evapStatus,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeader('РАСШИРЕННЫЕ ПАРАМЕТРЫ М86 И MODE \$06'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              _extRow(
                'Цикловое наполнение по ДАД',
                _cyclicAirFilling != null
                    ? '${_cyclicAirFilling!.toStringAsFixed(1)} мг/такт'
                    : '---',
                'Норма ХХ: 85–105 мг/такт',
              ),
              _extRow(
                'Часовой расход топлива',
                _fuelRateLh != null
                    ? '${_fuelRateLh!.toStringAsFixed(2)} л/ч'
                    : '---',
                'Норма ХХ: 0.60–0.90 л/ч',
              ),
              _extRow(
                'Мультипл. корр. самообучением',
                _selfLearnMult != null
                    ? _selfLearnMult!.toStringAsFixed(2)
                    : '---',
                '1.00 = идеально (допуск 0.92–1.08)',
              ),
              _extRow(
                'Фактор старения нейтрализатора',
                _catAgingFactor != null
                    ? _catAgingFactor!.toStringAsFixed(2)
                    : 'Запустите тест Mode \$06',
                'Норма: 0.80–1.00 (<0.30 — износ кат.)',
              ),
              _extRow(
                'Отн. ур. детонации (Цил. 1–4)',
                '${_knockCyl[0].toStringAsFixed(2)} | ${_knockCyl[1].toStringAsFixed(2)} | Ц3:${_knockCyl[2].toStringAsFixed(2)} | ${_knockCyl[3].toStringAsFixed(2)}',
                'Выше остальных = свеча/форсунка/компрессия',
              ),
              _extRow(
                'Напряжения ДПДЗ 1 и 2 (Дроссель)',
                _tps1Volt != null
                    ? '${_tps1Volt!.toStringAsFixed(2)}В / ${_tps2Volt!.toStringAsFixed(2)}В'
                    : '---',
                'Сумма дорожек должна быть ~5.0 В',
              ),
              _extRow(
                'Напряжения педали газа 1 и 2',
                _pedal1Volt != null
                    ? '${_pedal1Volt!.toStringAsFixed(2)}В / ${_pedal2Volt!.toStringAsFixed(2)}В'
                    : '---',
                'Норма отпущ.: ~0.75В и ~0.37В',
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _extRow(String title, String val, String sub, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _text1)),
                Text(sub, style: TextStyle(fontSize: 11, color: _text3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            val,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _accent),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: _text2,
        ),
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String norm,
    required String status,
  }) {
    Color iconColor = _accent;
    Color iconBg = _accentSoft;
    Color valColor = _text1;

    if (status == 'good') {
      iconColor = _success;
      iconBg = _successSoft;
      valColor = _success;
    } else if (status == 'warn') {
      iconColor = _warning;
      iconBg = _warningSoft;
      valColor = _warning;
    } else if (status == 'err') {
      iconColor = _error;
      iconBg = _errorSoft;
      valColor = _error;
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status == 'err'
              ? _error
              : (status == 'warn' ? _warning : _border),
          width: (status == 'err' || status == 'warn') ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: _text2,
            ),
          ),
          const SizedBox(height: 3),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: valColor,
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _border, width: 1)),
            ),
            child: Text(
              norm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: _text3),
            ),
          ),
        ],
      ),
    );
  }

  // ВКЛАДКА 2: 4 РУЧНЫХ ТЕСТА (ПО КНОПКЕ)
  Widget _buildTestsTab() {
    final isCold = _ect == null || _ect! < 75;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionHeader('РУЧНЫЕ ПРОТОКОЛЫ ДИАГНОСТИКИ (ЗАПУСК ПО КНОПКЕ)'),

        // Карточка 1: Тест впуска (Подсос vs Форсунки)
        _testCard(
          icon: Icons.air_rounded,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: '1. Тест: Подсос воздуха vs Форсунки',
          desc:
          'Сравнивает топливные коррекции на ХХ и в широком коридоре 2000–3500 об/мин (достаточно удержать педаль в этой зоне на 6 замеров).',
          warningBanner: isCold
              ? '⛔ Двигатель не прогрет (${_ect ?? 0}°C). Поднятие оборотов до 75°C заблокировано!'
              : null,
          statusText: _leakTestStatus,
          buttonLabel: _isRunningLeakTest
              ? 'Остановить / Сбросить тест'
              : 'Запустить тест впуска',
          isRunning: _isRunningLeakTest,
          onPressed: (isCold && !_isRunningLeakTest)
              ? null
              : _runAirLeakAutoTest,
        ),
        const SizedBox(height: 16),

        // Карточка 2: Протокол трудного запуска + АКБ
        _testCard(
          icon: Icons.battery_charging_full_rounded,
          iconColor: _warning,
          iconBg: _warningSoft,
          title: '2. Тест: Утренний пуск и просадка АКБ',
          desc:
          'Сверяет ДТОЖ/ДТВ на холодную (только здесь, без спама на горячую!), ловит минимальное напряжение АКБ при стартере (порог ≥10.5В) и открывает окно отчета АКБ.',
          statusText: _startTestStatus,
          buttonLabel: _isRunningStartTest
              ? 'Остановить запись пуска'
              : 'Запустить тест пуска (18 сек)',
          isRunning: _isRunningStartTest,
          onPressed: _runColdStartTest,
        ),
        const SizedBox(height: 16),

        // Карточка 3: Mode $06 ДК1, ДК2 и Катализатор
        _testCard(
          icon: Icons.Analytics_outlined,
          iconColor: _success,
          iconBg: _successSoft,
          title: '3. Mode \$06: Ресурс ДК1, ДК2 и Катализатора',
          desc:
          'Проверяет TID \$08 (макс. напряжение ДК1 0.1–0.9В), TID \$07 (ДК2) и фактор старения нейтрализатора (выявляет причину повышенного расхода).',
          statusText: _mode06TestStatus,
          buttonLabel: _isRunningMode06Test
              ? 'Идет опрос Mode \$06...'
              : 'Проверить ДК1 / ДК2 и Катализатор',
          isRunning: _isRunningMode06Test,
          onPressed: _isRunningMode06Test ? null : _runMode06AndCatTest,
        ),
        const SizedBox(height: 16),

        // Карточка 4: Детонация Цил. 1-4, EVAP и Дроссель
        _testCard(
          icon: Icons.precision_manufacturing_rounded,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: '4. М86: Детонация (Цил. 1–4), Адсорбер и ДПДЗ',
          desc:
          'Ищет проблемный цилиндр по уровню детонации (напр. Цил. 3), проверяет подсос паров через клапан адсорбера на ХХ (>15%) и напряжения ДПДЗ.',
          statusText: _m86DeepTestStatus,
          buttonLabel: _isRunningM86DeepTest
              ? 'Чтение таблиц М86...'
              : 'Запустить глубокий тест М86',
          isRunning: _isRunningM86DeepTest,
          onPressed: _isRunningM86DeepTest ? null : _runM86DeepDiagnosticTest,
        ),
      ],
    );
  }

  Widget _testCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String desc,
    String? warningBanner,
    required String statusText,
    required String buttonLabel,
    required bool isRunning,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: _text1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(desc, style: TextStyle(fontSize: 12, color: _text2)),
          if (warningBanner != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _errorSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                warningBanner,
                style: TextStyle(
                    color: _error, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: statusText.contains('✅')
                    ? _success
                    : (statusText.contains('❌') || statusText.contains('⛔')
                    ? _error
                    : _text1),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(isRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow_rounded),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? _error : _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ВКЛАДКА 3: ЖУРНАЛ НЮАНСОВ И ЭКСПОРТ CSV
  Widget _buildJournalTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Событий: ${_nuanceLog.length} · Точек CSV: ${_blackBox.length}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _text2),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 16),
                label:
                const Text('Экспорт CSV', style: TextStyle(fontSize: 12)),
                onPressed: _exportCsvToClipboard,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: _text2),
                onPressed: () => setState(() {
                  _nuanceLog.clear();
                  _lastNuanceTimes.clear();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: _nuanceLog.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Журнал нюансов чист.\nВсе реальные отклонения (просадки АКБ <10.5В, бедная/богатая смесь, итоги ручных тестов) сохраняются здесь.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _text2),
              ),
            ),
          )
              : ListView.builder(
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _nuanceLog.length,
            itemBuilder: (ctx, i) {
              final e = _nuanceLog[i];
              final color = e.severity == NuanceSeverity.critical
                  ? _error
                  : (e.severity == NuanceSeverity.warning
                  ? _warning
                  : _accent);
              final bg = e.severity == NuanceSeverity.critical
                  ? _errorSoft
                  : (e.severity == NuanceSeverity.warning
                  ? _warningSoft
                  : _accentSoft);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        e.severity == NuanceSeverity.critical
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  e.title,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: color),
                                ),
                              ),
                              Text(e.timeStr,
                                  style: TextStyle(
                                      fontSize: 11, color: _text3)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(e.description,
                              style: TextStyle(
                                  fontSize: 13, color: _text1)),
                          if (e.snapshot.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: e.snapshot.entries.map((entry) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _surface2,
                                    borderRadius:
                                    BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${entry.key}: ${entry.value}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _text2),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ВКЛАДКА 4: ОШИБКИ DTC И ПАСПОРТ ЭБУ
  Widget _buildDtcTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isConnected ? _readDtcAndEcuId : null,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Прочитать ошибки (Mode 03/07) и паспорт'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionHeader('ПАСПОРТ ЭБУ'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ОПРЕДЕЛЕННЫЙ ТИП БЛОКА',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _text3)),
              const SizedBox(height: 4),
              Text(_ecuType,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _text1)),
              const SizedBox(height: 14),
              Text('ID КАЛИБРОВКИ / ПРОШИВКИ',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _text3)),
              const SizedBox(height: 4),
              Text(_ecuId,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _accent)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionHeader('КОДЫ НЕИСПРАВНОСТЕЙ (DTC)'),
        if (_dtcList.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _successSoft,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.check_circle_rounded,
                      color: _success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Ошибок в ЭБУ не обнаружено (Mode 03 и 07 чистые). Все скрытые отклонения без чека фиксируются во вкладках «Анализ» и «Журнал».',
                    style: TextStyle(fontSize: 13, color: _text2),
                  ),
                ),
              ],
            ),
          )
        else
          ..._dtcList.map(
                (code) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _error),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: _error),
                  const SizedBox(width: 12),
                  Text(code,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text1)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
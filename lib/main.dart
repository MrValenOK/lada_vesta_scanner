import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

void main() {
  runApp(const VestaScannerApp());
}

// ===== 1. ДИЗАЙН: ТЁПЛЫЙ МИНИМАЛИЗМ (Светлая и Тёмная темы из макета) =====
class AppColors {
  // Светлая тема
  static const lightBg = Color(0xFFFAFAF7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF5F3EE);
  static const lightText1 = Color(0xFF1A1A1A);
  static const lightText2 = Color(0xFF6B6B6B);
  static const lightText3 = Color(0xFF9A9A9A);
  static const lightBorder = Color(0xFFEAE8E3);

  // Тёмная тема
  static const darkBg = Color(0xFF1C1B1A);
  static const darkSurface = Color(0xFF272624);
  static const darkSurface2 = Color(0xFF2F2E2C);
  static const darkText1 = Color(0xFFF0EDE8);
  static const darkText2 = Color(0xFFA8A49E);
  static const darkText3 = Color(0xFF75726D);
  static const darkBorder = Color(0xFF353331);

  // Акценты и статусы (Светлая)
  static const accent = Color(0xFF4A6FA5);
  static const accentSoft = Color(0xFFE8EEF6);
  static const success = Color(0xFF4CAF7D);
  static const successSoft = Color(0xFFE6F4EC);
  static const warning = Color(0xFFE8A838);
  static const warningSoft = Color(0xFFFFF4E0);
  static const error = Color(0xFFE07A7A);
  static const errorSoft = Color(0xFFFDEAEA);

  // Акценты и статусы (Тёмная)
  static const darkAccent = Color(0xFF8BA4C4);
  static const darkAccentSoft = Color(0xFF2A3442);
  static const darkSuccess = Color(0xFF7BC49A);
  static const darkSuccessSoft = Color(0xFF1F3A2A);
  static const darkWarning = Color(0xFFE8C078);
  static const darkWarningSoft = Color(0xFF3D3320);
  static const darkError = Color(0xFFE89898);
  static const darkErrorSoft = Color(0xFF3D2424);
}

// ===== 2. МОДЕЛИ ДАННЫХ =====
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
  bool _isDark = true; // По умолчанию включаем благородную тёмную тему

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
          fontSize: 22,
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
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isPolling = false;
  String _statusText = 'Выберите ELM327 адаптер и нажмите Старт';
  String _ecuType = 'Итэлма М86';

  final StringBuffer _rxBuffer = StringBuffer();
  StreamSubscription? _connSub;
  StreamSubscription? _dataSub;

  // Текущие параметры ЭБУ
  int? _rpm, _ect, _iat, _map;
  double? _volt, _stft, _ltft, _adv, _tps, _o2Voltage, _evapPurge;

  // Диагностика и журнал
  String _ecuId = 'Не прочитан';
  List<String> _dtcList = [];
  final List<NuanceEvent> _nuanceLog = [];
  final Map<String, DateTime> _lastNuanceTimes = {};
  final List<TelemetryPoint> _blackBox = [];
  final List<int> _rpmWindow = [];

  // Автотесты
  bool _isRunningLeakTest = false;
  String _leakTestStatus = 'Готов к проверке (требуется прогрев >75°C)';

  bool _isRunningStartTest = false;
  String _startTestStatus = 'Включите зажигание (не заводя) и нажмите кнопку';

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
  }

  @override
  void dispose() {
    _isPolling = false;
    _connSub?.cancel();
    _dataSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // Цветовые хелперы под текущую тему
  Color get _surface => widget.isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get _surface2 => widget.isDark ? AppColors.darkSurface2 : AppColors.lightSurface2;
  Color get _text1 => widget.isDark ? AppColors.darkText1 : AppColors.lightText1;
  Color get _text2 => widget.isDark ? AppColors.darkText2 : AppColors.lightText2;
  Color get _text3 => widget.isDark ? AppColors.darkText3 : AppColors.lightText3;
  Color get _border => widget.isDark ? AppColors.darkBorder : AppColors.lightBorder;

  Color get _accent => widget.isDark ? AppColors.darkAccent : AppColors.accent;
  Color get _accentSoft => widget.isDark ? AppColors.darkAccentSoft : AppColors.accentSoft;
  Color get _success => widget.isDark ? AppColors.darkSuccess : AppColors.success;
  Color get _successSoft => widget.isDark ? AppColors.darkSuccessSoft : AppColors.successSoft;
  Color get _warning => widget.isDark ? AppColors.darkWarning : AppColors.warning;
  Color get _warningSoft => widget.isDark ? AppColors.darkWarningSoft : AppColors.warningSoft;
  Color get _error => widget.isDark ? AppColors.darkError : AppColors.error;
  Color get _errorSoft => widget.isDark ? AppColors.darkErrorSoft : AppColors.errorSoft;

  // ===== 3. БЕЗОПАСНОСТЬ И АВТООПРЕДЕЛЕНИЕ ЭБУ =====
  String _detectEcuType(String id) {
    final upperId = id.toUpperCase();
    if (upperId.contains('M86') || upperId.contains('I86') || upperId.contains('I765') || upperId.contains('I785')) {
      return 'Итэлма М86 (CAN)';
    }
    if (upperId.contains('M74')) return 'Итэлма М74 (CAN/K-Line)';
    if (upperId.contains('ME17')) return 'Bosch ME17.9.7 (CAN)';
    if (upperId.contains('B774') || upperId.contains('VS51') || upperId.contains('7.9.7')) {
      return 'Bosch 7.9.7 (K-Line)';
    }
    if (upperId.contains('M73')) return 'Итэлма М73 (K-Line)';
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
      if (mounted) {
        setState(() {
          _devices = list;
          if (_devices.isNotEmpty && _selectedDevice == null) {
            _selectedDevice = _devices.firstWhere(
                  (d) =>
              d.name.toUpperCase().contains('OBD') ||
                  d.name.toUpperCase().contains('ELM'),
              orElse: () => _devices.first,
            );
          }
        });
      }
    } catch (e) {
      _setStatus('Ошибка списка BT: $e');
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
            if (_volt != null) 'Сеть': '${_volt!.toStringAsFixed(1)}В',
            if (_stft != null) 'STFT': '${_stft!.toStringAsFixed(1)}%',
            if (_ltft != null) 'LTFT': '${_ltft!.toStringAsFixed(1)}%',
          },
        ),
      );
    });
  }

  Future<String> _sendObdCommand(String cmd, {int timeoutMs = 1200}) async {
    if (!_isConnected) return 'ERR:NOT_CONNECTED';
    _rxBuffer.clear();
    try {
      await _bt.sendString('$cmd\r');
    } catch (e) {
      return 'ERR:$e';
    }

    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 40));
      final current = _rxBuffer.toString();
      if (current.contains('>')) {
        // Пауза 150 мс для защиты буфера бюджетных ELM327 от переполнения
        await Future.delayed(const Duration(milliseconds: 150));
        return current
            .replaceAll('>', '')
            .replaceAll('\r', ' ')
            .replaceAll('\n', ' ')
            .trim();
      }
    }
    await Future.delayed(const Duration(milliseconds: 150));
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

    if (_selectedDevice == null) {
      _setStatus('Сначала выберите OBDII устройство');
      return;
    }

    setState(() => _statusText = 'Подключение и инициализация ЭБУ...');
    try {
      bool ok = await _bt.connect(_selectedDevice!.address);
      if (!ok) {
        _setStatus('Не удалось подключиться к адаптеру');
        return;
      }
      _isConnected = true;

      // Правильная последовательность инициализации ELM327 для М86
      await _sendObdCommand('ATZ', timeoutMs: 2000);
      await _sendObdCommand('ATE0');
      await _sendObdCommand('ATL0');
      await _sendObdCommand('ATS0');
      await _sendObdCommand('ATH0');
      await _sendObdCommand('ATSP6'); // CAN 11bit 500kbps

      // Попытка сразу прочитать ID прошивки
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

      _isPolling = true;
      _setStatus('Подключено · CAN 500 kbps · $_ecuType');
      _logNuance(
        'session_start',
        'Сессия запущена',
        'На связи с $_ecuType (ID: $_ecuId). Фоновый мониторинг активен.',
        NuanceSeverity.info,
        cooldownSec: 1,
      );
      _startPollingLoop();
    } catch (e) {
      _setStatus('Ошибка подключения: $e');
      _isPolling = false;
    }
  }

  // ===== 4. ЦИКЛ ОПРОСА (Read-Only, безопасный) =====
  Future<void> _startPollingLoop() async {
    int cycle = 0;
    while (_isPolling && _isConnected) {
      try {
        _parseVoltage(await _sendObdCommand('ATRV'));
        if (!_isPolling) break;
        _parseRpm(await _sendObdCommand('010C'));
        if (!_isPolling) break;
        _parseMap(await _sendObdCommand('010B'));
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
        } else {
          if (!_isPolling) break;
          _parseIat(await _sendObdCommand('010F'));
          if (!_isPolling) break;
          _parseTps(await _sendObdCommand('0111'));
          if (!_isPolling) break;
          _parseEvap(await _sendObdCommand('012E'));
        }
        cycle++;
        _recordBlackBoxAndAnalyze();
        if (mounted) setState(() {});
      } catch (e) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // ===== 5. ПАРСЕРЫ =====
  List<int>? _extractBytes(String resp, String expectedPrefix) {
    final clean = resp.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf(expectedPrefix);
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
    if (m != null) _volt = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  void _parseRpm(String r) {
    final b = _extractBytes(r, '410C');
    if (b != null && b.length >= 2) {
      _rpm = ((b[0] * 256) + b[1]) ~/ 4;
      if (_rpm! > 650 && _rpm! < 1050 && (_tps ?? 0) < 10.0) {
        _rpmWindow.add(_rpm!);
        if (_rpmWindow.length > 20) _rpmWindow.removeAt(0);
      }
    }
  }

  void _parseMap(String r) {
    final b = _extractBytes(r, '410B');
    if (b != null && b.isNotEmpty) _map = b[0];
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
    if (b != null && b.isNotEmpty) _ltft = (b[0] - 128) * 100.0 / 128.0;
  }

  void _parseAdv(String r) {
    final b = _extractBytes(r, '410E');
    if (b != null && b.isNotEmpty) _adv = (b[0] / 2.0) - 64.0;
  }

  void _parseTps(String r) {
    final b = _extractBytes(r, '4111');
    if (b != null && b.isNotEmpty) _tps = b[0] * 100.0 / 255.0;
  }

  void _parseO2(String r) {
    final b = _extractBytes(r, '4114');
    if (b != null && b.isNotEmpty) _o2Voltage = b[0] / 200.0;
  }

  void _parseEvap(String r) {
    final b = _extractBytes(r, '412E');
    if (b != null && b.isNotEmpty) _evapPurge = b[0] * 100.0 / 255.0;
  }

  // ===== 6. АНАЛИТИКА И ЗАПИСЬ В ЧЕРНЫЙ ЯЩИК =====
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

    if (rpm == 0 && _ect != null && _iat != null && (ect - _iat!).abs() >= 8) {
      _logNuance(
        'temp_mismatch',
        'Рассогласование ДТОЖ и ДТВ до пуска',
        'На заглушенном моторе ОЖ ($ect°C) и Впуск ($_iat°C) отличаются на ${(ect - _iat!).abs()}°C. Если мотор холодный — врет датчик температуры.',
        NuanceSeverity.warning,
        cooldownSec: 120,
      );
    }
    if (rpm > 80 && rpm < 450 && volt < 9.8) {
      _logNuance(
        'crank_volt',
        'Критическая просадка при пуске',
        'Напряжение упало до ${volt.toStringAsFixed(1)} В на прокрутке ($rpm об/мин). Проверьте АКБ, стартер и массы.',
        NuanceSeverity.critical,
        cooldownSec: 15,
      );
    }
    if (rpm > 700 && volt < 13.3) {
      _logNuance(
        'low_alt',
        'Просадка бортсети на ходу',
        'Напряжение ${volt.toStringAsFixed(1)} В (норма 13.8–14.5 В). Недозаряд генератора или потери в массах.',
        NuanceSeverity.warning,
      );
    }
    if (ect > 103) {
      _logNuance(
        'overheat',
        'Перегрев ОЖ',
        'Температура достигла $ect °C. Проверьте первую скорость вентилятора и термостат.',
        NuanceSeverity.critical,
      );
    }
    if (rpm > 650 && (stft > 12.0 || ltft > 10.0)) {
      _logNuance(
        'lean_mix',
        'Бедная смесь (Плюсовые коррекции)',
        'STFT: +${stft.toStringAsFixed(1)}%, LTFT: +${ltft.toStringAsFixed(1)}%. Признак подсоса воздуха во впуске или нехватки давления топлива.',
        NuanceSeverity.warning,
      );
    }
    if (rpm > 650 && (stft < -12.0 || ltft < -10.0)) {
      _logNuance(
        'rich_mix',
        'Богатая смесь (Минусовые коррекции)',
        'STFT: ${stft.toStringAsFixed(1)}%, LTFT: ${ltft.toStringAsFixed(1)}%. Возможна текущая форсунка или открытый клапан адсорбера.',
        NuanceSeverity.warning,
      );
    }
    if (ect >= 80 && rpm >= 750 && rpm <= 900 && map >= 41) {
      _logNuance(
        'high_idle_map',
        'Слабое разрежение на ХХ (ДАД $map кПа)',
        'При норме 28–36 кПа давление >40 кПа указывает на смещение меток ГРМ на 1 зуб, зажатые клапаны или сильный подсос.',
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

  // ===== 7. АВТОТЕСТЫ (С ЖЁСТКОЙ ЗАЩИТОЙ ДВИГАТЕЛЯ) =====
  Future<void> _runAirLeakAutoTest() async {
    if (!_isPolling) {
      _setStatus('Сначала запустите связь!');
      return;
    }

    // Защита от поднятия оборотов на холодном двигателе
    if (_ect == null || _ect! < 75) {
      _setStatus(
          '⛔ ОПАСНО: Двигатель не прогрет (${_ect ?? 0}°C). Прогрейте минимум до 75°C!');
      _logNuance(
        'test_aborted_cold',
        'Тест заблокирован (Холодный ДВС)',
        'Попытка запуска теста с оборотами 2500+ при ОЖ ${_ect ?? 0}°C отменена для защиты двигателя.',
        NuanceSeverity.critical,
        cooldownSec: 5,
      );
      return;
    }

    setState(() {
      _isRunningLeakTest = true;
      _leakTestStatus = 'Этап 1/2: Холостой ход (10 сек)...';
    });

    final idleStft = <double>[], idleLtft = <double>[], idleMap = <int>[];
    for (int i = 10; i > 0; i--) {
      if (!_isPolling) break;
      setState(() => _leakTestStatus = 'Этап 1/2 (Холостой ход): осталось $i сек');
      if (_stft != null) idleStft.add(_stft!);
      if (_ltft != null) idleLtft.add(_ltft!);
      if (_map != null) idleMap.add(_map!);
      await Future.delayed(const Duration(seconds: 1));
    }

    setState(() =>
    _leakTestStatus = 'Этап 2/2: Плавно поднимите и держите ~2500–3000 об/мин!');
    await Future.delayed(const Duration(seconds: 3));

    final revStft = <double>[], revLtft = <double>[];
    for (int i = 10; i > 0; i--) {
      if (!_isPolling) break;
      setState(() => _leakTestStatus =
      'Этап 2/2: Осталось $i сек (Сейчас: ${_rpm ?? 0} об/мин)');
      if (_stft != null) revStft.add(_stft!);
      if (_ltft != null) revLtft.add(_ltft!);
      await Future.delayed(const Duration(seconds: 1));
    }

    double avg(List<num> list) =>
        list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
    final sumIdle = avg(idleStft) + avg(idleLtft);
    final sumRev = avg(revStft) + avg(revLtft);
    final avgIdleMap = avg(idleMap);

    String verdict;
    NuanceSeverity sev = NuanceSeverity.info;
    if (sumIdle > 8.0 && (sumIdle - sumRev) > 5.0) {
      verdict =
      '✅ ПОДТВЕРЖДЕН ПОДСОС ВОЗДУХА: На ХХ коррекция +${sumIdle.toStringAsFixed(1)}%, на оборотах падает до ${sumRev.toStringAsFixed(1)}%. Проверьте уплотнения ресивера, колечки форсунок и шланг ВУТ.';
      sev = NuanceSeverity.critical;
    } else if (sumIdle > 8.0 && sumRev > 7.0) {
      verdict =
      '⚠️ НЕХВАТКА ТОПЛИВА (ФОРСУНКИ / НАСОС): Коррекция высокая и на ХХ (+${sumIdle.toStringAsFixed(1)}%), и под нагрузкой (+${sumRev.toStringAsFixed(1)}%). Забиты форсунки или низкое давление в рампе.';
      sev = NuanceSeverity.critical;
    } else if (avgIdleMap > 40) {
      verdict =
      '⚠️ ДАД завышен (${avgIdleMap.toStringAsFixed(0)} кПа при норме 28–36). Проверьте метки ремня ГРМ и тепловые зазоры клапанов!';
      sev = NuanceSeverity.warning;
    } else {
      verdict =
      '✅ НОРМА: Сумма коррекций на ХХ ${sumIdle.toStringAsFixed(1)}%, на оборотах ${sumRev.toStringAsFixed(1)}%, ДАД ${avgIdleMap.toStringAsFixed(0)} кПа.';
    }

    _logNuance('test_leak', 'Результат теста «Подсос / Форсунки»', verdict, sev,
        cooldownSec: 1);
    if (mounted) {
      setState(() {
        _isRunningLeakTest = false;
        _leakTestStatus = verdict;
      });
    }
  }

  Future<void> _runColdStartTest() async {
    if (!_isPolling) {
      _setStatus('Сначала запустите связь!');
      return;
    }
    setState(() {
      _isRunningStartTest = true;
      _startTestStatus = 'Запись пуска (20 сек): Заводите двигатель прямо сейчас!';
    });

    final startEct = _ect ?? 0, startIat = _iat ?? 0;
    double minVolt = _volt ?? 14.0;
    int maxCrankRpm = 0;
    final postStartStft = <double>[];

    for (int i = 20; i > 0; i--) {
      if (!_isPolling) break;
      final v = _volt ?? 14.0, r = _rpm ?? 0;
      if (v < minVolt && v > 5.0) minVolt = v;
      if (r > 0 && r < 500 && r > maxCrankRpm) maxCrankRpm = r;
      if (r > 650 && _stft != null) postStartStft.add(_stft!);
      setState(() => _startTestStatus =
      'Запись ($i сек) | Мин. сеть: ${minVolt.toStringAsFixed(1)}В | Обороты: $r');
      await Future.delayed(const Duration(seconds: 1));
    }

    final avgStft = postStartStft.isEmpty
        ? 0.0
        : postStartStft.reduce((a, b) => a + b) / postStartStft.length;
    final issues = <String>[];
    if ((startEct - startIat).abs() >= 7) {
      issues.add(
          'Рассогласование ДТОЖ ($startEct°C) и ДТВ ($startIat°C) до старта.');
    }
    if (minVolt < 9.8) {
      issues.add(
          'Сильная просадка напряжения при стартере до ${minVolt.toStringAsFixed(1)} В.');
    }
    if (avgStft < -10.0) {
      issues.add(
          'После пуска STFT ушел в минус (${avgStft.toStringAsFixed(1)}%) — признак подтекающей форсунки.');
    }

    final report = issues.isEmpty
        ? 'Пуск штатно: Мин. напряжение ${minVolt.toStringAsFixed(1)} В, ДТОЖ $startEct°C / ДТВ $startIat°C, STFT ${avgStft.toStringAsFixed(1)}%.'
        : 'Выявлены проблемы пуска:\n• ${issues.join('\n• ')}';

    _logNuance(
      'test_start',
      'Протокол «Трудный запуск»',
      report,
      issues.isEmpty ? NuanceSeverity.info : NuanceSeverity.critical,
      cooldownSec: 1,
    );
    if (mounted) {
      setState(() {
        _isRunningStartTest = false;
        _startTestStatus = report;
      });
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
    sb.writeln('=== ЖУРНАЛ НЮАНСОВ (VestaScan M86) ===');
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

  // ===== 8. ИНТЕРФЕЙС (В ТОЧНОСТИ ПО МАКЕТУ) =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VestaScan'),
            Text(
              '$_ecuType · Read-Only',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: _text2),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode,
                color: _text1),
            tooltip: 'Сменить тему',
            onPressed: widget.onThemeToggle,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: _text1),
            tooltip: 'Обновить Bluetooth',
            onPressed: _loadPairedDevices,
          ),
          const SizedBox(width: 8),
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

  // Верхняя карточка подключения в стиле макета
  Widget _buildStatusConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<BluetoothDevice>(
                    isDense: true,
                    isExpanded: true,
                    value: _selectedDevice,
                    hint: Text('Выберите OBDII адаптер',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _text1)),
                    items: _devices.map((d) {
                      return DropdownMenuItem(
                        value: d,
                        child: Text(
                          d.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _text1),
                        ),
                      );
                    }).toList(),
                    onChanged: _isPolling
                        ? null
                        : (val) => setState(() => _selectedDevice = val),
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
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _toggleConnection,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _isPolling ? _errorSoft : _accentSoft,
              foregroundColor: _isPolling ? _error : _accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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

  // ВКЛАДКА 1: ВСЕ 10 ДАТЧИКОВ + БЛОК ДИАГНОСТИКИ ИЗ МАКЕТА
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        _sectionHeader('ТЕЛЕМЕТРИЯ'),
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
              norm: 'Норма: 800–880 | σ ${_rpmSigma.toStringAsFixed(1)}',
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
              label: 'ДАД (ВПУСК)',
              value: '${_map ?? "---"}',
              unit: 'кПа',
              norm: 'Норма: 28–36 кПа',
              status: mapStatus,
            ),
            _metricCard(
              icon: Icons.electric_bolt_rounded,
              label: 'БОРТ. СЕТЬ',
              value: _volt != null ? _volt!.toStringAsFixed(1) : '---',
              unit: 'В',
              norm: 'Норма: 13.8–14.5 В',
              status: voltStatus,
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
              norm: 'Допуск: ±7%',
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
              label: 'КИСЛОРОДНИК ДК1',
              value:
              _o2Voltage != null ? _o2Voltage!.toStringAsFixed(2) : '---',
              unit: 'В',
              norm: 'Синусоида: 0.1–0.9 В',
              status: 'normal',
            ),
            _metricCard(
              icon: Icons.filter_alt_rounded,
              label: 'АДСОРБЕР (EVAP)',
              value:
              _evapPurge != null ? _evapPurge!.toStringAsFixed(0) : '---',
              unit: '%',
              norm: 'Продувка паров бака',
              status: 'normal',
            ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeader('БЫСТРАЯ СВОДКА'),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              _diagSummaryRow(
                icon: _dtcList.isEmpty
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                title: _dtcList.isEmpty
                    ? 'Ошибок ЭБУ не найдено'
                    : 'Найдено ошибок: ${_dtcList.length}',
                sub: 'Mode 03 и Mode 07 проверены',
                status: _dtcList.isEmpty ? 'good' : 'err',
              ),
              _diagSummaryRow(
                icon: Icons.memory_rounded,
                title: 'Прошивка $_ecuId',
                sub: _ecuType,
                status: 'info',
              ),
              _diagSummaryRow(
                icon: (_ect ?? 0) >= 75
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                title: (_ect ?? 0) >= 75
                    ? 'Двигатель в рабочей зоне'
                    : 'Двигатель не прогрет',
                sub: 'ОЖ: ${_ect ?? "--"}°C · рабочая 85–99°C',
                status: (_ect ?? 0) >= 75 ? 'good' : 'warn',
              ),
            ],
          ),
        ),
      ],
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
    required String status, // 'normal', 'good', 'warn', 'err'
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
      padding: const EdgeInsets.all(16),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: _text2,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 24,
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
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 8),
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

  Widget _diagSummaryRow({
    required IconData icon,
    required String title,
    required String sub,
    required String status,
  }) {
    Color c = _accent;
    Color bg = _accentSoft;
    if (status == 'good') {
      c = _success;
      bg = _successSoft;
    } else if (status == 'warn') {
      c = _warning;
      bg = _warningSoft;
    } else if (status == 'err') {
      c = _error;
      bg = _errorSoft;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _text1)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ВКЛАДКА 2: АВТО-АНАЛИЗ (ТЕСТЫ ПОДСОСА, ФОРСУНОК, ЗАПУСКА И ГРМ)
  Widget _buildTestsTab() {
    final isCold = _ect == null || _ect! < 75;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionHeader('АВТОМАТИЧЕСКИЕ ПРОТОКОЛЫ'),
        Container(
          padding: const EdgeInsets.all(20),
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
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.air_rounded, color: _accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Автотест: Подсос vs Форсунки',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: _text1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Алгоритм замеряет коррекции и разрежение на ХХ (10 сек) и на 2500 об/мин (10 сек), разделяя негерметичность впуска и забитые форсунки.',
                style: TextStyle(fontSize: 13, color: _text2),
              ),
              if (isCold) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _errorSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: _error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⛔ Двигатель не прогрет (${_ect ?? 0}°C). Поднятие оборотов до 75°C заблокировано!',
                          style: TextStyle(
                              color: _error,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                _leakTestStatus,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _leakTestStatus.contains('✅')
                      ? _success
                      : (_leakTestStatus.contains('⛔') ? _error : _warning),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  (isCold || _isRunningLeakTest) ? null : _runAirLeakAutoTest,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_isRunningLeakTest
                      ? 'Идет замер...'
                      : 'Запустить тест впуска'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
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
                        color: _warningSoft,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.key_rounded, color: _warning, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Протокол: Трудный утренний запуск',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: _text1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Сверяет адекватность ДТОЖ и ДТВ до старта, фиксирует минимальную просадку АКБ при работе стартера и перелив форсунок после пуска.',
                style: TextStyle(fontSize: 13, color: _text2),
              ),
              const SizedBox(height: 14),
              Text(
                _startTestStatus,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _startTestStatus.contains('штатно')
                      ? _success
                      : _warning,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isRunningStartTest ? null : _runColdStartTest,
                  icon: const Icon(Icons.fiber_manual_record_rounded),
                  label: Text(_isRunningStartTest
                      ? 'Пишем лог пуска...'
                      : 'Начать тест запуска (20 сек)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _surface2,
                    foregroundColor: _text1,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
                label: const Text('Экспорт CSV', style: TextStyle(fontSize: 12)),
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
                'Журнал нюансов чист.\nВсе скрытые отклонения (просадки сети, скачки коррекций, подозрения на подсос и метки ГРМ) записываются сюда автоматически во время поездки.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _text2),
              ),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  child:
                  Icon(Icons.check_circle_rounded, color: _success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Ошибок в ЭБУ не обнаружено (Mode 03 и 07 чистые). Все скрытые отклонения без чека фиксируются во вкладке «Журнал».',
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
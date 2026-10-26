import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:url_launcher/url_launcher.dart';

// ===== КОНФИГУРАЦИЯ ВЕРСИИ И OTA (GITHUB RELEASES) =====
const String kAppVersion = '1.1.7';
const String kGithubRepo = 'MrValenOK/lada_vesta_scanner';
const String kDirectApkFallbackUrl =
    'https://github.com/$kGithubRepo/releases/latest/download/app-debug.apk';

void main() => runApp(const VestaScannerApp());

// ===== 1. ЗАВОДСКИЕ НОРМАТИВЫ АВТОВАЗА (ТИ 3100.25100.12056, ТАБЛ. 2.4-01) =====
class M86Specs {
  static const int idleRpmTarget = 840;
  static const int idleRpmMin = 780;
  static const int idleRpmMax = 900;
  static const double idleTpsMax = 4.5;
  static const int ectWarmMin = 90;
  static const int ectFan1On = 102;
  static const int ectFan2On = 103;
  static const int ectClosedLoopMin = 75;

  static const int idleMapMinKpa = 28;
  static const int idleMapMaxKpa = 41;
  static const int dfcoMapCutoffKpa = 25;

  static const double altVoltMin = 13.0;
  static const double altVoltMax = 14.5;
  static const double crankVoltMinHealthy = 10.5;
  static const double crankVoltCritical = 9.8;

  static const double trimNormLimitPct = 15.0;
  static const double trimHardLimitPct = 25.0;
  static const double idleAdaptNormPct = 2.5;
  static const double evapIdleMaxPct = 12.0;

  static const double throttleLeakMinKgH = 3.0;
  static const double throttleLeakMaxKgH = 5.0;

  static const double o2ColdRefMinV = 1.18;
  static const double o2ColdRefMaxV = 1.78;
  static const double udkLowThresholdV = 0.25;
  static const double udkHighThresholdV = 0.78;
  static const double udkMaxPeriodSec = 1.8;
  static const double catAgingMaxNorm = 0.45;

  static const double tpsSumTargetV = 5.0;
  static const double tpsSumToleranceV = 0.12;
}

// ===== 2. ДИЗАЙН-СИСТЕМА 2026: ТЁПЛЫЙ МИНИМАЛИЗМ + ВЫСОКИЙ КОНТРАСТ =====
class AppColors {
  static const lightBg = Color(0xFFF7F5F0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFEDEAE2);
  static const lightText1 = Color(0xFF161514);
  static const lightText2 = Color(0xFF57544E);
  static const lightText3 = Color(0xFF85817A);
  static const lightBorder = Color(0xFFE2DDD3);

  static const darkBg = Color(0xFF161514);
  static const darkSurface = Color(0xFF21201E);
  static const darkSurface2 = Color(0xFF2B2927);
  static const darkText1 = Color(0xFFF5F2EB);
  static const darkText2 = Color(0xFFB5B0A6);
  static const darkText3 = Color(0xFF7D7970);
  static const darkBorder = Color(0xFF33312E);

  static const accent = Color(0xFF3B669E);
  static const accentSoft = Color(0xFFE5EEF9);
  static const success = Color(0xFF2E8B57);
  static const successSoft = Color(0xFFE3F3EA);
  static const warning = Color(0xFFD9822B);
  static const warningSoft = Color(0xFFFCF0E1);
  static const error = Color(0xFFC94A4A);
  static const errorSoft = Color(0xFFFCE8E8);

  static const darkAccent = Color(0xFF8AB4F8);
  static const darkAccentSoft = Color(0xFF243142);
  static const darkSuccess = Color(0xFF81C995);
  static const darkSuccessSoft = Color(0xFF1D3528);
  static const darkWarning = Color(0xFFFDD663);
  static const darkWarningSoft = Color(0xFF3B321E);
  static const darkError = Color(0xFFF28B82);
  static const darkErrorSoft = Color(0xFF3C2222);
}

// ===== 3. БАЗА КОДОВ М86 (ТИ 3100.25100.12056, ЛИСТ 31-34) =====
const Map<String, String> kM86DtcDatabase = {
  'P0030': 'Нагреватель УДК (ДК1 до нейтрализатора), цепь неисправна',
  'P0031': 'Нагреватель УДК (ДК1), замыкание цепи управления на массу',
  'P0032': 'Нагреватель УДК (ДК1), замыкание цепи на бортовую сеть',
  'P0036': 'Нагреватель ДДК (ДК2 после нейтрализатора), цепь неисправна',
  'P0037': 'Нагреватель ДДК (ДК2), замыкание цепи управления на массу',
  'P0038': 'Нагреватель ДДК (ДК2), замыкание цепи на бортовую сеть',
  'P0106': 'Цепь ДАД, выход сигнала из допустимого диапазона (расхождение ЦН > 200 мг/цикл)',
  'P0107': 'Цепь ДАД, низкий уровень сигнала (< 0,1 В)',
  'P0108': 'Цепь ДАД, высокий уровень сигнала (> 4,65 В)',
  'P0111': 'Цепь ДТВ, выход сигнала из допустимого диапазона (замена на 32°C)',
  'P0112': 'Цепь ДТВ, низкий уровень сигнала (< 0,25 В)',
  'P0113': 'Цепь ДТВ, высокий уровень сигнала (> 4,96 В)',
  'P0116': 'Цепь ДТОЖ, выход сигнала из допустимого диапазона',
  'P0117': 'Цепь ДТОЖ, низкий уровень сигнала (включается вентилятор ОЖ)',
  'P0118': 'Цепь ДТОЖ, высокий уровень сигнала (обрыв цепи, ~5 В)',
  'P0122': 'Цепь ДПДЗ А (дорожка 1), низкий уровень сигнала',
  'P0123': 'Цепь ДПДЗ А (дорожка 1), высокий уровень сигнала',
  'P0130': 'Управляющий датчик кислорода (ДК1) неисправен (зависание в 1,2..1,7 В)',
  'P0131': 'Цепь УДК (ДК1), низкий уровень выходного сигнала',
  'P0132': 'Цепь УДК (ДК1), высокий уровень выходного сигнала',
  'P0133': 'Цепь УДК (ДК1), медленный отклик на изменение состава смеси (период > 1,8 с)',
  'P0134': 'Цепь УДК (ДК1) неактивна (нет выхода из опорных 1,7 В)',
  'P0135': 'УДК (ДК1), нагреватель неисправен',
  'P0136': 'Диагностический датчик кислорода (ДК2) неисправен',
  'P0137': 'Цепь ДДК (ДК2), низкий уровень сигнала',
  'P0138': 'Цепь ДДК (ДК2), высокий уровень сигнала',
  'P0140': 'Цепь ДДК (ДК2) неактивна',
  'P0141': 'ДДК (ДК2), нагреватель неисправен',
  'P0171': 'Система топливоподачи слишком бедная (подсос воздуха / низкое давление ЭБН)',
  'P0172': 'Система топливоподачи слишком богатая (недогрев ОЖ / клапан КПА / форсунки)',
  'P0201': 'Форсунка цилиндра 1, цепь неисправна',
  'P0202': 'Форсунка цилиндра 2, цепь неисправна',
  'P0203': 'Форсунка цилиндра 3, цепь неисправна',
  'P0204': 'Форсунка цилиндра 4, цепь неисправна',
  'P0217': 'Температура двигателя выше допустимой (перегрев)',
  'P0222': 'Цепь ДПДЗ В (дорожка 2), низкий уровень сигнала',
  'P0223': 'Цепь ДПДЗ В (дорожка 2), высокий уровень сигнала',
  'P0300': 'Обнаружены случайные/множественные пропуски воспламенения',
  'P0301': 'Цилиндр 1: обнаружены пропуски воспламенения',
  'P0302': 'Цилиндр 2: обнаружены пропуски воспламенения',
  'P0303': 'Цилиндр 3: обнаружены пропуски воспламенения',
  'P0304': 'Цилиндр 4: обнаружены пропуски воспламенения',
  'P0327': 'Цепь датчика детонации (ДД), низкий уровень сигнала',
  'P0328': 'Цепь датчика детонации (ДД), высокий уровень сигнала',
  'P0335': 'Цепь ДПКВ неисправна (нет синхронизации 58+2 зубьев)',
  'P0336': 'Цепь ДПКВ, выход сигнала из допустимого диапазона',
  'P0340': 'Датчик фаз (ДФ распредвала) неисправен',
  'P0342': 'Цепь датчика фаз, низкий уровень сигнала',
  'P0343': 'Цепь датчика фаз, высокий уровень сигнала',
  'P0351': 'Катушка зажигания цилиндра 1, обрыв цепи управления (контакт X1.2/N5)',
  'P0352': 'Катушка зажигания цилиндра 2, обрыв цепи управления (контакт X1.2/N4)',
  'P0353': 'Катушка зажигания цилиндра 3, обрыв цепи управления (контакт X1.2/N3)',
  'P0354': 'Катушка зажигания цилиндра 4, обрыв цепи управления (контакт X1.2/N2)',
  'P0363': 'Пропуски воспламенения: отключена топливоподача в неработающих цилиндрах!',
  'P0422': 'Эффективность каталитического нейтрализатора ниже порога (фактор >= 0,45)',
  'P0441': 'Система улавливания паров бензина (СУПБ), неверный расход воздуха через КПА',
  'P0443': 'Клапан продувки адсорбера (КПА), цепь неисправна',
  'P0444': 'Клапан продувки адсорбера (КПА), обрыв цепи управления',
  'P0458': 'Клапан продувки адсорбера (КПА), замыкание цепи на массу',
  'P0459': 'Клапан продувки адсорбера (КПА), замыкание цепи на бортсеть',
  'P0480': 'Реле вентилятора 1 (малая скорость, 102°C, конт. X1.1/H2), цепь неисправна',
  'P0481': 'Реле вентилятора 2 (макс. скорость, 103°C, конт. X1.1/H3), цепь неисправна',
  'P0504': 'Выключатели А/В педали тормоза (конт. C4/C5), рассогласование сигналов (ограничение мощности!)',
  'P0513': 'Некорректный ключ иммобилизатора',
  'P0522': 'Цепь датчика давления масла, низкий уровень сигнала',
  'P0523': 'Цепь датчика давления масла, высокий уровень сигнала',
  'P0560': 'ПРИОРИТЕТ: Напряжение бортовой сети автомобиля неисправно (проверить Гл. реле)',
  'P0561': 'Напряжение бортовой сети нестабильно',
  'P0562': 'ПРИОРИТЕТ: Пониженное напряжение бортсети (контакты X1.1/L3, K3)',
  'P0563': 'Повышенное напряжение бортовой сети (регулятор генератора)',
  'P0627': 'Реле электробензонасоса (конт. X1.1/J4), цепь неисправна',
  'P0641': 'Цепь питания датчиков (+5 В), обрыв',
  'P0660': 'Клапан управления длиной каналов впуска (конт. X1.2/F2), обрыв цепи',
  'P1301': 'Цилиндр 1: пропуски воспламенения, критичные для нейтрализатора',
  'P1302': 'Цилиндр 2: пропуски воспламенения, критичные для нейтрализатора',
  'P1303': 'Цилиндр 3: пропуски воспламенения, критичные для нейтрализатора',
  'P1304': 'Цилиндр 4: пропуски воспламенения, критичные для нейтрализатора',
  'P1335': 'Мониторинг привода ДЗ: положение заслонки вне допустимого диапазона',
  'P1336': 'Мониторинг привода ДЗ: рассогласование датчиков А и В (сумма != 5,0 В)',
  'P1388': 'Мониторинг привода ДЗ: рассогласование датчиков А и В педали акселератора',
  'P1545': 'Привод дроссельной заслонки (ЭДП): положение вне допустимого диапазона',
  'P1558': 'Привод дроссельной заслонки: возвратная пружина неисправна',
  'P1559': 'Привод ДЗ: положение в состоянии покоя (Limp Home 6-7%) вне диапазона',
  'P1564': 'Адаптация нуля дроссельной заслонки прервана из-за низкого напряжения АКБ',
  'P1570': 'Иммобилизатор, цепь неисправна (обмен с ЦБКЭ)',
  'P1578': 'Адаптация положения нуля ДЗ вне допустимого диапазона',
  'P1579': 'Адаптация нуля ДЗ прервана из-за внешних условий (ОЖ <5°C или нажата педаль)',
  'P1602': 'Контроллер СУД: пропадание напряжения питания (отключение АКБ)',
  'P2100': 'Электропривод дроссельной заслонки, обрыв цепи управления',
  'P2101': 'Электропривод дроссельной заслонки, цепь управления неисправна',
  'P2135': 'Датчики А/В положения дроссельной заслонки: рассогласование (сумма != 5В)',
  'P2138': 'Датчики А/В педали акселератора: рассогласование (ДППА1 != 2 * ДППА2)',
  'P2176': 'Адаптация положения нуля дроссельной заслонки не выполнена (выполните 30с тест)',
  'P2187': 'Система топливоподачи слишком бедная на холостом ходу (подсос / жиклер 1,7 мм)',
  'P2188': 'Система топливоподачи слишком богатая на холостом ходу (КПА / недогрев ОЖ)',
  'P2270': 'ДДК (ДК2): отсутствие отклика на обогащение смеси',
  'P2271': 'ДДК (ДК2): отсутствие отклика на обеднение смеси',
  'U0001': 'ПРИОРИТЕТ: Шина CAN неисправна (проверить контакты X1.1/H4 и H5)',
  'U0002': 'Шина CAN: общая неисправность обмена',
  'U0009': 'ПРИОРИТЕТ: Шина CAN — короткое замыкание линии CAN-L на CAN-H',
  'U0073': 'Шина CAN отключена',
  'U0121': 'Шина CAN: нет данных от контроллера АБС (нет сигнала скорости ДСА)',
  'U0122': 'Шина CAN: нет данных от контроллера ESP',
  'U0155': 'Шина CAN: нет данных от комбинации приборов',
  'U0167': 'Шина CAN: нет связи с иммобилизатором (ЦБКЭ)',
};

const Set<String> kPriorityCodes = {'U0001', 'U0009', 'P0560', 'P0562'};

// ===== 4. МОДЕЛИ И ISO-TP ПАРСЕР =====
enum NuanceSeverity { info, warning, critical }

enum TestStatus { pending, running, ok, warning, error }

class NuanceEvent {
  final String id;
  DateTime timestamp;
  NuanceSeverity severity;
  String title;
  String description;
  Map<String, String> snapshot;
  int hzCount;

  NuanceEvent({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.title,
    required this.description,
    required this.snapshot,
    this.hzCount = 1,
  });

  String get timeStr =>
      "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";

  Map<String, dynamic> toJson() => {
    'id': id,
    'ts': timestamp.toIso8601String(),
    'sev': severity.name,
    'title': title,
    'desc': description,
    'snap': snapshot,
    'hz': hzCount,
  };

  factory NuanceEvent.fromJson(Map<String, dynamic> j) {
    final sevName = (j['sev'] ?? 'info').toString();
    final sev = NuanceSeverity.values.firstWhere(
          (e) => e.name == sevName,
      orElse: () => NuanceSeverity.info,
    );
    final rawSnap = j['snap'] as Map<String, dynamic>? ?? {};
    return NuanceEvent(
      id: (j['id'] ?? '').toString(),
      timestamp:
      DateTime.tryParse((j['ts'] ?? '').toString()) ?? DateTime.now(),
      severity: sev,
      title: (j['title'] ?? '').toString(),
      description: (j['desc'] ?? '').toString(),
      snapshot: rawSnap.map((k, v) => MapEntry(k, v.toString())),
      hzCount: (j['hz'] as num?)?.toInt() ?? 1,
    );
  }
}

class TrimBin {
  final String label;
  final List<double> _samples = [];
  TrimBin(this.label);

  int get count => _samples.length;
  bool get isNotEmpty => _samples.isNotEmpty;
  List<double> get rawSamples => List.unmodifiable(_samples);

  void loadSamples(List<double> saved) {
    _samples
      ..clear()
      ..addAll(saved.take(90));
  }

  void addSample(double stft, double ltft) {
    if (stft.abs() > M86Specs.trimHardLimitPct + 5.0 ||
        ltft.abs() > M86Specs.trimHardLimitPct + 5.0) {
      return;
    }
    _samples.add(stft + ltft);
    if (_samples.length > 90) _samples.removeAt(0);
  }

  double get median {
    if (_samples.isEmpty) return 0.0;
    final sorted = List<double>.from(_samples)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  void clear() => _samples.clear();
}

// ISO 15765-2 парсер. Не блокирует кадры с байтом 7F внутри данных.
// Отсекает только реальный Negative Response (7F + код сервиса в начале).
class ObdParser {
  static List<int>? extractBytes(String resp, String expectedPrefix) {
    final upper = resp.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('ERROR') ||
        upper.contains('UNABLE') ||
        upper.contains('STOPPED') ||
        upper.contains('?')) {
      return null;
    }

    int? expectedTotalLen;
    final lines = upper.split(RegExp(r'[\r\n]+'));
    final cleanHexBuf = StringBuffer();

    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      var line = lines[lineIdx].trim();
      if (line.isEmpty || line.startsWith('SEARCHING')) continue;

      // 12-битный заголовок длины ISO-TP («01A», «024») идёт отдельной первой строкой
      if (lineIdx == 0 &&
          line.length == 3 &&
          RegExp(r'^[0-9A-F]{3}$').hasMatch(line)) {
        expectedTotalLen = int.tryParse(line, radix: 16);
        continue;
      }

      // Отрезаем префикс номера кадра ISO-TP ("0:", "1:", "2:", ...)
      final colonIdx = line.indexOf(':');
      if (colonIdx != -1 && colonIdx <= 2) {
        line = line.substring(colonIdx + 1).trim();
      }

      // Отрезаем CAN-ID заголовки вида 7E8
      if (line.startsWith('7E8')) {
        line = line.substring(3).trim();
      }

      final hexOnly = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      cleanHexBuf.write(hexOnly);
    }

    final clean = cleanHexBuf.toString();
    if (clean.isEmpty) return null;

    // Проверка Negative Response только в начале ответа
    final pref = expectedPrefix.toUpperCase();
    if (pref.length >= 2) {
      final respServiceByte = int.tryParse(pref.substring(0, 2), radix: 16);
      if (respServiceByte != null && respServiceByte >= 0x40) {
        final reqServiceHex = (respServiceByte - 0x40)
            .toRadixString(16)
            .padLeft(2, '0')
            .toUpperCase();
        if (clean.startsWith('7F$reqServiceHex') ||
            clean.startsWith('037F$reqServiceHex')) {
          return null;
        }
      }
    }

    final idx = clean.indexOf(pref);
    if (idx == -1) return null;

    final hexData = clean.substring(idx + pref.length);
    final bytes = <int>[];
    for (int i = 0; i + 1 < hexData.length; i += 2) {
      final b = int.tryParse(hexData.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }

    final payloadMaxLen = expectedTotalLen != null
        ? (expectedTotalLen - (pref.length ~/ 2))
        : null;
    if (payloadMaxLen != null &&
        payloadMaxLen > 0 &&
        bytes.length > payloadMaxLen) {
      return bytes.sublist(0, payloadMaxLen);
    }
    return bytes;
  }

  static int? tryParseMode06Counter(String resp, String expectedPrefix) {
    final b = extractBytes(resp, expectedPrefix);
    if (b == null || b.length < 4) return null;
    if (b.length >= 5) return (b[3] * 256) + b[4];
    return (b[2] * 256) + b[3];
  }
}

class TelemetryPoint {
  final DateTime time;
  final int rpm, ect, iat, map;
  final double volt, stft, ltft, adv, tps, o2s1, o2s2, evap;

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
    required this.o2s1,
    required this.o2s2,
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
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
        isDark ? AppColors.darkSurface : AppColors.lightSurface,
        indicatorColor:
        isDark ? AppColors.darkAccentSoft : AppColors.accentSoft,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
late TabController _tabController;
int _currentTabIndex = 0;

final FlutterBluetoothClassic _bt = FlutterBluetoothClassic();

List<BluetoothDevice> _devices = [];
String? _selectedAddress;
bool _isConnected = false;
bool _isPolling = false;
bool _isSendingCmd = false;
bool _focusAnomaliesOnly = false;

// C9: флаг UDS-протокола. Мутируется ТОЛЬКО в _applyEcuProtocolHint /
// _openM86DiagSession / _runM86HexSniffer. _detectEcuType — pure function.
bool _isUdsM86 = false;

String _statusText = 'Выберите ELM327 адаптер и нажмите Старт';
String _ecuType = 'Итэлма М86 (Евро-5)';
String _dtcSearchQuery = '';

// C1: proper mutex — Completer на текущий polling-цикл
Completer<void>? _cycleCompleter;

// M16: кеш неподдерживаемого Mode06
int _mode06FailStreak = 0;
bool _mode06NotSupported = false;

// M14: debounce сохранения на диск
Timer? _saveDebounceTimer;

// Debounce поиска по DTC
Timer? _dtcSearchDebounce;

final StringBuffer _rxBuffer = StringBuffer();
StreamSubscription? _connSub;
StreamSubscription? _dataSub;

// ignore: unused_field
int? _rpm, _ect, _iat, _map, _speedKmh;
String _mapSourceTag = '010B';
double? _engineLoadPct;
double? _volt, _stft, _ltft, _adv, _tps, _o2Voltage, _o2Sensor2, _evapPurge;
double? _o2AdcVolt, _o2AdcVolt2;

// C2: не пополняем историю O2 чаще, чем раз в 200 мс
DateTime? _lastO2SampleAt;

String _rawLast2101 = 'не опрашивался';
// ignore: unused_field
String _rawLast2102 = 'не опрашивался';
// ignore: unused_field
String _rawLast010B = 'не опрашивался';

final List<double> _o2S1History = [];
final List<double> _o2S2History = [];
double? _dk1PeriodSec;

double? _minVoltSession;
double? _maxVoltSession;
DateTime? _minVoltTime;
int? _minVoltRpm;

final Map<String, TrimBin> _trimBins = {
'zone_idle': TrimBin('ХХ (ДЗ ≤4%)'),
'zone_low_load': TrimBin('Малая нагр.'),
'zone_part_load': TrimBin('Частичная'),
'zone_high_load': TrimBin('Высокая'),
};

double? _selfLearnMult;
double? _idleFuelAdaptPct;
double? _throttleLeakKgH;
double? _idleTorqueAdaptPct;
double? _idleTorquePropPct;
double? _idleTorqueIntPct;
double? _catAgingFactor;
String _catSignalVerdict = 'Не проверялся';
double? _mapAdcVolt;
double? _tps1Volt, _tps2Volt;
double? _pedal1Volt, _pedal2Volt;
double? _acPressVolt;
List<double>? _knockCyl;
List<int>? _misfireCyl;

bool? _clutchSwitchPressed;
bool? _brakeSwitch1Pressed;
bool? _brakeSwitch2Pressed;
bool? _flagIdleMode;
bool? _flagClosedLoopO2;
bool? _flagBaseMixAdapt;
bool? _flagPulleyLearned;
bool? _flagFuelCutoffDfco;
bool? _flagKnockControlActive;
bool? _flagAcRequest;
bool? _flagAcRelayOn;
bool? _flagFan1On;
bool? _flagFan2On;
int _brakeMismatchStreak = 0;

double? _calcCyclicAir;
double? _calcMassAirFlowKgH;
double? _calcFuelRateLh;

// ignore: unused_field
bool? _tid08Dk1Passed;
// ignore: unused_field
bool? _tid07Dk2Passed;

bool _isTrackingPulleyLearn = false;
int _pulleyBrakingCount = 0;
bool _pulleyReached4000 = false;
String _pulleyTrackerStatus =
'Лист 5 ТИ АвтоВАЗ: прогрейте ОЖ до 60–90°C, на 2-й передаче разгонитесь до 4000 об/мин и выполните торможение двигателем до 1000 об/мин 6 раз за поездку.';

bool _isRunningActuatorTest = false;
String _activeActuatorName = 'Нет активного теста';
String _actuatorStatusLog =
'Выберите исполнительный механизм. Перед отправкой любой опасной команды действует двухэтапное подтверждение безопасности.';

double? _weatherTemp;
String _weatherCity = '';

bool _isCheckingUpdate = false;
bool _hasNewUpdate = false;
bool _otaSnackShown = false; // M12: один SnackBar за сессию
String _latestGithubVersion = kAppVersion;
String _latestReleaseNotes = 'Описание релиза отсутствует';
String _latestApkUrl = kDirectApkFallbackUrl;
String _latestPublishedAt = '';

String _ecuId = 'Не прочитан';
List<String> _dtcList = [];
final List<NuanceEvent> _nuanceLog = [];
final Map<String, DateTime> _lastNuanceTimes = {};
final List<TelemetryPoint> _blackBox = [];
final List<int> _rpmWindow = [];

bool _isRunningLeakTest = false;
String _leakTestStatus =
'Готов к проверке (прогрев >70°C). Проверяет подсос ресивера и контура 1,7 мм.';

bool _isRunningStartTest = false;
String _startTestStatus =
'Включите зажигание (не заводя мотор) и нажмите кнопку для контроля АКБ и ДТОЖ.';

bool _isRunningMode06Test = false;
String _mode06TestStatus =
'Проверка реального размаха УДК (0,18–0,95В), ДДК (0,59–0,75В) и ответа Mode \$06.';

bool _isRunningM86DeepTest = false;
String _m86DeepTestStatus =
'Прямой запрос 21 01, 21 02 и Mode \$06 (Пропуски Цил. 1–4, Детонация, КПА, АЦП ДПДЗ/ДППА).';

bool _isRunningPedalSwitchTest = false;
String _pedalSwitchTestStatus =
'Зажигание ВКЛ, мотор ЗАГЛУШЕН: проверка ВСППС (сцепление по CAN от ВСМ) и синхронности ВСТ 1/2 (тормоз C4/C5).';

bool _isRunningThrottleAdapt = false;
String _throttleAdaptStatus =
'После сброса ЭБУ или чистки дросселя: 30 сек зажигание ВКЛ (с живым контролем условий Листа 5) + 10 сек ожидание главного реле.';

bool _isRunningSniffer = false;
String _snifferDump =
'Нажмите кнопку ниже, чтобы опросить ЭБУ и снять полные HEX-ответы 0904, 2101, 2102, 2103, 010B, 0104 для точной сверки карты байтов вашей прошивки.';

// ===== LIFECYCLE =====
@override
void initState() {
super.initState();
// M9: подписка на lifecycle для сохранения при уходе в фон
WidgetsBinding.instance.addObserver(this);
_tabController = TabController(length: 5, vsync: this);
_tabController.addListener(() {
if (_currentTabIndex != _tabController.index) {
HapticFeedback.selectionClick();
setState(() => _currentTabIndex = _tabController.index);
}
});
_loadPersistedState();
_initBluetooth();
_fetchAmbientWeather();
Future.delayed(const Duration(seconds: 2), () {
_checkForOtaUpdate(silent: true);
});
}

@override
void dispose() {
WidgetsBinding.instance.removeObserver(this);
_isPolling = false;
// M9: синхронный flush при закрытии
_flushPersistedState();
_saveDebounceTimer?.cancel();
_dtcSearchDebounce?.cancel();
_connSub?.cancel();
_dataSub?.cancel();
_tabController.dispose();
super.dispose();
}

// M9: сохраняем при уходе в фон
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
if (state == AppLifecycleState.paused) {
_flushPersistedState();
}
}

// ===== M10: ПОСТОЯННАЯ ПАПКА ПРИЛОЖЕНИЯ =====
Future<Directory> _resolveStateDir() async {
try {
// Android: systemTemp = /data/user/0/<pkg>/cache
//           systemTemp.parent = /data/user/0/<pkg> (app root, постоянный)
// iOS:     systemTemp = .../Library/Caches, parent = .../Library
final appRoot = Directory.systemTemp.parent;
final dir = Directory('${appRoot.path}/files/.vesta_state');
if (!await dir.exists()) await dir.create(recursive: true);
return dir;
} catch (_) {
return Directory.systemTemp;
}
}

Future<void> _loadPersistedState() async {
try {
final dir = await _resolveStateDir();
final f = File('${dir.path}/vesta_scan_state_v114.json');
if (!await f.exists()) return;
final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
if (mounted) {
setState(() {
if (data['minVolt'] != null) {
_minVoltSession = (data['minVolt'] as num).toDouble();
}
if (data['maxVolt'] != null) {
_maxVoltSession = (data['maxVolt'] as num).toDouble();
}
if (data['ecuId'] != null) _ecuId = data['ecuId'].toString();
// M20: восстанавливаем протокол
if (data['isUds'] is bool) _isUdsM86 = data['isUds'] as bool;
final binsMap = data['bins'] as Map<String, dynamic>?;
if (binsMap != null) {
binsMap.forEach((k, v) {
if (_trimBins.containsKey(k) && v is List) {
_trimBins[k]!.loadSamples(
v.map((e) => (e as num).toDouble()).toList());
}
});
}
final logList = data['log'] as List?;
if (logList != null) {
_nuanceLog
..clear()
..addAll(logList
.whereType<Map<String, dynamic>>()
.map(NuanceEvent.fromJson));
}
});
}
} catch (_) {}
}

// M14: debounce, чтобы не дёргать I/O на каждый чих
void _savePersistedState() {
_saveDebounceTimer?.cancel();
_saveDebounceTimer = Timer(const Duration(milliseconds: 800), () {
_flushPersistedState();
});
}

Future<void> _flushPersistedState() async {
try {
final dir = await _resolveStateDir();
final binsJson = <String, List<double>>{};
_trimBins.forEach((k, v) => binsJson[k] = v.rawSamples);
final payload = jsonEncode({
'minVolt': _minVoltSession,
'maxVolt': _maxVoltSession,
'ecuId': _ecuId,
'isUds': _isUdsM86,
'bins': binsJson,
'log': _nuanceLog.take(60).map((e) => e.toJson()).toList(),
});
await File('${dir.path}/vesta_scan_state_v114.json')
.writeAsString(payload);
} catch (_) {}
}

// ===== ЦВЕТА ТЕМЫ =====
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

// ===== C1: EXCLUSIVE DIAGNOSTIC С PROPER MUTEX =====
// Ждёт окончания polling-цикла и текущей команды, без _sendQueue
// (иначе deadlock: task() → _sendObdCommand зависает на своём же drain)
Future<void> _runExclusiveDiagnostic(Future<void> Function() task) async {
final wasPolling = _isPolling;
_isPolling = false;

// Дождаться текущего polling-цикла
if (_cycleCompleter != null && !_cycleCompleter!.isCompleted) {
try {
await _cycleCompleter!.future;
} catch (_) {}
}
// Дождаться окончания текущей отправки
while (_isSendingCmd) {
await Future.delayed(const Duration(milliseconds: 20));
}

try {
await task();
} finally {
_savePersistedState();
if (wasPolling && _isConnected && mounted) {
_isPolling = true;
_startPollingLoop();
}
}
}

// ===== C1: NRC-детектор =====
// Проверяет только НАЧАЛО ответа, не ищет 7F в данных
bool _isNrc(String r) {
if (r.isEmpty) return false;
final clean = r.replaceAll(RegExp(r'\s+'), '').toUpperCase();
// NRC: 7F <service> <code> либо с префиксом длины 03
return RegExp(r'^(03)?7F[0-9A-F]{2}[0-9A-F]{2}').hasMatch(clean);
}

// ===== B2: НАДЁЖНАЯ ДЕТЕКЦИЯ СЕССИИ =====
// Критерий успеха — наличие положительного ответа (5081 / 5003),
// а не отсутствие одного конкретного NRC (7F10)
Future<void> _openM86DiagSession() async {
if (_isUdsM86) {
await _sendObdCommand('1003', timeoutMs: 800, postDelayMs: 90);
return;
}
// Пробуем KWP: успех = 5081
final r81 = await _sendObdCommand('1081', timeoutMs: 800, postDelayMs: 90);
final kwpOk = r81.contains('5081') || r81.contains('50 81');
if (kwpOk) return;
// Пробуем UDS
final r03 = await _sendObdCommand('1003', timeoutMs: 800, postDelayMs: 90);
final udsOk = r03.contains('5003') || r03.contains('50 03');
if (udsOk) _isUdsM86 = true;
}

// ===== ДВУХЭТАПНЫЙ SAFETY DIALOG =====
Future<bool> _showTwoStepSafetyDialog({
required String title,
required String warningText,
required String conditionsText,
String finalActionLabel = 'ПОДТВЕРЖДАЮ ЗАПУСК',
bool isDestructive = false,
}) async {
HapticFeedback.heavyImpact();

// ЭТАП 1/2: информирование
final step1Confirmed = await showDialog<bool>(
context: context,
barrierDismissible: false,
builder: (ctx) => AlertDialog(
backgroundColor: _surface,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(24),
side: BorderSide(
color: isDestructive ? _error : _warning, width: 1.5),
),
title: Row(
children: [
Container(
width: 38,
height: 38,
decoration: BoxDecoration(
color: isDestructive ? _errorSoft : _warningSoft,
borderRadius: BorderRadius.circular(12),
),
child: Icon(
Icons.warning_amber_rounded,
color: isDestructive ? _error : _warning,
),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'ШАГ 1 ИЗ 2 · ПРЕДУПРЕЖДЕНИЕ',
style: TextStyle(
fontSize: 10.5,
fontWeight: FontWeight.w800,
letterSpacing: 0.8,
color: isDestructive ? _error : _warning,
),
),
Text(
title,
style: TextStyle(
fontSize: 15.5,
fontWeight: FontWeight.w800,
color: _text1),
),
],
),
),
],
),
content: Text(
warningText,
style: TextStyle(fontSize: 13, color: _text1, height: 1.4),
),
actions: [
OutlinedButton(
onPressed: () => Navigator.pop(ctx, false),
style: OutlinedButton.styleFrom(
foregroundColor: _text2,
side: BorderSide(color: _border),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12)),
),
child: const Text('Отмена'),
),
ElevatedButton(
onPressed: () => Navigator.pop(ctx, true),
style: ElevatedButton.styleFrom(
backgroundColor: _accent,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12)),
),
child: const Text(
'Далее (Шаг 2 из 2) ➔',
style: TextStyle(fontWeight: FontWeight.w800),
),
),
],
),
);

if (step1Confirmed != true || !mounted) return false;
HapticFeedback.heavyImpact();

// ЭТАП 2/2: чек-лист с обязательной галочкой
bool safetyChecked = false;
final step2Confirmed = await showDialog<bool>(
context: context,
barrierDismissible: false,
builder: (ctx) => StatefulBuilder(
builder: (ctx, setDialogState) => AlertDialog(
backgroundColor: _surface,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(24),
side: BorderSide(color: _error, width: 2.0),
),
title: Row(
children: [
Container(
width: 38,
height: 38,
decoration: BoxDecoration(
color: _errorSoft,
borderRadius: BorderRadius.circular(12),
),
child: Icon(Icons.security_rounded, color: _error),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'ШАГ 2 ИЗ 2 · ФИНАЛЬНЫЙ ДОПУСК',
style: TextStyle(
fontSize: 10.5,
fontWeight: FontWeight.w800,
letterSpacing: 0.8,
color: _error,
),
),
Text(
'Проверка условий ТИ АвтоВАЗ',
style: TextStyle(
fontSize: 15.5,
fontWeight: FontWeight.w800,
color: _text1),
),
],
),
),
],
),
content: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Container(
width: double.infinity,
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: _surface2,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: _border),
),
child: Text(
conditionsText,
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w700,
color: _text2,
height: 1.35),
),
),
const SizedBox(height: 12),
InkWell(
borderRadius: BorderRadius.circular(12),
onTap: () {
HapticFeedback.selectionClick();
setDialogState(() => safetyChecked = !safetyChecked);
},
child: Container(
padding:
const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
decoration: BoxDecoration(
color: safetyChecked ? _errorSoft : _surface2,
borderRadius: BorderRadius.circular(12),
border: Border.all(
color: safetyChecked ? _error : _border),
),
child: Row(
children: [
Checkbox(
value: safetyChecked,
activeColor: _error,
onChanged: (v) {
HapticFeedback.selectionClick();
setDialogState(() => safetyChecked = v ?? false);
},
),
Expanded(
child: Text(
'Подтверждаю: все условия безопасности соблюдены, автомобиль зафиксирован.',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w800,
color: _text1,
),
),
),
],
),
),
),
],
),
actions: [
OutlinedButton(
onPressed: () => Navigator.pop(ctx, false),
style: OutlinedButton.styleFrom(
foregroundColor: _text2,
side: BorderSide(color: _border),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12)),
),
child: const Text('Отмена'),
),
ElevatedButton(
onPressed: safetyChecked
? () {
HapticFeedback.heavyImpact();
Navigator.pop(ctx, true);
}
: null,
style: ElevatedButton.styleFrom(
backgroundColor: _error,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12)),
),
child: Text(
finalActionLabel,
style: const TextStyle(fontWeight: FontWeight.w800),
),
),
],
),
),
);

return step2Confirmed == true;
}
// ===== СБРОС ЭБУ С ИНИЦИАЛИЗАЦИЕЙ (Лист 4) =====
Future<void> _confirmAndRunEcuInitializationReset() async {
final confirmed = await _showTwoStepSafetyDialog(
title: 'Сброс ЭБУ с инициализацией',
warningText:
'В контроллере Итэлма М86 снятие клеммы АКБ НЕ обнуляет накопленные коэффициенты самообучения топливоподачи (Лист 20 ТИ АвтоВАЗ).\n\n'
'Команда «Сброс ЭБУ с инициализацией» полностью сотрёт таблицы адаптации смеси в ОЗУ, сбросит адаптацию дросселя и перезагрузит контроллер.',
conditionsText:
'⚠️ ОБЯЗАТЕЛЬНЫЕ УСЛОВИЯ (Лист 4):\n'
'1. Автомобиль стоит на месте, зажигание ВКЛЮЧЕНО, двигатель ЗАГЛУШЕН (0 об/мин).\n'
'2. Сразу после сброса необходимо выждать 30 секунд не нажимая педаль газа (для адаптации нуля дроссельной заслонки)!',
finalActionLabel: 'СБРОСИТЬ ЭБУ (ШАГ 2/2)',
isDestructive: true,
);

if (!confirmed) return;
if (!_isConnected) {
_setStatus('Нет связи с ELM327! Подключитесь к адаптеру.');
return;
}
if ((_rpm ?? 0) > 0) {
_setStatus(
'⛔ Сброс ЭБУ запрещен на работающем двигателе! Заглушите мотор.');
return;
}

setState(() {
_statusText = 'Выполняется Сброс ЭБУ с инициализацией (ОЗУ/ЭРПЗУ)...';
});

await _runExclusiveDiagnostic(() async {
try {
await _openM86DiagSession();
final r31 = await _sendObdCommand('310100', timeoutMs: 1400);
final r11 = await _sendObdCommand('1101', timeoutMs: 1400);
await _sendObdCommand('04', timeoutMs: 1400);

_resetTrimBins();
_idleFuelAdaptPct = null;
_selfLearnMult = null;

final msg =
'✅ Сброс ЭБУ с инициализацией выполнен (ответ шины: ${r11.isNotEmpty ? r11 : r31}). Таблицы самообучения обнулены! Не выключайте зажигание 30 секунд для адаптации нуля дросселя.';
_logNuance(
'ecu_init_reset',
'Сброс ЭБУ с инициализацией',
msg,
NuanceSeverity.warning,
cooldownSec: 1,
);
if (mounted) {
setState(() {
_statusText =
'ЭБУ сброшен с инициализацией. Выполните адаптацию ДЗ (30 с).';
_actuatorStatusLog = msg;
});
}
} finally {
await _sendObdCommand('1001', timeoutMs: 800, postDelayMs: 100);
}
});
}

// ===== B1 + C4: АКТИВНЫЕ ТЕСТЫ ИМ =====
// B1: OFF-команды идут по обоим каналам (основной + альтернативный),
//      IOControl идемпотентен — безопасно отправлять оба
// C4: hold-loop привязан к Stopwatch, шаг ровно 1 сек
Future<void> _executeActuatorTest({
required String title,
required String warningText,
required String conditionsText,
required String kwpCmdOn,
required String kwpCmdOff,
required String udsCmdOn,
required String udsCmdOff,
int holdSeconds = 5,
bool requireEngineRunning = false,
bool requireEngineStopped = false,
bool measureRpmDrop = false,
}) async {
final confirmed = await _showTwoStepSafetyDialog(
title: 'Активный тест: $title',
warningText: warningText,
conditionsText: conditionsText,
finalActionLabel: 'ЗАПУСТИТЬ ТЕСТ ИМ',
);

if (!confirmed) return;
if (!_isConnected) {
setState(() => _actuatorStatusLog =
'⛔ Ошибка: адаптер ELM327 не подключен! Нажмите «Старт» в верхней карточке.');
return;
}

final currentRpm = _rpm ?? 0;
if (requireEngineRunning && currentRpm < 500) {
setState(() => _actuatorStatusLog =
'⛔ Отказ безопасности: тест «$title» требует работающего на ХХ двигателя (сейчас $currentRpm об/мин)!');
return;
}
if (requireEngineStopped && currentRpm > 0) {
setState(() => _actuatorStatusLog =
'⛔ Отказ безопасности: тест «$title» выполняется СТРОГО на заглушенном двигателе!');
return;
}

setState(() {
_isRunningActuatorTest = true;
_activeActuatorName = title;
_actuatorStatusLog = 'Открытие сессии и активация ИМ...';
});

await _runExclusiveDiagnostic(() async {
final primaryOn = _isUdsM86 ? udsCmdOn : kwpCmdOn;
final altOn = _isUdsM86 ? kwpCmdOn : udsCmdOn;
final primaryOff = _isUdsM86 ? udsCmdOff : kwpCmdOff;
final altOff = _isUdsM86 ? kwpCmdOff : udsCmdOff;

bool altSucceeded = false;
bool primarySucceeded = false;

try {
final startRpm = _rpm ?? 840;
int minRpmDuringTest = startRpm;
int maxRpmDuringTest = startRpm;

await _openM86DiagSession();

// Пробуем основной канал
String respOn = await _sendObdCommand(primaryOn,
timeoutMs: 1400, postDelayMs: 150);
primarySucceeded = !_isNrc(respOn) && respOn.isNotEmpty;

// Если основной NRC — пробуем альтернативный
if (!primarySucceeded) {
respOn = await _sendObdCommand(altOn,
timeoutMs: 1400, postDelayMs: 150);
altSucceeded = !_isNrc(respOn) && respOn.isNotEmpty;
}

// Оба канала провалились — не активировали, OFF не нужен
if (!primarySucceeded && !altSucceeded) {
if (mounted) {
setState(() => _actuatorStatusLog =
'⛔ Команда не принята ЭБУ (оба протокола вернули NRC). Управление не активировано.');
}
return;
}

// C4: hold-loop через Stopwatch, шаг ровно 1 секунда
final totalTarget = Duration(seconds: holdSeconds);
final sw = Stopwatch()..start();
int lastShownSec = -1;
while (sw.elapsed < totalTarget) {
if (!_isRunningActuatorTest || !_isConnected) break;

await _sendObdCommand(_isUdsM86 ? '3E00' : '3E',
timeoutMs: 400, postDelayMs: 30);

if (measureRpmDrop) {
_parseRpm(await _sendObdCommand('010C',
timeoutMs: 500, postDelayMs: 60));
if (_rpm != null) {
if (_rpm! < minRpmDuringTest) minRpmDuringTest = _rpm!;
if (_rpm! > maxRpmDuringTest) maxRpmDuringTest = _rpm!;
}
} else {
_parseVoltage(await _sendObdCommand('ATRV',
timeoutMs: 500, postDelayMs: 60));
}

final elapsedSec = sw.elapsedMilliseconds ~/ 1000;
final remaining = holdSeconds - elapsedSec;
if (remaining != lastShownSec && mounted) {
lastShownSec = remaining;
setState(() {
_actuatorStatusLog = measureRpmDrop
? 'Тест «$title» активен ($remaining с) · Обороты: ${_rpm ?? "---"} об/мин'
: 'Тест «$title» активен ($remaining с) · Бортсеть: ${_volt?.toStringAsFixed(2) ?? "---"} В';
});
}

// C4: точная компенсация до 1 секунды
final elapsedMsInIter = sw.elapsedMilliseconds - (elapsedSec * 1000);
final toSleepMs = 1000 - elapsedMsInIter;
if (toSleepMs > 0) {
await Future.delayed(Duration(milliseconds: toSleepMs));
}
}

String summary;
if (measureRpmDrop) {
// Различаем рост (тест «ХХ 1050») и падение (отключение цилиндра)
if (maxRpmDuringTest - startRpm > 100) {
summary =
'✅ Тест «$title» завершён. Обороты ХХ выросли с $startRpm до $maxRpmDuringTest об/мин (ΔRPM = +${maxRpmDuringTest - startRpm}). '
'${(maxRpmDuringTest - startRpm) >= 100 ? "Привод ЭДП отрабатывает штатно." : "⚠️ Обороты выросли слабо (<100 об/мин)."}';
} else {
final drop = startRpm - minRpmDuringTest;
summary =
'✅ Тест «$title» завершён. Обороты ХХ упали с $startRpm до $minRpmDuringTest об/мин (ΔRPM = -$drop). '
'${drop >= 50 ? "Цилиндр участвует в работе." : "⚠️ Падение <50 об/мин — проверьте компрессию, свечу, форсунку."}';
}
} else {
final rawInfo = respOn.isNotEmpty ? respOn : 'NO DATA';
summary =
'✅ Команда «$title» завершена, управление возвращено ЭБУ (ответ: ${rawInfo.length > 60 ? "${rawInfo.substring(0, 60)}..." : rawInfo}).';
}

_logNuance(
'act_$kwpCmdOn',
'Активный тест: $title',
summary,
NuanceSeverity.info,
cooldownSec: 1,
);

if (mounted) setState(() => _actuatorStatusLog = summary);
} finally {
// B1: ОБЯЗАТЕЛЬНО снимаем управление по ОБОИМ каналам
try {
await _sendObdCommand(primaryOff,
timeoutMs: 1200, postDelayMs: 100);
} catch (_) {}
if (altSucceeded) {
try {
await _sendObdCommand(altOff,
timeoutMs: 1200, postDelayMs: 100);
} catch (_) {}
}
try {
await _sendObdCommand('1001', timeoutMs: 800, postDelayMs: 100);
} catch (_) {}

if (mounted) {
setState(() {
_isRunningActuatorTest = false;
_activeActuatorName = 'Нет активного теста';
});
}
}
});
}

// ===== C5: СНИФФЕР БЕЗ ПОРЧИ СЕССИИ =====
// TesterPresent перед каждой командой, не мутирует живые значения
// (не вызываем _parseM86ExtendedBlock / _parseM86AdcBlock),
// _isUdsM86 обновляется по результатам 1081/1003
Future<void> _runM86HexSniffer() async {
HapticFeedback.mediumImpact();
if (_isRunningSniffer) return;
if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

setState(() {
_isRunningSniffer = true;
_snifferDump = 'Опрос диагностических регистров М86...';
});

await _runExclusiveDiagnostic(() async {
try {
final sb = StringBuffer();
sb.writeln('=== ДАМП ОТВЕТОВ ЭБУ М86 (v$kAppVersion) ===');
final r1081 = await _sendObdCommand('1081', timeoutMs: 900);
final r1003 = await _sendObdCommand('1003', timeoutMs: 900);
sb.writeln('1081 (KWP): $r1081 | 1003 (UDS): $r1003');

// Определяем протокол
final kwpOk = r1081.contains('5081');
final udsOk = r1003.contains('5003');
if (!kwpOk && udsOk) _isUdsM86 = true;
if (kwpOk && !udsOk) _isUdsM86 = false;

sb.writeln('=> Протокол: ${_isUdsM86 ? "UDS" : "KWP-CAN"}');

// Формируем список команд в зависимости от протокола
final List<String> cmds = ['0904', '0100', '010B', '0104', '012E'];

if (_isUdsM86) {
// Для UDS используем команды 22 XX XX
cmds.addAll([
'222001', '222002', '222003', // Часто используются для ЭБУ М86 UDS
'220401', '220402', '220403', // Альтернативные идентификаторы
'22F187', '22F188', '22F190'  // Паспортные данные (железо, софт, VIN)
]);
} else {
// Для KWP используем 21 XX
cmds.addAll(['2101', '2102', '2103']);
}

for (final cmd in cmds) {
await _sendObdCommand(_isUdsM86 ? '3E00' : '3E',
timeoutMs: 400, postDelayMs: 30);
final r =
await _sendObdCommand(cmd, timeoutMs: 1600, postDelayMs: 150);
sb.writeln('$cmd => ${r.replaceAll('\n', ' | ')}');
}

final dumpStr = sb.toString().trim();
await Clipboard.setData(ClipboardData(text: dumpStr));
if (mounted) {
setState(() {
_snifferDump =
'$dumpStr\n\n✅ Полный HEX-дамп скопирован в буфер обмена!';
});
}
} finally {
if (mounted) setState(() => _isRunningSniffer = false);
}
});
}

// ===== C10: SEMVER =====
bool _isVersionHigher(String remote, String local) {
String clean(String v) =>
v.split('+').first.split('-').first.replaceAll(RegExp(r'[^0-9.]'), '');
final rParts =
clean(remote).split('.').map((e) => int.tryParse(e) ?? 0).toList();
final lParts =
clean(local).split('.').map((e) => int.tryParse(e) ?? 0).toList();
final maxLen = max(rParts.length, lParts.length);
for (int i = 0; i < maxLen; i++) {
final r = i < rParts.length ? rParts[i] : 0;
final l = i < lParts.length ? lParts[i] : 0;
if (r > l) return true;
if (r < l) return false;
}
return false;
}

// ===== OTA (M12: SnackBar при silent-находке) =====
Future<void> _checkForOtaUpdate({bool silent = false}) async {
if (_isCheckingUpdate) return;
if (mounted) setState(() => _isCheckingUpdate = true);

final client = HttpClient()
..connectionTimeout = const Duration(seconds: 8);
try {
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
_latestReleaseNotes = notes.isNotEmpty
? notes
: 'Обновление алгоритмов М86 VestaScan';
_latestApkUrl = apkUrl;
_latestPublishedAt = pubAt.length >= 16
? pubAt.substring(0, 16).replaceAll('T', ' ')
: pubAt;
_hasNewUpdate = isNewer;
});
}

// M12: показываем SnackBar, если нашли обновление в silent-режиме
if (silent && isNewer && mounted && !_otaSnackShown) {
_otaSnackShown = true;
WidgetsBinding.instance.addPostFrameCallback((_) {
if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Доступно обновление $tagName'),
action: SnackBarAction(
label: 'Открыть',
onPressed: () => _checkForOtaUpdate(silent: false),
),
),
);
});
}
}
} catch (_) {
} finally {
client.close(force: true);
if (mounted) setState(() => _isCheckingUpdate = false);
if (!silent && mounted) _showOtaUpdateDialog();
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
} else {
_setStatus('Открываю браузер для скачивания APK...');
}
}

void _showOtaUpdateDialog() {
showModalBottomSheet(
context: context,
backgroundColor: _surface,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
fontWeight: FontWeight.w800,
color: _text1),
),
Text('Репозиторий: $kGithubRepo',
style: TextStyle(fontSize: 12, color: _text2)),
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
Text('Дата релиза:',
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
Text(_latestReleaseNotes,
maxLines: 6,
overflow: TextOverflow.ellipsis,
style: TextStyle(fontSize: 13, color: _text1)),
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
: 'Скачать свежий APK с GitHub',
),
style: ElevatedButton.styleFrom(
backgroundColor: _hasNewUpdate ? _success : _accent,
foregroundColor: Colors.white,
padding: const EdgeInsets.symmetric(vertical: 15),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(14)),
),
),
),
],
),
);
},
);
}

// ===== ПОГОДА ДЛЯ СВЕРКИ ДТОЖ =====
Future<void> _fetchAmbientWeather() async {
final client = HttpClient()
..connectionTimeout = const Duration(seconds: 6);
try {
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
} catch (_) {
} finally {
client.close(force: true);
}
}

// ===== C9: ДЕТЕКТОР ECU — PURE FUNCTION =====
// Не мутирует _isUdsM86. Для явной установки флага — _applyEcuProtocolHint
String _detectEcuType(String id) {
final upperId = id.toUpperCase();
if (upperId.contains('I785')) return 'Итэлма М86 (1.8л 21179 · UDS)';
if (upperId.contains('M86') ||
upperId.contains('I86') ||
upperId.contains('I765')) {
return 'Итэлма М86 (1.6л 21129 · KWP-CAN)';
}
if (upperId.contains('M74')) return 'Итэлма М74 (CAN/K-Line)';
if (upperId.contains('ME17')) return 'Bosch ME17.9.7 (CAN)';
return 'ЭБУ не определён (OBD-II)';
}

// C9: явная установка _isUdsM86 по результатам 0904
void _applyEcuProtocolHint(String id) {
final upperId = id.toUpperCase();
if (upperId.contains('I785')) {
_isUdsM86 = true;
} else if (upperId.contains('M86') ||
upperId.contains('I86') ||
upperId.contains('I765')) {
_isUdsM86 = false;
}
// Для M74 / ME17 / неизвестного — не трогаем:
// OBD-II работает в любом случае, _openM86DiagSession всё равно
// попробует 1081 и 1003 при следующем подключении
}

// ===== BLUETOOTH =====
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
final uniqueMap = <String, BluetoothDevice>{};
for (final d in list) {
if (d.address.isNotEmpty) uniqueMap[d.address] = d;
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

// ===== M15: LOG С ТРИМОМ ДО 500 =====
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

final currentSnapshot = <String, String>{
if (_rpm != null) 'RPM': '$_rpm',
if (_map != null) 'ДАД': '$_map кПа',
if (_ect != null) 'ОЖ': '$_ect°C',
if (_volt != null) 'Сеть': '${_volt!.toStringAsFixed(2)}В',
if (_minVoltSession != null)
'Мин.АКБ': '${_minVoltSession!.toStringAsFixed(2)}В',
if (_stft != null) 'STFT': '${_stft!.toStringAsFixed(1)}%',
if (_ltft != null) 'LTFT': '${_ltft!.toStringAsFixed(1)}%',
};

setState(() {
final existingIdx = _nuanceLog.indexWhere((e) => e.id == id);
if (existingIdx != -1) {
final existing = _nuanceLog.removeAt(existingIdx);
existing.hzCount += 1;
existing.timestamp = now;
existing.severity = sev;
existing.title = title;
existing.description = desc;
existing.snapshot = currentSnapshot;
_nuanceLog.insert(0, existing);
} else {
_nuanceLog.insert(
0,
NuanceEvent(
id: id,
timestamp: now,
severity: sev,
title: title,
description: desc,
snapshot: currentSnapshot,
),
);
}
if (_nuanceLog.length > 500) {
_nuanceLog.removeRange(500, _nuanceLog.length);
}
});
_savePersistedState();
}

// ===== C1: sendObdCommand без _sendQueue (simple spin-wait) =====
// Между проверкой и установкой флага нет await → в single-threaded Dart
// race невозможен. Всё остальное время занимает await внутри try.
Future<String> _sendObdCommand(
String cmd, {
int timeoutMs = 1100,
int postDelayMs = 150,
}) async {
if (!_isConnected) return 'ERR:NOT_CONNECTED';

while (_isSendingCmd) {
await Future.delayed(const Duration(milliseconds: 20));
}
_isSendingCmd = true;
try {
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
if (postDelayMs > 0) {
await Future.delayed(Duration(milliseconds: postDelayMs));
}
return current.replaceAll('>', '').replaceAll('\r', '\n').trim();
}
}
if (postDelayMs > 0) {
await Future.delayed(Duration(milliseconds: postDelayMs));
}
return _rxBuffer.toString().trim();
} finally {
_isSendingCmd = false;
}
}

// ===== CONNECTION TOGGLE =====
// Проверяет ошибки ATR-команд (P2 из старого ревью)
Future<void> _toggleConnection() async {
HapticFeedback.mediumImpact();

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

setState(() => _statusText = 'Подключение по шине CAN (X1.1/H4-H5)...');

try {
bool ok = await _bt.connect(_selectedAddress!);
if (!ok) {
_setStatus('Не удалось подключиться к адаптеру');
return;
}
_isConnected = true;

// Проверяем каждый ответ ATR-команды
final atrCommands = <String, int>{
'ATZ': 1800,
'ATE0': 500,
'ATL0': 500,
'ATS0': 500,
'ATH0': 500,
'ATSP6': 800,
'ATAL': 500,
'ATCAF1': 500,
'ATSH7E0': 500,
'ATCRA7E8': 500,
'ATFCSH7E0': 500,
'ATFCSD300000': 800,
'ATFCSM1': 500,
};

for (final entry in atrCommands.entries) {
final r = await _sendObdCommand(entry.key, timeoutMs: entry.value);
if (r.startsWith('ERR') || r.contains('?')) {
_setStatus('⚠️ ELM327 не принял ${entry.key}');
}
}

final idResp = await _sendObdCommand('0904', timeoutMs: 1800);
final idBytes = ObdParser.extractBytes(idResp, '4904');
if (idBytes != null && idBytes.isNotEmpty) {
final chars = idBytes
.where((b) => b >= 32 && b <= 126)
.map((b) => String.fromCharCode(b))
.join()
.trim();
if (chars.isNotEmpty) {
_ecuId = chars;
_ecuType = _detectEcuType(_ecuId);
_applyEcuProtocolHint(_ecuId);
}
}

await _openM86DiagSession();

_isPolling = true;
_setStatus('На связи · CAN ISO-TP · $_ecuType');
_logNuance(
'session_start',
'Сессия диагностики открыта',
'Контроллер $_ecuType (Калибровка: $_ecuId). Протокол: ${_isUdsM86 ? "UDS" : "KWP-CAN"}.',
NuanceSeverity.info,
cooldownSec: 1,
);
_startPollingLoop();
} catch (e) {
_setStatus('Ошибка подключения: $e');
_isPolling = false;
}
}

// ===== POLLING LOOP (C1: Completer для exclusive-взаимодействия) =====
Future<void> _startPollingLoop() async {
int cycle = 0;
while (_isPolling && _isConnected) {
_cycleCompleter = Completer<void>();
try {
_parseVoltage(await _sendObdCommand('ATRV'));
if (!_isPolling) break;

_parseRpm(await _sendObdCommand('010C'));
if (!_isPolling) break;

final mapResp = await _sendObdCommand('010B');
_rawLast010B = mapResp.replaceAll('\n', ' ');
_parseMap(mapResp);
if (_map == null) {
_parseEngineLoad(await _sendObdCommand('0104'));
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
_parseEvap(await _sendObdCommand('012E'));
if (!_isPolling) break;
_parseSpeed(await _sendObdCommand('010D'));
if (!_isPolling) break;

final cmdBlock1 = _isUdsM86 ? '222001' : '2101';
final rBlock1 = await _sendObdCommand(cmdBlock1, timeoutMs: 1600);
_rawLast2101 = rBlock1.replaceAll('\n', ' ');
_parseM86ExtendedBlock(rBlock1, isUds: _isUdsM86);
if (!_isPolling) break;

final cmdBlock2 = _isUdsM86 ? '222002' : '2102';
final rBlock2 = await _sendObdCommand(cmdBlock2, timeoutMs: 1500);
_rawLast2102 = rBlock2.replaceAll('\n', ' ');
_parseM86AdcBlock(rBlock2, isUds: _isUdsM86);

if (!_mode06NotSupported &&
_misfireCyl == null &&
cycle % 4 == 1) {
await _pollMode06MisfiresQuick();
}
}

_parseVoltage(await _sendObdCommand('ATRV'));

cycle++;
_recordBlackBoxAndAnalyze();
if (cycle % 10 == 0) _savePersistedState();
if (mounted) setState(() {});
} catch (_) {
await Future.delayed(const Duration(milliseconds: 300));
} finally {
if (_cycleCompleter != null && !_cycleCompleter!.isCompleted) {
_cycleCompleter!.complete();
}
}
}

if (_cycleCompleter != null && !_cycleCompleter!.isCompleted) {
_cycleCompleter!.complete();
}
}

// ===== M16: MODE06 С КЕШЕМ =====
Future<void> _pollMode06MisfiresQuick() async {
final m1 = ObdParser.tryParseMode06Counter(
await _sendObdCommand('06A2', timeoutMs: 750, postDelayMs: 80),
'46A2') ??
ObdParser.tryParseMode06Counter(
await _sendObdCommand('060A', timeoutMs: 750, postDelayMs: 80),
'460A');
if (m1 == null) {
_mode06FailStreak++;
if (_mode06FailStreak >= 2) _mode06NotSupported = true;
return;
}
final m2 = ObdParser.tryParseMode06Counter(
await _sendObdCommand('06A3', timeoutMs: 750, postDelayMs: 80),
'46A3') ??
ObdParser.tryParseMode06Counter(
await _sendObdCommand('060B', timeoutMs: 750, postDelayMs: 80),
'460B');
final m3 = ObdParser.tryParseMode06Counter(
await _sendObdCommand('06A4', timeoutMs: 750, postDelayMs: 80),
'46A4') ??
ObdParser.tryParseMode06Counter(
await _sendObdCommand('060C', timeoutMs: 750, postDelayMs: 80),
'460C');
final m4 = ObdParser.tryParseMode06Counter(
await _sendObdCommand('06A5', timeoutMs: 750, postDelayMs: 80),
'46A5') ??
ObdParser.tryParseMode06Counter(
await _sendObdCommand('060D', timeoutMs: 750, postDelayMs: 80),
'460D');
if (m2 != null && m3 != null && m4 != null) {
_misfireCyl = [m1, m2, m3, m4];
_mode06FailStreak = 0;
} else {
_mode06FailStreak++;
if (_mode06FailStreak >= 2) _mode06NotSupported = true;
}
}
// ===== ПАРСЕРЫ =====
void _parseVoltage(String r) {
final m = RegExp(r'(\d+[.,]\d+)').firstMatch(r);
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
final b = ObdParser.extractBytes(r, '410C');
if (b != null && b.length >= 2) {
final rpmVal = ((b[0] * 256) + b[1]) ~/ 4;
_rpm = rpmVal;
if (rpmVal >= 680 &&
rpmVal <= 980 &&
(_tps ?? 2.0) <= M86Specs.idleTpsMax) {
_rpmWindow.add(rpmVal);
if (_rpmWindow.length > 20) _rpmWindow.removeAt(0);
}
_updatePulleyLearningTracker(rpmVal);
_updateDerivedEstimates();
}
}

// P1: текст приведён к коду (60..90)
void _updatePulleyLearningTracker(int currentRpm) {
if (!_isTrackingPulleyLearn) return;
if ((_ect ?? 0) < 60 || (_ect ?? 0) > 90) {
_pulleyTrackerStatus =
'⚠️ Для обучения шкива ОЖ должна быть в коридоре 60..90°C (сейчас ${_ect ?? "--"}°C, Лист 5).';
return;
}
if (currentRpm >= 3950) {
_pulleyReached4000 = true;
_pulleyTrackerStatus =
'🔥 4000 об/мин достигнуты! Тормозите двигателем до 1000 об/мин (Цикл ${_pulleyBrakingCount + 1}/6)...';
} else if (_pulleyReached4000 &&
currentRpm <= 1100 &&
(_tps ?? 2.0) <= M86Specs.idleTpsMax) {
_pulleyReached4000 = false;
_pulleyBrakingCount++;
HapticFeedback.heavyImpact();
if (_pulleyBrakingCount >= 6) {
_isTrackingPulleyLearn = false;
_flagPulleyLearned = true;
_pulleyTrackerStatus =
'✅ 6/6 циклов! Адаптация шкива ДПКВ завершена по Листу 5.';
_logNuance(
'pulley_learned',
'Обучение шкива ДПКВ (6/6)',
_pulleyTrackerStatus,
NuanceSeverity.info,
cooldownSec: 1,
);
} else {
_pulleyTrackerStatus =
'✅ Засчитан цикл $_pulleyBrakingCount из 6! Снова до 4000 об/мин.';
}
}
}

// C7: MAP без нижней отсечки 10 (высокогорье)
void _parseMap(String r) {
final b = ObdParser.extractBytes(r, '410B');
if (b != null && b.isNotEmpty && b[0] >= 5 && b[0] <= 125) {
_map = b[0];
_mapSourceTag = 'PID 010B';
_updateDerivedEstimates();
}
}

void _parseEngineLoad(String r) {
final b = ObdParser.extractBytes(r, '4104');
if (b != null && b.isNotEmpty) {
_engineLoadPct = b[0] * 100.0 / 255.0;
}
}

void _parseSpeed(String r) {
final b = ObdParser.extractBytes(r, '410D');
if (b != null && b.isNotEmpty) _speedKmh = b[0];
}

void _updateDerivedEstimates() {
final mapVal = _map;
final rpmVal = _rpm;
if (mapVal != null) {
final iatK = (_iat ?? 30) + 273.15;
// P8: 3.05 — эмпирический коэффициент VE * объём / 4π для 1.6L 21129
final cyclicAir = (mapVal * 3.05 * (293.15 / iatK)).clamp(40.0, 520.0);
_calcCyclicAir = cyclicAir;
if (rpmVal != null && rpmVal > 300) {
final mafKgH =
((cyclicAir * rpmVal * 2 * 60) / 1000000.0).clamp(1.0, 180.0);
_calcMassAirFlowKgH = mafKgH;
final trimFactor = 1.0 + (((_stft ?? 0.0) + (_ltft ?? 0.0)) / 100.0);
_calcFuelRateLh =
((mafKgH / (14.6 * 0.75)) * trimFactor).clamp(0.3, 25.0);
} else {
_calcMassAirFlowKgH = 0.0;
_calcFuelRateLh = 0.0;
}
}
final ltftVal = _ltft;
if (ltftVal != null) _selfLearnMult = 1.0 + (ltftVal / 100.0);
}

void _parseEct(String r) {
final b = ObdParser.extractBytes(r, '4105');
if (b != null && b.isNotEmpty) _ect = b[0] - 40;
}

void _parseIat(String r) {
final b = ObdParser.extractBytes(r, '410F');
if (b != null && b.isNotEmpty) _iat = b[0] - 40;
}

void _parseStft(String r) {
final b = ObdParser.extractBytes(r, '4106');
if (b != null && b.isNotEmpty) _stft = (b[0] - 128) * 100.0 / 128.0;
}

void _parseLtft(String r) {
final b = ObdParser.extractBytes(r, '4107');
if (b != null && b.isNotEmpty) {
_ltft = (b[0] - 128) * 100.0 / 128.0;
_updateDerivedEstimates();
}
}

void _parseAdv(String r) {
final b = ObdParser.extractBytes(r, '410E');
if (b != null && b.isNotEmpty) _adv = (b[0] / 2.0) - 64.0;
}

void _parseTps(String r) {
final b = ObdParser.extractBytes(r, '4111');
if (b != null && b.isNotEmpty) _tps = b[0] * 100.0 / 255.0;
}

// C2: единая функция для O2, история пополняется не чаще 200 мс
void _applyO2Sample(double voltage, {required bool fromAdc}) {
final now = DateTime.now();
final canAppend = _lastO2SampleAt == null ||
now.difference(_lastO2SampleAt!).inMilliseconds >= 200;
if (canAppend) {
_o2S1History.add(voltage);
if (_o2S1History.length > 40) _o2S1History.removeAt(0);
_lastO2SampleAt = now;
}
}

// P10: явные комментарии магических порогов
void _parseO2(String r) {
final b = ObdParser.extractBytes(r, '4114');
if (b == null || b.isEmpty) return;
final vStd = b[0] / 200.0;
// 230 = 1.15 В — граница «прогретый» датчик
// 255 = 1.275 В — PID saturation (обрезано, неинформативно при ADC-режиме)
// 1.25 В — граница опорного (заводские 1.2..1.7)
if (b[0] < 230 && _o2AdcVolt != null && _o2AdcVolt! > 1.25) {
_o2AdcVolt = vStd;
}
if (b[0] == 255 && _o2AdcVolt != null && _o2AdcVolt! > 1.25) return;
_o2Voltage =
(_o2AdcVolt != null && _o2AdcVolt! > 1.25) ? _o2AdcVolt : vStd;
_applyO2Sample(_o2Voltage!, fromAdc: false);
}

void _parseO2Sensor2(String r) {
final b = ObdParser.extractBytes(r, '4115');
if (b == null || b.isEmpty) return;
final vStd = b[0] / 200.0;
if (b[0] < 230 && _o2AdcVolt2 != null && _o2AdcVolt2! > 1.25) {
_o2AdcVolt2 = vStd;
}
if (b[0] == 255 && _o2AdcVolt2 != null && _o2AdcVolt2! > 1.25) return;
_o2Sensor2 =
(_o2AdcVolt2 != null && _o2AdcVolt2! > 1.25) ? _o2AdcVolt2 : vStd;
_o2S2History.add(_o2Sensor2!);
if (_o2S2History.length > 40) _o2S2History.removeAt(0);
}

void _parseEvap(String r) {
final b = ObdParser.extractBytes(r, '412E');
if (b != null && b.isNotEmpty) _evapPurge = b[0] * 100.0 / 255.0;
}

// Заводской блок 21 01 — не перезаписывает стандартные PID
void _parseM86ExtendedBlock(String r, {bool isUds = false}) {
List<int>? b;
if (isUds) {
b = ObdParser.extractBytes(r, '622001') ?? ObdParser.extractBytes(r, '620401');
} else {
b = ObdParser.extractBytes(r, '6101');
}
if (b == null || b.length < 10) return;

if (_map == null && b.length > 8 && b[8] >= 18 && b[8] <= 115) {
_map = b[8];
_mapSourceTag = 'Блок 21 01';
}
if (b.length >= 14) {
_misfireCyl = [b[10], b[11], b[12], b[13]];
}
if (_evapPurge == null && b.length > 14) {
_evapPurge = (b[14] * 100.0 / 255.0).clamp(0.0, 100.0);
}
if (b.length > 15) {
_idleFuelAdaptPct = ((b[15] - 128) * 10.0 / 128.0).clamp(-10.0, 10.0);
}
if (b.length >= 20) {
_knockCyl = [
(b[16] / 100.0).clamp(0.0, 10.0),
(b[17] / 100.0).clamp(0.0, 10.0),
(b[18] / 100.0).clamp(0.0, 10.0),
(b[19] / 100.0).clamp(0.0, 10.0),
];
}
if (b.length >= 21) {
_throttleLeakKgH = (b[20] / 10.0).clamp(0.0, 25.0);
}
if (b.length >= 22) {
final flags = b[21];
_clutchSwitchPressed = (flags & 0x01) == 0;
_brakeSwitch1Pressed = (flags & 0x02) == 0;
_brakeSwitch2Pressed = (flags & 0x04) != 0;
_flagIdleMode = (flags & 0x08) != 0;
_flagClosedLoopO2 = (flags & 0x10) != 0;
_flagBaseMixAdapt = (flags & 0x20) != 0;
_flagPulleyLearned = (flags & 0x40) != 0;
_flagFuelCutoffDfco = (flags & 0x80) != 0;

if (_brakeSwitch1Pressed != _brakeSwitch2Pressed) {
_brakeMismatchStreak++;
} else {
_brakeMismatchStreak = 0;
}
}
if (b.length >= 23) {
final flags2 = b[22];
_flagAcRequest = (flags2 & 0x01) != 0;
_flagAcRelayOn = (flags2 & 0x02) != 0;
_flagFan1On = (flags2 & 0x04) != 0;
_flagFan2On = (flags2 & 0x08) != 0;
_flagKnockControlActive = (flags2 & 0x10) != 0;
}
if (b.length >= 24) {
_catAgingFactor = (b[23] / 100.0).clamp(0.0, 1.0);
}
if (b.length >= 27) {
_idleTorqueAdaptPct = ((b[24] - 128) * 20.0 / 128.0).clamp(-25.0, 25.0);
_idleTorqueIntPct = ((b[25] - 128) * 25.0 / 128.0).clamp(-30.0, 30.0);
_idleTorquePropPct = ((b[26] - 128) * 25.0 / 128.0).clamp(-30.0, 30.0);
}
_updateDerivedEstimates();
}

// Заводской блок 21 02 — АЦП каналы
void _parseM86AdcBlock(String r, {bool isUds = false}) {
List<int>? b;
if (isUds) {
b = ObdParser.extractBytes(r, '622002') ?? ObdParser.extractBytes(r, '620402');
} else {
b = ObdParser.extractBytes(r, '6102');
}
if (b == null || b.length < 10) return;

_mapAdcVolt = b[2] * 5.0 / 255.0;
final adcO2S1 = b[3] * 5.0 / 255.0;
final adcO2S2 = b[4] * 5.0 / 255.0;
if (adcO2S1 >= 0.0 && adcO2S1 <= 2.5) {
_o2AdcVolt = adcO2S1;
_o2Voltage = adcO2S1;
_applyO2Sample(adcO2S1, fromAdc: true);
}
if (adcO2S2 >= 0.0 && adcO2S2 <= 2.5) {
_o2AdcVolt2 = adcO2S2;
_o2Sensor2 = adcO2S2;
_o2S2History.add(adcO2S2);
if (_o2S2History.length > 40) _o2S2History.removeAt(0);
}
_acPressVolt = b[5] * 5.0 / 255.0;
_tps1Volt = b[6] * 5.0 / 255.0;
_tps2Volt = b[7] * 5.0 / 255.0;
_pedal1Volt = b[8] * 5.0 / 255.0;
_pedal2Volt = b[9] * 5.0 / 255.0;
}

// ===== C8: BLACKBOX + ANALYZE =====
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
o2s1: _o2Voltage ?? 0.0,
o2s2: _o2Sensor2 ?? 0.0,
evap: _evapPurge ?? 0.0,
),
);
if (_blackBox.length > 1500) _blackBox.removeAt(0);

final rpm = _rpm ?? 0;
final ect = _ect ?? 0;
final map = _map;
final tps = _tps ?? 2.5;
final volt = _volt ?? 14.0;
final stft = _stft;
final ltft = _ltft;

final isDfcoCutoff = (_flagFuelCutoffDfco == true) ||
(rpm > 1800 && tps <= 2.2 && (map ?? 35) <= M86Specs.dfcoMapCutoffKpa);
final isO2Cold = _o2Voltage != null &&
_o2Voltage! >= M86Specs.o2ColdRefMinV &&
_o2Voltage! <= M86Specs.o2ColdRefMaxV;

if (ect >= M86Specs.ectClosedLoopMin &&
stft != null &&
ltft != null &&
!isDfcoCutoff &&
!isO2Cold &&
tps < 70.0) {
if (rpm >= 740 && rpm <= 960 && tps <= M86Specs.idleTpsMax) {
_trimBins['zone_idle']!.addSample(stft, ltft);
} else if (rpm > 1600 && tps <= 12.0 && (map ?? 40) < 48) {
_trimBins['zone_low_load']!.addSample(stft, ltft);
} else if (rpm >= 1300 &&
rpm <= 3400 &&
tps > M86Specs.idleTpsMax &&
tps <= 35.0) {
_trimBins['zone_part_load']!.addSample(stft, ltft);
} else if (tps > 35.0 || (map ?? 40) >= 75) {
_trimBins['zone_high_load']!.addSample(stft, ltft);
}
}

// C8: просадка АКБ фиксируется ТОЛЬКО при прокрутке стартера
if (volt < M86Specs.crankVoltMinHealthy &&
volt > 5.0 &&
rpm > 100 &&
rpm < 600) {
_logNuance(
'crank_volt_low',
'Просадка АКБ при прокрутке (${volt.toStringAsFixed(2)} В)',
'Просадка ниже 10.5 В при работе стартера — признак стареющего АКБ.',
volt < M86Specs.crankVoltCritical
? NuanceSeverity.critical
: NuanceSeverity.warning,
cooldownSec: 20,
);
}

if (rpm > 700 &&
(volt < M86Specs.altVoltMin || volt > M86Specs.altVoltMax + 0.2)) {
_logNuance(
'alt_out_of_norm',
'Напряжение бортсети вне нормы (${volt.toStringAsFixed(2)} В)',
'Норма на работающем двигателе: 13,0–14,5 В. Проверьте генератор и Главное реле К27.',
NuanceSeverity.warning,
);
}

if (ect > M86Specs.ectFan2On) {
_logNuance(
'overheat',
'Перегрев ОЖ ($ect °C > 103 °C)',
'При 102°C — 1-я скорость вентилятора (X1.1/H2), при 103°C — 2-я (X1.1/H3).',
NuanceSeverity.critical,
);
}

if (_idleFuelAdaptPct != null &&
_idleFuelAdaptPct!.abs() > M86Specs.idleAdaptNormPct) {
_logNuance(
'idle_adapt_out',
'Адаптация ХХ вне допуска (${_idleFuelAdaptPct!.toStringAsFixed(1)}%)',
'Норма ±2,5% (предел ±5%). Проверьте подсос и КПА.',
_idleFuelAdaptPct!.abs() >= 4.5
? NuanceSeverity.critical
: NuanceSeverity.warning,
);
}

if (_throttleLeakKgH != null &&
_throttleLeakKgH! > M86Specs.throttleLeakMaxKgH) {
_logNuance(
'throttle_leak_high',
'Завышены перетечки через закрытый дроссель (${_throttleLeakKgH!.toStringAsFixed(1)} кг/ч)',
'Норма 3–5 кг/ч. Проверьте шланг ВКГ с жиклером 1,7 мм.',
NuanceSeverity.warning,
);
}

if (rpm > 650 &&
((stft ?? 0.0) > M86Specs.trimNormLimitPct ||
(ltft ?? 0.0) > M86Specs.trimNormLimitPct)) {
_logNuance(
'lean_mix',
'Бедная смесь (коррекция > +15%)',
'Проверьте подсос воздуха и давление в рампе (364–400 кПа).',
NuanceSeverity.warning,
);
}

if (rpm > 650 &&
((stft ?? 0.0) < -M86Specs.trimNormLimitPct ||
(ltft ?? 0.0) < -M86Specs.trimNormLimitPct)) {
_logNuance(
'rich_mix',
'Богатая смесь (коррекция < -15%)',
'Проверьте термостат, КПА и герметичность форсунок.',
NuanceSeverity.warning,
);
}

if (_brakeMismatchStreak >= 3) {
_logNuance(
'brake_p0504_mismatch',
'Рассогласование ВСТ 1 и ВСТ 2 (риск P0504)',
'В течение $_brakeMismatchStreak циклов состояния C4 и C5 не совпадают.',
NuanceSeverity.critical,
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

// ===== M17: АДАПТАЦИЯ ДЗ — ECT/IAT перечитываются раз в 5 сек =====
Future<void> _runThrottleAdaptationMaster() async {
HapticFeedback.mediumImpact();
if (_isRunningThrottleAdapt) {
setState(() {
_isRunningThrottleAdapt = false;
_throttleAdaptStatus = 'Адаптация нуля дросселя прервана пользователем.';
});
return;
}

if (!_isConnected) {
setState(() => _throttleAdaptStatus =
'⛔ Подключитесь к адаптеру ELM327 для контроля условий адаптации ДЗ!');
return;
}

setState(() => _isRunningThrottleAdapt = true);

await _runExclusiveDiagnostic(() async {
try {
_parseEct(
await _sendObdCommand('0105', timeoutMs: 600, postDelayMs: 60));
_parseIat(
await _sendObdCommand('010F', timeoutMs: 600, postDelayMs: 60));

final sw = Stopwatch()..start();
int lastEctReadSec = 0;
while (sw.elapsedMilliseconds < 30000) {
if (!_isRunningThrottleAdapt || !_isConnected) return;

final elapsedSec = sw.elapsedMilliseconds ~/ 1000;

_parseVoltage(
await _sendObdCommand('ATRV', timeoutMs: 500, postDelayMs: 50));
_parseRpm(
await _sendObdCommand('010C', timeoutMs: 500, postDelayMs: 50));
_parseTps(
await _sendObdCommand('0111', timeoutMs: 500, postDelayMs: 50));

// M17: ECT/IAT перечитываем раз в 5 секунд
if (elapsedSec - lastEctReadSec >= 5) {
_parseEct(
await _sendObdCommand('0105', timeoutMs: 500, postDelayMs: 50));
_parseIat(
await _sendObdCommand('010F', timeoutMs: 500, postDelayMs: 50));
lastEctReadSec = elapsedSec;
}

if ((_rpm ?? 0) > 0) {
setState(() => _throttleAdaptStatus =
'⛔ СРЫВ (Лист 5): прокрутка двигателя ($_rpm об/мин)!');
return;
}
if ((_volt ?? 12.5) < 10.0) {
setState(() => _throttleAdaptStatus =
'⛔ СРЫВ (P1564): напряжение ${_volt?.toStringAsFixed(2)} В < 10.0 В!');
return;
}
if ((_tps ?? 2.0) > 9.5) {
setState(() => _throttleAdaptStatus =
'⛔ СРЫВ (P1579): нажата педаль (ДЗ ${_tps!.toStringAsFixed(1)}%)!');
return;
}
if (_ect != null && (_ect! < 5 || _ect! > 100)) {
setState(() => _throttleAdaptStatus =
'⛔ СРЫВ (P1579): ОЖ $_ect°C вне коридора 5..100!');
return;
}
if (_iat != null && _iat! < 5) {
setState(() => _throttleAdaptStatus =
'⛔ СРЫВ (Лист 5): ДТВ $_iat°C < +5°C!');
return;
}

if (mounted) {
final remSec = max(1, 30 - elapsedSec);
setState(() => _throttleAdaptStatus =
'Шаг 1/2 (ЭБУ: ${_volt?.toStringAsFixed(2) ?? "--"}В, ДЗ ${_tps?.toStringAsFixed(1) ?? "--"}%, ОЖ ${_ect ?? "--"}°C)... Осталось $remSec сек');
}
await Future.delayed(const Duration(milliseconds: 250));
}

HapticFeedback.heavyImpact();
for (int i = 10; i > 0; i--) {
if (!_isRunningThrottleAdapt) return;
if (mounted) {
setState(() => _throttleAdaptStatus =
'Шаг 2/2: ВЫКЛЮЧИТЕ ЗАЖИГАНИЕ прямо сейчас! Ожидание отключения гл. реле К27... $i сек');
}
await Future.delayed(const Duration(seconds: 1));
}

const doneMsg =
'✅ Адаптация нуля ДЗ успешно выполнена (30+10 сек, Лист 5)! Значения сохранены в ЭРПЗУ.';
_logNuance(
'throttle_adapt',
'Адаптация нуля ДЗ выполнена',
doneMsg,
NuanceSeverity.info,
cooldownSec: 1,
);
if (mounted) setState(() => _throttleAdaptStatus = doneMsg);
} finally {
if (mounted) setState(() => _isRunningThrottleAdapt = false);
}
});
}

// ===== M18: ТЕСТ ПОДСОСА — коридор 2000–3500 =====
Future<void> _runAirLeakAutoTest() async {
HapticFeedback.mediumImpact();
if (_isRunningLeakTest) {
setState(() {
_isRunningLeakTest = false;
_leakTestStatus = 'Тест остановлен пользователем.';
});
return;
}

if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

if ((_ect ?? 0) < 70) {
setState(() => _leakTestStatus =
'⛔ БЛОКИРОВКА: двигатель холодный (${_ect ?? 0}°C). Прогрейте до 70°C!');
return;
}

setState(() {
_isRunningLeakTest = true;
_leakTestStatus = 'Этап 1/2: Не трогайте педаль газа (ХХ, 8 сек)...';
});

await _runExclusiveDiagnostic(() async {
try {
final idleStft = <double>[], idleLtft = <double>[], idleMap = <int>[];
for (int i = 8; i > 0; i--) {
// B3-style: явный выход из метода, не break
if (!_isRunningLeakTest || !_isConnected) {
if (mounted) setState(() => _isRunningLeakTest = false);
return;
}
_parseRpm(
await _sendObdCommand('010C', timeoutMs: 500, postDelayMs: 60));
_parseMap(
await _sendObdCommand('010B', timeoutMs: 500, postDelayMs: 60));
_parseStft(
await _sendObdCommand('0106', timeoutMs: 500, postDelayMs: 60));
_parseLtft(
await _sendObdCommand('0107', timeoutMs: 500, postDelayMs: 60));

if (_stft != null) idleStft.add(_stft!);
if (_ltft != null) idleLtft.add(_ltft!);
if (_map != null) idleMap.add(_map!);

if (mounted) {
setState(() => _leakTestStatus =
'Этап 1/2 (ХХ): осталось $i сек (RPM: ${_rpm ?? "--"}, ДАД: ${_map ?? "--"} кПа)');
}
await Future.delayed(const Duration(milliseconds: 250));
}

final revStft = <double>[], revLtft = <double>[];
int timeoutSec = 25;
while (revStft.length < 6 && timeoutSec-- > 0) {
if (!_isRunningLeakTest || !_isConnected) {
if (mounted) setState(() => _isRunningLeakTest = false);
return;
}
_parseRpm(
await _sendObdCommand('010C', timeoutMs: 500, postDelayMs: 60));
_parseStft(
await _sendObdCommand('0106', timeoutMs: 500, postDelayMs: 60));
_parseLtft(
await _sendObdCommand('0107', timeoutMs: 500, postDelayMs: 60));

final r = _rpm ?? 0;
// M18: коридор 2000–3500 соответствует тексту
final inCorridor = r >= 2000 && r <= 3500;
if (inCorridor) {
revStft.add(_stft ?? 0.0);
revLtft.add(_ltft ?? 0.0);
}

if (mounted) {
setState(() => _leakTestStatus = inCorridor
? 'Этап 2/2: Держим коридор! Точек: ${revStft.length}/6 ($r об/мин)'
: 'Этап 2/2: Поднимите обороты до 2000-3500 (сейчас $r) · ${revStft.length}/6 (timeout $timeoutSec с)');
}
await Future.delayed(const Duration(milliseconds: 250));
}

if (revStft.length < 3) {
if (mounted) {
  setState(() => _leakTestStatus =
  '⚠️ Не удалось набрать точки >2000 об/мин. Повторите, плавно нажав на газ.');
}
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
'✅ ПОДСОС ВОЗДУХА: на ХХ +${sumIdle.toStringAsFixed(1)}%, на 3000 упало до ${sumRev.toStringAsFixed(1)}%. Проверьте жиклер 1,7 мм, ресивер, КПА.';
sev = NuanceSeverity.critical;
} else if (sumIdle > 8.0 && sumRev > 7.0) {
verdict =
'⚠️ НЕХВАТКА ТОПЛИВА: +${sumIdle.toStringAsFixed(1)}% / +${sumRev.toStringAsFixed(1)}%. Проверьте давление ЭБН, форсунки, ДК1.';
sev = NuanceSeverity.critical;
} else if (idleMap.isNotEmpty &&
avgIdleMap > M86Specs.idleMapMaxKpa) {
verdict =
'⚠️ ЗАВЫШЕН ДАД НА ХХ (${avgIdleMap.toStringAsFixed(0)} кПа при норме 28–41): проверьте фазы ГРМ и зазоры клапанов.';
sev = NuanceSeverity.warning;
} else {
final mapInfo = idleMap.isNotEmpty
? '${avgIdleMap.toStringAsFixed(0)} кПа'
: 'нет данных';
verdict =
'✅ ВПУСК И ТОПЛИВО В НОРМЕ: ХХ ${sumIdle.toStringAsFixed(1)}%, обороты ${sumRev.toStringAsFixed(1)}%, ДАД $mapInfo.';
}

_logNuance(
'test_leak',
'Тест «Подсос vs Форсунки»',
verdict,
sev,
cooldownSec: 1,
);
if (mounted) setState(() => _leakTestStatus = verdict);
} finally {
if (mounted) setState(() => _isRunningLeakTest = false);
}
});
}

// ===== M8: УТРЕННИЙ ПУСК — _minVoltRpm обновляется =====
Future<void> _runColdStartTest() async {
HapticFeedback.mediumImpact();
if (_isRunningStartTest) {
setState(() {
_isRunningStartTest = false;
_startTestStatus = 'Тест пуска остановлен.';
});
return;
}

if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

setState(() {
_isRunningStartTest = true;
_startTestStatus =
'Эксклюзивный захват пуска (18 сек): Заводите двигатель прямо сейчас!';
});

await _runExclusiveDiagnostic(() async {
try {
_parseEct(
await _sendObdCommand('0105', timeoutMs: 700, postDelayMs: 60));
_parseIat(
await _sendObdCommand('010F', timeoutMs: 700, postDelayMs: 60));
final startEct = _ect ?? 0, startIat = _iat ?? 0;
final isTrulyColdStart = startEct < 45;
double? minVolt = _volt;
int? minVoltRpm;
final postStartStft = <double>[];

final sw = Stopwatch()..start();
while (sw.elapsedMilliseconds < 18000 &&
_isRunningStartTest &&
_isConnected) {
_parseVoltage(
await _sendObdCommand('ATRV', timeoutMs: 450, postDelayMs: 50));
_parseRpm(
await _sendObdCommand('010C', timeoutMs: 550, postDelayMs: 60));

final v = _volt;
final r = _rpm ?? 0;
if (v != null && v > 4.5) {
if (minVolt == null || v < minVolt) {
minVolt = v;
minVoltRpm = r;
}
}
if (r > 650) {
_parseStft(
await _sendObdCommand('0106', timeoutMs: 550, postDelayMs: 60));
if (_stft != null) postStartStft.add(_stft!);
}

if (mounted) {
final remSec = max(0, 18 - (sw.elapsedMilliseconds ~/ 1000));
final minStr =
minVolt != null ? '${minVolt.toStringAsFixed(2)} В' : '---';
setState(() => _startTestStatus =
'Осталось $remSec с | Пик АКБ: $minStr | Обороты: $r');
}
}

// M8: обновляем _minVoltRpm
if (minVolt != null) {
if (_minVoltSession == null || minVolt < _minVoltSession!) {
_minVoltSession = minVolt;
_minVoltTime = DateTime.now();
_minVoltRpm = minVoltRpm;
}
}

final avgStft = postStartStft.isEmpty
? 0.0
: postStartStft.reduce((a, b) => a + b) / postStartStft.length;
final issues = <String>[];

if (isTrulyColdStart && (startEct - startIat).abs() >= 8) {
issues.add(
'Разброс ДТОЖ ($startEct°C) и ДТВ ($startIat°C) на холодном моторе (${(startEct - startIat).abs()}°C).');
}
if (isTrulyColdStart &&
_weatherTemp != null &&
(startEct - _weatherTemp!).abs() >= 10) {
final locText = _weatherCity.isNotEmpty ? ' ($_weatherCity)' : '';
issues.add(
'ДТОЖ ($startEct°C) vs погода$locText: ${_weatherTemp!.toStringAsFixed(1)}°C.');
}
if (minVolt == null) {
issues.add('Не удалось получить замер напряжения АКБ.');
} else if (minVolt < M86Specs.crankVoltMinHealthy) {
issues.add(
'Просадка АКБ до ${minVolt.toStringAsFixed(2)} В (< 10.5 В — умирающий АКБ!).');
}
if (avgStft < -10.0) {
issues.add(
'STFT ушёл в минус (${avgStft.toStringAsFixed(1)}%) — возможен прихват клапана форсунки.');
}

final minReportStr =
minVolt != null ? '${minVolt.toStringAsFixed(2)} В' : '---';
final report = issues.isEmpty
? '✅ Пуск в норме: Мин. АКБ $minReportStr (≥10.5В), ДТОЖ $startEct°C / ДТВ $startIat°C, STFT ${avgStft.toStringAsFixed(1)}%.'
: '⚠️ Замечания при пуске:\n• ${issues.join('\n• ')}';

_logNuance(
'test_start',
'Протокол «Утренний пуск и АКБ»',
report,
issues.isEmpty ? NuanceSeverity.info : NuanceSeverity.critical,
cooldownSec: 1,
);

if (mounted) {
setState(() => _startTestStatus = report);
_showBatteryMinDialog();
}
} finally {
if (mounted) setState(() => _isRunningStartTest = false);
}
});
}

// ===== B4 + C3: MODE 06 — исправлен ДДК, 20 циклов × 200 мс =====
Future<void> _runMode06AndCatTest() async {
HapticFeedback.mediumImpact();
if (_isRunningMode06Test) return;
if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

setState(() {
_isRunningMode06Test = true;
_mode06TestStatus =
'Опрос Mode \$06 + высокочастотный хронометраж УДК/ДДК (20 циклов × 200 мс)...';
});

await _runExclusiveDiagnostic(() async {
try {
final b0601 = ObdParser.extractBytes(
await _sendObdCommand('0601', timeoutMs: 1500), '4601');
final b0621 = ObdParser.extractBytes(
await _sendObdCommand('0621', timeoutMs: 1500), '4621');

double minO2 = 2.0, maxO2 = 0.0;
double minO2S2 = 2.0, maxO2S2 = 0.0;
int s1Samples = 0, s2Samples = 0;
int transitions = 0;
bool? lastRich;

final sw = Stopwatch()..start();
// C3: 20 циклов × 200 мс = 4 сек. Реальный шаг ~400 мс ≈ Nyquist
for (int i = 20; i > 0; i--) {
if (mounted) {
setState(() => _mode06TestStatus =
'Замер УДК/ДДК: осталось $i циклов из 20...');
}

final b1 = ObdParser.extractBytes(
await _sendObdCommand('0114',
timeoutMs: 400, postDelayMs: 40),
'4114');
if (b1 != null && b1.isNotEmpty) {
final v1 = b1[0] / 200.0;
_o2Voltage = v1;
s1Samples++;
_applyO2Sample(v1, fromAdc: false);
if (v1 < minO2) minO2 = v1;
if (v1 > maxO2) maxO2 = v1;
final isRich = v1 > 0.45;
if (lastRich != null && lastRich != isRich) transitions++;
lastRich = isRich;
}

final b2 = ObdParser.extractBytes(
await _sendObdCommand('0115',
timeoutMs: 400, postDelayMs: 40),
'4115');
if (b2 != null && b2.isNotEmpty) {
final v2 = b2[0] / 200.0;
_o2Sensor2 = v2;
s2Samples++;
_o2S2History.add(v2);
if (_o2S2History.length > 40) _o2S2History.removeAt(0);
if (v2 < minO2S2) minO2S2 = v2;
if (v2 > maxO2S2) maxO2S2 = v2;
}

await Future.delayed(const Duration(milliseconds: 200));
}
sw.stop();

final elapsedSec = max(1.0, sw.elapsedMilliseconds / 1000.0);
_dk1PeriodSec =
transitions >= 2 ? (elapsedSec / (transitions / 2.0)) : null;

final dk1FullSwing = s1Samples > 0 &&
(maxO2 >= M86Specs.udkHighThresholdV &&
minO2 <= M86Specs.udkLowThresholdV);

final dk2MirrorsDk1 = s2Samples > 0 && ((maxO2S2 - minO2S2) > 0.35);

// B4: ДДК должен быть в узком окне 0.10..0.95 — иначе мёртв
final dk2InRange = s2Samples > 0 &&
minO2S2 >= 0.10 &&
maxO2S2 <= 0.95 &&
(maxO2S2 - minO2S2) < 0.40;

_tid08Dk1Passed = dk1FullSwing;
_tid07Dk2Passed = dk2InRange && !dk2MirrorsDk1;

if (b0621 != null && b0621.length >= 5) {
final rawVal = (b0621[3] * 256 + b0621[4]) / 1000.0;
if (rawVal >= 0.0 && rawVal <= 1.0) _catAgingFactor = rawVal;
}

_catSignalVerdict = s2Samples == 0
? 'Нет ответа от ДДК (0115)'
: (dk2MirrorsDk1
? 'ДДК повторяет УДК (размах ${(maxO2S2 - minO2S2).toStringAsFixed(2)}В) — снижение эффективности кат.'
: dk2InRange
? 'ДДК стабилен (${minO2S2.toStringAsFixed(2)}–${maxO2S2.toStringAsFixed(2)}В) — нейтрализатор OK'
: '⚠️ ДДК вне рабочего диапазона (${minO2S2.toStringAsFixed(2)}–${maxO2S2.toStringAsFixed(2)}В) — проверьте датчик!');

final notes = <String>[];
if (s1Samples == 0) {
notes.add('⚠️ ЭБУ не вернул данные по УДК (PID 0114).');
} else if (!dk1FullSwing) {
notes.add(
'❌ УДК: неполный размах ${minO2.toStringAsFixed(2)}–${maxO2.toStringAsFixed(2)} В (норма 0,18–0,95 В). Датчик «устал» или не прогрет!');
} else {
final perStr = _dk1PeriodSec != null
? '${_dk1PeriodSec!.toStringAsFixed(2)} с'
: 'нет переключений';
final perOk = _dk1PeriodSec != null &&
_dk1PeriodSec! < M86Specs.udkMaxPeriodSec;
notes.add(
'${perOk ? "✅" : "⚠️"} УДК: размах ${minO2.toStringAsFixed(2)}–${maxO2.toStringAsFixed(2)} В, период $perStr (норма < 1,8 с).');
}
if (b0601 != null) {
notes.add('ℹ️ Mode \$06 (0601) получен (${b0601.length} байт).');
}
if (_catAgingFactor != null) {
notes.add(_catAgingFactor! < M86Specs.catAgingMaxNorm
? '✅ Фактор старения катализатора: ${_catAgingFactor!.toStringAsFixed(2)} (норма < 0,45).'
: '❌ Фактор старения катализатора: ${_catAgingFactor!.toStringAsFixed(2)} (превышен 0,45!).');
} else {
notes.add('ℹ️ ДДК: $_catSignalVerdict');
}

final summary = notes.join('\n');
_logNuance(
'mode06_test',
'Результат проверки УДК / ДДК / Mode \$06',
summary,
(!dk1FullSwing || dk2MirrorsDk1 || !dk2InRange)
? NuanceSeverity.warning
: NuanceSeverity.info,
cooldownSec: 1,
);

if (mounted) setState(() => _mode06TestStatus = summary);
} finally {
if (mounted) setState(() => _isRunningMode06Test = false);
}
});
}

// ===== M86 DEEP (21 01 / 21 02 / Mode 06) =====
Future<void> _runM86DeepDiagnosticTest() async {
HapticFeedback.mediumImpact();
if (_isRunningM86DeepTest) return;
if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

setState(() {
_isRunningM86DeepTest = true;
_m86DeepTestStatus =
'Открытие сессии М86 и опрос 21 01, 21 02, Mode \$06...';
});

await _runExclusiveDiagnostic(() async {
try {
await _openM86DiagSession();

final cmdBlock1 = _isUdsM86 ? '222001' : '2101';
final r2101 = await _sendObdCommand(cmdBlock1, timeoutMs: 1600);
final cmdBlock2 = _isUdsM86 ? '222002' : '2102';
final r2102 = await _sendObdCommand(cmdBlock2, timeoutMs: 1600);
_rawLast2101 = r2101.replaceAll('\n', ' ');
_rawLast2102 = r2102.replaceAll('\n', ' ');
_parseM86ExtendedBlock(r2101, isUds: _isUdsM86);
_parseM86AdcBlock(r2102, isUds: _isUdsM86);

if (_misfireCyl == null && !_mode06NotSupported) {
await _pollMode06MisfiresQuick();
}

final findings = <String>[];

final misfires = _misfireCyl;
if (misfires != null && misfires.length == 4) {
final totalMisfires = misfires.fold<int>(0, (a, b) => a + b);
if (totalMisfires > 0) {
final maxMisfire = misfires.reduce(max);
final maxCylIdx = misfires.indexOf(maxMisfire) + 1;
findings.add(
'❌ ПРОПУСКИ (Цил. 1–4): всего $totalMisfires шт. (${misfires.join(" / ")}). Максимум в Цил.$maxCylIdx ($maxMisfire шт.).');
} else {
findings.add('✅ Пропуски (Цил. 1–4): 0 / 0 / 0 / 0.');
}
} else {
findings.add(
'ℹ️ Пропуски (21 01 / Mode \$06): ЭБУ ответил «$_rawLast2101».');
}

final knocks = _knockCyl;
if (knocks != null && knocks.length == 4) {
final maxKnock = knocks.reduce(max);
final maxCylIdx = knocks.indexOf(maxKnock) + 1;
if (maxKnock >= 0.45) {
findings.add(
'⚠️ Детонация Цил.$maxCylIdx (${maxKnock.toStringAsFixed(2)}): ЭБУ убавляет УОЗ в $maxCylIdx-м цилиндре.');
} else {
findings.add(
'✅ Гашение детонации: (${knocks.map((e) => e.toStringAsFixed(2)).join(" | ")}).');
}
} else {
findings.add('ℹ️ Поцилиндровая детонация: ЭБУ не вернул 21 01.');
}

if (_throttleLeakKgH != null) {
final okLeak = _throttleLeakKgH! >= M86Specs.throttleLeakMinKgH &&
_throttleLeakKgH! <= M86Specs.throttleLeakMaxKgH;
findings.add(okLeak
? '✅ Перетечки ДЗ: ${_throttleLeakKgH!.toStringAsFixed(1)} кг/ч (норма 3–5).'
: '⚠️ Перетечки ДЗ: ${_throttleLeakKgH!.toStringAsFixed(1)} кг/ч вне нормы.');
}

if (_evapPurge != null) {
if (_evapPurge! > M86Specs.evapIdleMaxPct && (_rpm ?? 0) < 950) {
findings.add(
'⚠️ КПА на ХХ: ${_evapPurge!.toStringAsFixed(1)}% (норма 0–12%). Избыточный продув!');
} else {
findings.add(
'✅ КПА: ${_evapPurge!.toStringAsFixed(1)}% (норма 0–12%).');
}
}

final t1 = _tps1Volt;
final t2 = _tps2Volt;
if (t1 != null && t2 != null) {
final sum = t1 + t2;
final okSum = (sum - M86Specs.tpsSumTargetV).abs() <=
M86Specs.tpsSumToleranceV;
findings.add(okSum
? '✅ ДПДЗ 1+2: ${t1.toStringAsFixed(2)}В + ${t2.toStringAsFixed(2)}В = ${sum.toStringAsFixed(2)}В.'
: '❌ РАССОГЛАСОВАНИЕ ДПДЗ 1+2: ${sum.toStringAsFixed(2)}В (риск P2135)!');
}

final report = findings.join('\n');
_logNuance(
'm86_deep_test',
'Результат глубокого опроса М86',
report,
findings.any((f) => f.contains('⚠️') || f.contains('❌'))
? NuanceSeverity.warning
: NuanceSeverity.info,
cooldownSec: 1,
);

if (mounted) setState(() => _m86DeepTestStatus = report);
} finally {
if (mounted) setState(() => _isRunningM86DeepTest = false);
}
});
}

// ===== B3 + M19: КОНЦЕВИКИ ПЕДАЛЕЙ =====
Future<void> _runPedalSwitchesTest() async {
HapticFeedback.mediumImpact();
if (_isRunningPedalSwitchTest) {
setState(() {
_isRunningPedalSwitchTest = false;
_pedalSwitchTestStatus = 'Проверка концевиков педалей остановлена.';
});
return;
}

if (!_isConnected) {
_setStatus('Сначала нажмите «Старт» для подключения к ЭБУ!');
return;
}

setState(() {
_isRunningPedalSwitchTest = true;
_pedalSwitchTestStatus =
'Тест идёт (15 сек): Поочередно нажмите и отпустите СЦЕПЛЕНИЕ и ТОРМОЗ...';
});

await _runExclusiveDiagnostic(() async {
try {
await _openM86DiagSession();

bool sawClutchChange = false;
bool sawBrakeChange = false;
bool sawSustainedBrakeMismatch = false;
bool? initClutch;
bool? initBrake1;
int framesReceived = 0;

for (int i = 15; i > 0; i--) {
// B3: return, а не break — иначе result строится с неполными данными
if (!_isRunningPedalSwitchTest || !_isConnected) {
if (mounted) setState(() => _isRunningPedalSwitchTest = false);
return;
}

// M19: сбрасываем флаги, чтобы отличить «нет кадра» от «было значение»
_clutchSwitchPressed = null;
_brakeSwitch1Pressed = null;
_brakeSwitch2Pressed = null;

final cmdBlock1 = _isUdsM86 ? '222001' : '2101';
final r2101 = await _sendObdCommand(cmdBlock1,
timeoutMs: 1100, postDelayMs: 150);
_rawLast2101 = r2101.replaceAll('\n', ' ');
_parseM86ExtendedBlock(r2101, isUds: _isUdsM86);

if (_clutchSwitchPressed != null) {
framesReceived++;
initClutch ??= _clutchSwitchPressed;
initBrake1 ??= _brakeSwitch1Pressed;

if (_clutchSwitchPressed != initClutch) sawClutchChange = true;
if (_brakeSwitch1Pressed != initBrake1) sawBrakeChange = true;
if (_brakeMismatchStreak >= 2) {
sawSustainedBrakeMismatch = true;
}
}

if (mounted) {
final cStr = _clutchSwitchPressed == null
? '---'
: (_clutchSwitchPressed! ? 'НАЖАТА' : 'ОТПУЩЕНА');
final b1Str = _brakeSwitch1Pressed == null
? '---'
: (_brakeSwitch1Pressed! ? 'ВКЛ' : 'ВЫКЛ');
final b2Str = _brakeSwitch2Pressed == null
? '---'
: (_brakeSwitch2Pressed! ? 'ВКЛ' : 'ВЫКЛ');

setState(() {
_pedalSwitchTestStatus =
'Осталось $i с | Сцепление: $cStr | Тормоз C4/C5: $b1Str / $b2Str';
});
}
await Future.delayed(const Duration(milliseconds: 650));
}

String result;
NuanceSeverity sev = NuanceSeverity.info;
if (framesReceived == 0) {
result =
'ℹ️ ЭБУ не отдал байт флагов в 21 01 (ответ: $_rawLast2101).\n'
'Проверка ВСППС вручную: на концевике сцепления при нажатии цепь Кл.15 должна РАЗМЫКАТЬСЯ.';
} else {
final lines = <String>[];
lines.add(sawClutchChange
? '✅ ВСППС (сцепление → ВСМ → CAN): переключение зафиксировано.'
: '⚠️ ВСППС: смена состояния НЕ зафиксирована. Проверьте концевик и связь с ВСМ по CAN.');
if (sawSustainedBrakeMismatch) {
lines.add(
'❌ РАССОГЛАСОВАНИЕ ВСТ 1 (C4) и ВСТ 2 (C5): риск P0504 и ограничения мощности Е-Газа!');
sev = NuanceSeverity.critical;
} else if (sawBrakeChange) {
lines.add('✅ ВСТ 1 и ВСТ 2: оба канала переключились синхронно.');
} else {
lines.add('ℹ️ Педаль тормоза не нажималась.');
}
result = lines.join('\n');
}

_logNuance(
'pedal_switch_test',
'Тест концевиков ВСППС и ВСТ',
result,
sev,
cooldownSec: 1,
);
if (mounted) setState(() => _pedalSwitchTestStatus = result);
} finally {
if (mounted) setState(() => _isRunningPedalSwitchTest = false);
}
});
}
// ===== DTC: чтение кодов и паспорта ЭБУ =====
Future<void> _readDtcAndEcuId() async {
HapticFeedback.lightImpact();
_setStatus('Чтение паспорта М86 и памяти ошибок...');

await _runExclusiveDiagnostic(() async {
// 1) Паспорт ЭБУ (0904)
final idResp = await _sendObdCommand('0904', timeoutMs: 2000);
final idBytes = ObdParser.extractBytes(idResp, '4904');
if (idBytes != null && idBytes.isNotEmpty) {
final chars = idBytes
.where((b) => b >= 32 && b <= 126)
.map((b) => String.fromCharCode(b))
.join()
.trim();
if (chars.isNotEmpty) {
_ecuId = chars;
_ecuType = _detectEcuType(_ecuId);
_applyEcuProtocolHint(_ecuId); // C9: явная установка _isUdsM86
}
}

// 2) DTC (Mode 03 / 07)
final codes = <String>{};
for (final mode in ['03', '07']) {
final resp = await _sendObdCommand(mode, timeoutMs: 2000);
final b = ObdParser.extractBytes(resp, mode == '03' ? '43' : '47');
if (b == null || b.length < 3) continue;

final cnt = b[0];
final usable = (cnt > 0 && cnt <= 40 && b.length >= 1 + cnt * 2)
? cnt
: (b.length - 1) ~/ 2;

for (int i = 0; i < usable; i++) {
final b1 = b[1 + i * 2];
final b2 = b[2 + i * 2];
if (b1 == 0 && b2 == 0) continue; // padding
const typeChars = ['P', 'C', 'B', 'U'];
final type = typeChars[(b1 >> 6) & 0x03];
final codeStr =
'$type${((b1 >> 4) & 0x03)}${(b1 & 0x0F).toRadixString(16).toUpperCase()}${((b2 >> 4) & 0x0F).toRadixString(16).toUpperCase()}${(b2 & 0x0F).toRadixString(16).toUpperCase()}';
codes.add(codeStr);
}
}

// 3) Сортировка: приоритетные первыми, остальные по алфавиту
final sortedCodes = codes.toList()
..sort((a, b) {
final aPrio = kPriorityCodes.contains(a) ? 0 : 1;
final bPrio = kPriorityCodes.contains(b) ? 0 : 1;
if (aPrio != bPrio) return aPrio.compareTo(bPrio);
return a.compareTo(b);
});

if (mounted) {
setState(() {
_dtcList = sortedCodes;
_statusText =
'Чтение DTC и паспорта завершено (найдено: ${_dtcList.length})';
});
}
});
}

// ===== DTC: сброс кодов (Mode 04) =====
Future<void> _clearDtcCodes() async {
final confirm = await _showTwoStepSafetyDialog(
title: 'Сброс кодов ошибок (Mode 04)',
warningText:
'Команда Mode 04 полностью очистит память кодов неисправностей ОЗУ контроллера М86 и погасит сигнализатор MIL (Лист 37, 44).',
conditionsText:
'⚠️ УСЛОВИЯ (Лист 44): Включите зажигание на стоящем автомобиле при заглушенном двигателе (0 об/мин). Предварительно рекомендуется просмотреть стоп-кадры найденных кодов.',
finalActionLabel: 'СТЕРЕТЬ КОДЫ (MODE 04)',
isDestructive: true,
);

if (!confirm) return;

await _runExclusiveDiagnostic(() async {
await _sendObdCommand('04', timeoutMs: 2000);
if (mounted) {
setState(() {
_dtcList.clear();
_statusText = 'Память кодов неисправностей очищена (Mode 04)';
});
}
_logNuance(
'dtc_clear',
'Сброс кодов DTC (Mode 04)',
'Коды неисправностей стерты из памяти контроллера.',
NuanceSeverity.info,
cooldownSec: 1,
);
});
}

// ===== EXPORT CSV — ISO 8601 =====
Future<void> _exportCsvAndSaveFile() async {
HapticFeedback.lightImpact();
final sb = StringBuffer();

sb.writeln(
'=== ЖУРНАЛ ДИАГНОСТИКИ (VestaScan Pro v$kAppVersion · ТИ 3100.25100.12056) ===');
sb.writeln(
'Мин. АКБ за сессию: ${_minVoltSession?.toStringAsFixed(2) ?? "---"} В');

for (final e in _nuanceLog) {
sb.writeln(
'[${e.timestamp.toIso8601String()}] [HZ:${e.hzCount}] [${e.severity.name.toUpperCase()}] ${e.title}: ${e.description} | ${e.snapshot}');
}

sb.writeln('\n=== ЧЕРНЫЙ ЯЩИК (CSV) ===');
sb.writeln(
'Time_ISO;RPM;MAP_kPa;ECT_C;IAT_C;Volt_V;STFT_%;LTFT_%;UOZ_deg;TPS_%;UDK1_V;DDK2_V;KPA_EVAP_%');

for (final p in _blackBox) {
sb.writeln(
'${p.time.toIso8601String()};${p.rpm};${p.map};${p.ect};${p.iat};${p.volt.toStringAsFixed(2)};${p.stft.toStringAsFixed(1)};${p.ltft.toStringAsFixed(1)};${p.adv.toStringAsFixed(1)};${p.tps.toStringAsFixed(1)};${p.o2s1.toStringAsFixed(2)};${p.o2s2.toStringAsFixed(2)};${p.evap.toStringAsFixed(1)}');
}

final csvText = sb.toString();
await Clipboard.setData(ClipboardData(text: csvText));

String savedFileMsg = '';
try {
final dir = await _resolveStateDir();
final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
final f = File('${dir.path}/vesta_export_$stamp.csv');
await f.writeAsString(csvText);
savedFileMsg = ' · файл: ${f.path}';
} catch (_) {
savedFileMsg = ' · файл НЕ сохранён (нет прав)';
}

_setStatus(
'Скопировано в буфер (${_nuanceLog.length} событий, ${_blackBox.length} строк CSV)$savedFileMsg');
}

// ===== OUTCOME VERDICT (P2: недогрев < 87) =====
Map<String, dynamic> _buildOutcomeDrivenVerdict() {
final findings = <String>[];
Color badgeColor = _accent;
Color badgeBg = _accentSoft;
String headline = 'Ожидание телеметрии Итэлма М86';

if (!_isConnected && _minVoltSession == null && _ect == null) {
return {
'headline': headline,
'summary':
'Подключитесь к адаптеру. Все пороги синхронизированы с ТИ 3100.25100.12056.',
'color': badgeColor,
'bg': badgeBg,
};
}

// P2: расширенное окно недогрева (40..87)
if (_ect != null && _ect! < 87 && _ect! > 40 && (_rpm ?? 0) > 600) {
findings.add(
'• Недогрев ДВС ($_ect°C при норме ${M86Specs.ectWarmMin}–${M86Specs.ectFan2On}°C): термостат рано открывает большой круг, ЭБУ богатит смесь.');
}
if (_minVoltSession != null &&
_minVoltSession! < M86Specs.crankVoltMinHealthy) {
findings.add(
'• Просадка АКБ при пуске до ${_minVoltSession!.toStringAsFixed(2)} В (< 10.5 В): признак потери ёмкости или окисления масс.');
}
final misfires = _misfireCyl;
if (misfires != null && misfires.any((c) => c > 0)) {
final total = misfires.fold<int>(0, (a, b) => a + b);
findings.add(
'• Зафиксированы пропуски ($total шт. → ${misfires.join("/")}): проверьте катушку, свечу, форсунку!');
}
if (_idleFuelAdaptPct != null &&
_idleFuelAdaptPct!.abs() > M86Specs.idleAdaptNormPct) {
findings.add(
'• Адаптация ХХ (${_idleFuelAdaptPct! >= 0 ? "+" : ""}${_idleFuelAdaptPct!.toStringAsFixed(1)}%) вне допуска (±2,5%)!');
}
if (_throttleLeakKgH != null &&
(_throttleLeakKgH! > M86Specs.throttleLeakMaxKgH ||
_throttleLeakKgH! < M86Specs.throttleLeakMinKgH)) {
findings.add(
'• Перетечки через закрытый дроссель ${_throttleLeakKgH!.toStringAsFixed(1)} кг/ч (норма 3–5): проверьте шланг ВКГ с жиклёром 1,7 мм.');
}
if (_map != null &&
(_rpm ?? 0) >= M86Specs.idleRpmMin &&
(_rpm ?? 0) <= M86Specs.idleRpmMax &&
(_ect ?? 0) >= 85 &&
(_tps ?? 2.0) <= M86Specs.idleTpsMax) {
if (_map! > M86Specs.idleMapMaxKpa) {
findings.add(
'• ДАД на ХХ завышен ($_map кПа при 28–41): подсос или фазы ГРМ.');
} else if (_map! < M86Specs.idleMapMinKpa) {
findings.add(
'• ДАД на ХХ ниже нормы ($_map кПа < 28): нетипичное разрежение.');
}
}
if ((_evapPurge ?? 0) > M86Specs.evapIdleMaxPct &&
(_rpm ?? 0) > 650 &&
(_rpm ?? 0) < 920) {
findings.add(
'• КПА на ХХ ${_evapPurge!.toStringAsFixed(1)}% (норма 0–12%): избыточный продув.');
}
if (_o2Voltage != null &&
_o2Voltage! >= M86Specs.o2ColdRefMinV &&
_o2Voltage! <= M86Specs.o2ColdRefMaxV) {
findings.add(
'• УДК в опорном ${_o2Voltage!.toStringAsFixed(2)} В (1,2–1,7): датчик не прогрет или цепь неактивна.');
}
if (_brakeMismatchStreak >= 3) {
findings.add('• Рассогласование ВСТ 1 и ВСТ 2 (C4/C5): риск P0504!');
}

if (findings.isEmpty) {
headline = 'Измеренные параметры в заводском допуске';
badgeColor = _success;
badgeBg = _successSoft;
findings.add(
'Отклонений по прочитанным датчикам не зафиксировано. Матрица коррекций накапливается с медианной фильтрацией.');
} else {
final hasCrit =
(_minVoltSession != null &&
_minVoltSession! < M86Specs.crankVoltCritical) ||
(_ect != null && _ect! > M86Specs.ectFan2On) ||
(misfires != null && misfires.any((c) => c > 5));
headline = hasCrit
? 'Требуется внимание инженера (${findings.length})'
: 'Зафиксированы отклонения (${findings.length})';
badgeColor = hasCrit ? _error : _warning;
badgeBg = hasCrit ? _errorSoft : _warningSoft;
}

return {
'headline': headline,
'summary': findings.join('\n'),
'color': badgeColor,
'bg': badgeBg,
};
}

// ===== СБРОС/ОЧИСТКА СОСТОЯНИЙ =====
void _resetMinVoltage() {
HapticFeedback.mediumImpact();
setState(() {
_minVoltSession = _volt;
_maxVoltSession = _volt;
_minVoltTime = _volt != null ? DateTime.now() : null;
_minVoltRpm = _rpm;
});
_savePersistedState();
}

void _resetTrimBins() {
HapticFeedback.lightImpact();
setState(() {
for (final bin in _trimBins.values) {
bin.clear();
}
});
_savePersistedState();
}

// ===== МОНИТОР АКБ (M8-фикс: не показываем «при 0 об/мин» если RPM не было) =====
void _showBatteryMinDialog() {
HapticFeedback.lightImpact();
showModalBottomSheet(
context: context,
isScrollControlled: true,
backgroundColor: _surface,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
),
builder: (ctx) {
final minV = _minVoltSession;
final isDying = minV != null && minV < M86Specs.crankVoltMinHealthy;
final isCritical = minV != null && minV < M86Specs.crankVoltCritical;

String verdictTitle = 'Замер ещё не выполнен';
String verdictDesc =
'Подключитесь к ЭБУ и запустите двигатель, чтобы зафиксировать минимальное напряжение на контактах X1.1/L3 и K3 при работе стартера.';
Color statusColor = _accent;
Color statusBg = _accentSoft;

if (minV != null) {
if (isCritical) {
verdictTitle = 'КРИТИЧЕСКАЯ ПРОСАДКА (${minV.toStringAsFixed(2)} В)';
verdictDesc =
'Напряжение упало ниже 9.8 В! Высокий риск срыва адаптации дросселя (P1564). Проверьте АКБ и силовые массы.';
statusColor = _error;
statusBg = _errorSoft;
} else if (isDying) {
verdictTitle =
'ПРИЗНАК УМИРАЮЩЕГО АКБ (${minV.toStringAsFixed(2)} В)';
verdictDesc =
'Просадка ниже 10.5 В при пуске говорит о потере пускового тока и сульфатации АКБ.';
statusColor = _warning;
statusBg = _warningSoft;
} else {
verdictTitle = 'АКБ ДЕРЖИТ НАГРУЗКУ (${minV.toStringAsFixed(2)} В)';
verdictDesc =
'Минимальное напряжение не опускалось ниже 10.5 В.';
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
width: 46,
height: 46,
decoration: BoxDecoration(
color: statusBg,
borderRadius: BorderRadius.circular(14),
),
child:
Icon(Icons.battery_alert_rounded, color: statusColor),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text('Монитор просадки АКБ',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.w800,
color: _text1)),
Text(
'Контроль клемм X1.1/L3, K3 (норма ХХ 13,0–14,5 В)',
style:
TextStyle(fontSize: 12, color: _text2)),
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
borderRadius: BorderRadius.circular(18),
border:
Border.all(color: statusColor.withValues(alpha: 0.5)),
),
child: Column(
children: [
Row(
mainAxisAlignment: MainAxisAlignment.spaceAround,
children: [
Column(children: [
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
fontFeatures: const [
FontFeature.tabularFigures()
],
color: statusColor)),
]),
Container(width: 1, height: 44, color: _border),
Column(children: [
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
fontFeatures: const [
FontFeature.tabularFigures()
],
color: _text1)),
]),
Container(width: 1, height: 44, color: _border),
Column(children: [
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
fontFeatures: const [
FontFeature.tabularFigures()
],
color: _text2)),
]),
],
),
const SizedBox(height: 12),
Divider(color: _border, height: 1),
const SizedBox(height: 10),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Text('Момент фиксации минимума:',
style: TextStyle(fontSize: 12, color: _text2)),
Text(
// Фикс: не печатаем «при 0 об/мин»
_minVoltRpm != null && _minVoltRpm! > 0
? '$timeStr (при $_minVoltRpm об/мин)'
: timeStr,
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w700,
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
Text(verdictTitle,
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w800,
color: statusColor)),
const SizedBox(height: 4),
Text(verdictDesc,
style: TextStyle(
fontSize: 13, color: _text1, height: 1.35)),
],
),
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
label: const Text('Сбросить'),
style: OutlinedButton.styleFrom(
padding: const EdgeInsets.symmetric(vertical: 14),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(14)),
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
borderRadius: BorderRadius.circular(14)),
),
child: const Text('Понятно'),
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

// ===== M6: СТОП-КАДР — sheet открывается сразу, данные грузятся в фоне,
// FLC/HLC/DLC/TSF убраны (ЭБУ их не отдаёт — не показываем фейк) =====
Future<void> _showDtcFreezeFrameSheet(String dtcCode) async {
HapticFeedback.lightImpact();

final desc = kM86DtcDatabase[dtcCode] ??
'Код неисправности стандарта OBD-II (см. карту кода в ТИ 3100.25100.12056)';

final loggedIdx = _nuanceLog.indexWhere(
(e) => e.title.contains(dtcCode) || e.description.contains(dtcCode));
final int hz = loggedIdx != -1
? _nuanceLog[loggedIdx].hzCount
: (_dtcList.contains(dtcCode) ? 1 : 0);

// Локальные переменные для замыкания
int? ffRpm, ffEct, ffMap, ffSpeed;
double? ffStft, ffLtft, ffVolt;
bool requestStarted = false;

if (!mounted) return;

showModalBottomSheet(
context: context,
isScrollControlled: true,
backgroundColor: _surface,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
),
builder: (ctx) {
return StatefulBuilder(
builder: (ctx, setSheetState) {
// Запускаем запрос ОДИН раз при первом билде
if (!requestStarted) {
requestStarted = true;
Future.microtask(() async {
if (!_isConnected || !mounted) {
if (mounted) setSheetState(() {});
return;
}
await _runExclusiveDiagnostic(() async {
final rRpm = ObdParser.extractBytes(
await _sendObdCommand('020C00', timeoutMs: 900),
'420C');
if (rRpm != null && rRpm.length >= 3) {
ffRpm = ((rRpm[1] * 256) + rRpm[2]) ~/ 4;
}
final rEct = ObdParser.extractBytes(
await _sendObdCommand('020500', timeoutMs: 900),
'4205');
if (rEct != null && rEct.length >= 2) {
ffEct = rEct[1] - 40;
}
final rMap = ObdParser.extractBytes(
await _sendObdCommand('020B00', timeoutMs: 900),
'420B');
if (rMap != null && rMap.length >= 2) ffMap = rMap[1];
final rStft = ObdParser.extractBytes(
await _sendObdCommand('020600', timeoutMs: 900),
'4206');
if (rStft != null && rStft.length >= 2) {
ffStft = (rStft[1] - 128) * 100.0 / 128.0;
}
final rLtft = ObdParser.extractBytes(
await _sendObdCommand('020700', timeoutMs: 900),
'4207');
if (rLtft != null && rLtft.length >= 2) {
ffLtft = (rLtft[1] - 128) * 100.0 / 128.0;
}
final rSpd = ObdParser.extractBytes(
await _sendObdCommand('020D00', timeoutMs: 900),
'420D');
if (rSpd != null && rSpd.length >= 2) ffSpeed = rSpd[1];
final rVolt = ObdParser.extractBytes(
await _sendObdCommand('024200', timeoutMs: 900),
'4242');
if (rVolt != null && rVolt.length >= 3) {
ffVolt = ((rVolt[1] * 256) + rVolt[2]) / 1000.0;
}
});
if (mounted) setSheetState(() {});
});
}

final hasRealFreezeFrame = ffRpm != null ||
ffEct != null ||
ffMap != null ||
ffStft != null ||
ffVolt != null;
final stillLoading = _isConnected && !hasRealFreezeFrame;

return Padding(
padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Container(
padding: const EdgeInsets.symmetric(
horizontal: 12, vertical: 6),
decoration: BoxDecoration(
color: _errorSoft,
borderRadius: BorderRadius.circular(12),
),
child: Text(dtcCode,
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.w800,
color: _error)),
),
const SizedBox(width: 12),
Expanded(
child: Text('Стоп-кадр и паспорт (Лист 43–44)',
style: TextStyle(
fontSize: 15,
fontWeight: FontWeight.w800,
color: _text1)),
),
if (stillLoading)
const SizedBox(
width: 18,
height: 18,
child: CircularProgressIndicator(strokeWidth: 2),
),
],
),
const SizedBox(height: 10),
Text(desc,
style: TextStyle(
fontSize: 13, color: _text1, height: 1.35)),
const SizedBox(height: 12),
if (!hasRealFreezeFrame && !stillLoading)
Container(
margin: const EdgeInsets.only(bottom: 12),
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: _warningSoft,
borderRadius: BorderRadius.circular(12),
),
child: Text(
'ЭБУ не вернул стоп-кадр (NO DATA). Ниже показан только паспорт ошибки.',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w700,
color: _warning),
),
),
Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: _surface2,
borderRadius: BorderRadius.circular(16),
border: Border.all(color: _border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text('УСЛОВИЯ ВОЗНИКНОВЕНИЯ (MODE \$02):',
style: TextStyle(
fontSize: 11,
fontWeight: FontWeight.w800,
color: _accent)),
const SizedBox(height: 8),
Wrap(
spacing: 8,
runSpacing: 8,
children: [
_ffChip('Обороты', '${ffRpm ?? "---"} об/мин'),
_ffChip('Темп. ОЖ', '${ffEct ?? "---"} °C'),
_ffChip('ДАД впуск', '${ffMap ?? "---"} кПа'),
_ffChip('STFT',
'${ffStft?.toStringAsFixed(1) ?? "---"} %'),
_ffChip('LTFT',
'${ffLtft?.toStringAsFixed(1) ?? "---"} %'),
_ffChip('Бортсеть',
'${ffVolt?.toStringAsFixed(2) ?? "---"} В'),
_ffChip('Скорость',
'${ffSpeed ?? "---"} км/ч'),
],
),
],
),
),
const SizedBox(height: 12),
// FLC/HLC/DLC/TSF убраны — ЭБУ их не отдаёт, не показываем фейк
Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: _surface2,
borderRadius: BorderRadius.circular(16),
border: Border.all(color: _border),
),
child: Row(
children: [
Icon(Icons.info_outline_rounded,
size: 16, color: _text3),
const SizedBox(width: 8),
Expanded(
child: Text(
'HZ (счётчик случаев): $hz раз — по энергонезависимому журналу приложения.',
style: TextStyle(
fontSize: 12,
color: _text2,
height: 1.35),
),
),
],
),
),
const SizedBox(height: 16),
SizedBox(
width: double.infinity,
child: ElevatedButton(
onPressed: () => Navigator.pop(ctx),
style: ElevatedButton.styleFrom(
backgroundColor: _accent,
foregroundColor: Colors.white,
padding: const EdgeInsets.symmetric(vertical: 14),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(14)),
),
child: const Text('Закрыть стоп-кадр'),
),
),
],
),
);
},
);
},
);
}

Widget _ffChip(String label, String val) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: _border),
),
child: Text(
'$label: $val',
style: TextStyle(
fontSize: 11.5,
fontWeight: FontWeight.w700,
color: _text1),
),
);
}

// ===== ПАМЯТКА ПО РАСПИНОВКЕ =====
void _showM86PinoutReferenceModal() {
HapticFeedback.lightImpact();
showModalBottomSheet(
context: context,
isScrollControlled: true,
backgroundColor: _surface,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
),
builder: (ctx) {
return DraggableScrollableSheet(
expand: false,
initialChildSize: 0.75,
maxChildSize: 0.92,
minChildSize: 0.5,
builder: (_, scrollCtrl) {
return ListView(
controller: scrollCtrl,
padding: const EdgeInsets.all(22),
children: [
Text('Инженерная памятка Итэлма М86',
style: TextStyle(
fontSize: 19,
fontWeight: FontWeight.w800,
color: _text1)),
Text('По ТИ 3100.25100.12056',
style: TextStyle(fontSize: 12, color: _text2)),
const SizedBox(height: 16),
_pinoutSectionCard(
'Концевики педалей ВСППС и ВСТ (Лист 12, 13, 25, 49)',
[
'• ВСППС (сцепление): коммутирует Кл. 15. При нажатии РАЗОМКНУТ. Сигнал идёт в ЦБКЭ (ВСМ) и передаётся в ЭСУД по CAN.',
'• ВСТ 1 (C4): при отпущенной педали НОРМАЛЬНО ЗАМКНУТ (+12В на C4).',
'• ВСТ 2 (C5): при отпущенной педали НОРМАЛЬНО РАЗОМКНУТ (+12В появляется при нажатии).',
'• При рассогласовании ВСТ 1 и ВСТ 2 → P0504 и ограничение мощности Е-Газ!',
],
),
const SizedBox(height: 12),
_pinoutSectionCard(
'Ключевые контакты Х1.1 (Кузовной)',
[
'X1.1 / A5 — Клемма 15 (+12В при вкл. зажигании)',
'X1.1 / J3 — Главное реле К27',
'X1.1 / K3, L3 — Силовое питание с К27 (13,5–15,2 В)',
'X1.1 / J4 — Реле ЭБН К7 (2 сек подкачка, F26 15А)',
'X1.1 / H4 (CAN-H), H5 (CAN-L) — Шина CAN',
'X1.1 / H2, H3 — Реле вентилятора 1 (102°C) и 2 (103°C)',
'X1.1 / J2 — Клапан адсорбера КПА',
'X1.1 / F2 — Реле муфты кондиционера; F4 — ДДХ',
],
),
const SizedBox(height: 12),
_pinoutSectionCard(
'Ключевые контакты Х1.2 (Моторный)',
[
'X1.2 / F3 (+5В), J4 (ДАД: ~4,07В заглушен, 1,56–1,66В ХХ), J2 (ДТВ), J5 (Масса)',
'X1.2 / J3 — ДТОЖ (~3,0В при 20°C; при обрыве 5,0В)',
'X1.2 / G2 (ДПДЗ 1: 0,58–0,70В), G3 (ДПДЗ 2: 4,30–4,42В). Сумма 5,0±0,1В',
'X1.2 / G4 (УДК), H4 (ДДК). Непрогретый опорный = 1,7 В',
'X1.2 / N5..N2 — Ключи катушек Цил. 1–4',
'X1.2 / B2, C2, C3, D2 — Форсунки Цил. 1–4 (рампа 364–400 кПа)',
],
),
],
);
},
);
},
);
}

Widget _pinoutSectionCard(String title, List<String> lines) {
return Container(
padding: const EdgeInsets.all(15),
decoration: BoxDecoration(
color: _surface2,
borderRadius: BorderRadius.circular(18),
border: Border.all(color: _border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(title,
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w800,
color: _accent)),
const SizedBox(height: 8),
...lines.map((l) => Padding(
padding: const EdgeInsets.only(bottom: 6),
child: Text(l,
style: TextStyle(
fontSize: 12, color: _text1, height: 1.35)),
)),
],
),
);
}
// ===== P18: МАТРИЦА КОРРЕКЦИЙ + ветка «умеренный подсос» =====
Widget _buildTrimMapCard() {
final idleBin = _trimBins['zone_idle']!;
final partBin = _trimBins['zone_part_load']!;
String autoArbiter =
'Медианный фильтр отсекает сбои CAN (>25%) и ПХХ. Подсос даёт «+» на ХХ и норму под нагрузкой; слабый насос/форсунки — «+» в частичных и высоких нагрузках.';

if (idleBin.count >= 5 && partBin.count >= 5) {
final idleMed = idleBin.median;
final loadMed = partBin.median;
// P18: явный подсос → умеренный подсос → бедная смесь → богатая
if (idleMed > 8.0 && (idleMed - loadMed) > 4.5) {
autoArbiter =
'🔍 Явный ПОДСОС воздуха: ХХ +${idleMed.toStringAsFixed(1)}%, под нагрузкой ${loadMed.toStringAsFixed(1)}%. Проверьте жиклёр 1,7 мм и ресивер.';
} else if (idleMed > 4.0 && (idleMed - loadMed) > 3.0) {
autoArbiter =
'🔍 НАЧАЛЬНЫЕ ПРИЗНАКИ ПОДСОСА: ХХ +${idleMed.toStringAsFixed(1)}%, под нагрузкой ${loadMed.toStringAsFixed(1)}%. Проверьте герметичность впуска.';
} else if (idleMed > 8.0 && loadMed > 7.5) {
autoArbiter =
'🔍 БЕДНАЯ СМЕСЬ во всех режимах (+${idleMed.toStringAsFixed(1)}% / +${loadMed.toStringAsFixed(1)}%): проверьте давление ЭБН (364–400 кПа), форсунки, УДК.';
} else if (idleMed < -8.0) {
autoArbiter =
'🔍 БОГАТАЯ СМЕСЬ на ХХ (${idleMed.toStringAsFixed(1)}%): проверьте термостат (недогрев < 90°C) и КПА.';
}
}

return Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: _border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(Icons.grid_on_rounded, color: _accent, size: 20),
const SizedBox(width: 8),
Expanded(
child: Text('4 зоны самообучения М86 (медиана STFT+LTFT)',
style: TextStyle(
fontSize: 13.5,
fontWeight: FontWeight.w800,
color: _text1)),
),
IconButton(
icon:
Icon(Icons.restart_alt_rounded, size: 18, color: _text2),
tooltip: 'Очистить накопленные корзины',
visualDensity: VisualDensity.compact,
onPressed: _resetTrimBins,
),
],
),
const SizedBox(height: 8),
Row(
children: _trimBins.values.map((bin) {
final med = bin.median;
final hasData = bin.isNotEmpty;
final color = !hasData
? _text3
: (med.abs() > 12.0
? _error
: (med.abs() > 6.5 ? _warning : _success));
return Expanded(
child: Container(
margin: const EdgeInsets.symmetric(horizontal: 3),
padding:
const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
decoration: BoxDecoration(
color: _surface2,
borderRadius: BorderRadius.circular(14),
border: Border.all(
color: hasData
? color.withValues(alpha: 0.5)
: Colors.transparent),
),
child: Column(
children: [
Text(bin.label,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
fontSize: 9.5,
fontWeight: FontWeight.w700,
color: _text2)),
const SizedBox(height: 5),
Text(
hasData
? '${med >= 0 ? "+" : ""}${med.toStringAsFixed(1)}%'
: '---',
style: TextStyle(
fontSize: 13.5,
fontWeight: FontWeight.w800,
color: color,
fontFeatures: const [
FontFeature.tabularFigures()
])),
const SizedBox(height: 2),
Text(hasData ? '${bin.count} зам.' : '0 зам.',
style: TextStyle(fontSize: 9, color: _text3)),
],
),
),
);
}).toList(),
),
const SizedBox(height: 10),
Text(autoArbiter,
style:
TextStyle(fontSize: 11.5, color: _text2, height: 1.35)),
],
),
);
}

// ===== P19: ФЛАГИ ЭСУД без warnWhenTrue на вентиляторах =====
Widget _buildEcuFlagsPanel() {
Widget flagChip(String title, bool? state, {bool warnWhenTrue = false}) {
final isSet = state == true;
final isKnown = state != null;
final chipColor = !isKnown
? _text3
: (isSet ? (warnWhenTrue ? _warning : _success) : _text2);
final chipBg = !isKnown
? _surface2
: (isSet
? (warnWhenTrue ? _warningSoft : _successSoft)
: _surface2);

return Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
decoration: BoxDecoration(
color: chipBg,
borderRadius: BorderRadius.circular(10),
border: Border.all(
color: isKnown && isSet
? chipColor.withValues(alpha: 0.5)
: _border),
),
child: Text(
'$title: ${!isKnown ? "---" : (isSet ? "ДА" : "НЕТ")}',
style: TextStyle(
fontSize: 11, fontWeight: FontWeight.w700, color: chipColor),
),
);
}

return Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: _border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Wrap(
spacing: 6,
runSpacing: 6,
children: [
flagChip('Режим ХХ', _flagIdleMode),
flagChip('Замкн. контур ДК', _flagClosedLoopO2),
flagChip('Базовая адапт.', _flagBaseMixAdapt),
flagChip('Обучение шкива', _flagPulleyLearned),
flagChip('Отсечка ПХХ', _flagFuelCutoffDfco, warnWhenTrue: true),
flagChip('Контроль детон.', _flagKnockControlActive),
// P19: вентиляторы — это норма, а не warn
flagChip('Вент. 1 (102°C)', _flagFan1On),
flagChip('Вент. 2 (103°C)', _flagFan2On),
flagChip('Запрос конд.', _flagAcRequest),
flagChip('Муфта конд.', _flagAcRelayOn),
],
),
if (_acPressVolt != null) ...[
const SizedBox(height: 8),
Text(
'ДДХ (X1.1/F4, Лист 28): ${_acPressVolt!.toStringAsFixed(2)} В',
style: TextStyle(fontSize: 11.5, color: _text2)),
],
],
),
);
}

// ===== ГЛАВНЫЙ BUILD =====
@override
Widget build(BuildContext context) {
final hasLowBatt = _minVoltSession != null &&
_minVoltSession! < M86Specs.crankVoltMinHealthy;

return Scaffold(
appBar: AppBar(
title: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Text('VestaScan Pro'),
Text('$_ecuType · v$kAppVersion · ${_isUdsM86 ? "UDS" : "KWP"}',
style: TextStyle(
fontSize: 11.5,
fontWeight: FontWeight.w600,
color: _text2)),
],
),
actions: [
IconButton(
icon: Container(
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: _warningSoft,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: _warning.withValues(alpha: 0.6)),
),
child:
Icon(Icons.restart_alt_rounded, color: _warning, size: 20),
),
tooltip: 'Сброс ЭБУ с инициализацией (2 шага)',
onPressed: _confirmAndRunEcuInitializationReset,
),
IconButton(
icon: Icon(Icons.cable_rounded, color: _text1),
tooltip: 'Памятка и распиновка М86',
onPressed: _showM86PinoutReferenceModal,
),
IconButton(
icon: Badge(
isLabelVisible: hasLowBatt,
backgroundColor: _error,
child: Icon(Icons.battery_charging_full_rounded,
color: hasLowBatt ? _error : _text1),
),
tooltip: 'Монитор АКБ',
onPressed: _showBatteryMinDialog,
),
IconButton(
icon: Badge(
isLabelVisible: _hasNewUpdate,
backgroundColor: _success,
child: Icon(Icons.cloud_download_outlined,
color: _hasNewUpdate ? _success : _text1),
),
tooltip: 'OTA (GitHub Releases)',
onPressed: () => _checkForOtaUpdate(silent: false),
),
IconButton(
icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode,
color: _text1),
tooltip: 'Сменить тему',
onPressed: widget.onThemeToggle,
),
const SizedBox(width: 2),
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
_buildActiveTestsTab(),
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
isLabelVisible: _isRunningActuatorTest,
backgroundColor: _warning,
child: const Icon(Icons.tune_outlined),
),
selectedIcon: const Icon(Icons.tune_rounded),
label: 'Актив. тесты',
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
NavigationDestination(
icon: Badge(
isLabelVisible: _dtcList.isNotEmpty,
backgroundColor: _error,
label: Text('${_dtcList.length}'),
child: const Icon(Icons.bug_report_outlined),
),
selectedIcon: Badge(
isLabelVisible: _dtcList.isNotEmpty,
backgroundColor: _error,
label: Text('${_dtcList.length}'),
child: const Icon(Icons.bug_report_rounded),
),
label: 'Коды М86',
),
],
),
),
);
}

// ===== КАРТОЧКА ПОДКЛЮЧЕНИЯ =====
Widget _buildStatusConnectionCard() {
final safeValue = _devices.any((d) => d.address == _selectedAddress)
? _selectedAddress
: null;

return AnimatedContainer(
duration: const Duration(milliseconds: 280),
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: _isPolling ? _success : _border),
),
child: Row(
children: [
InkWell(
onTap: _loadPairedDevices,
borderRadius: BorderRadius.circular(21),
child: Container(
width: 42,
height: 42,
decoration: BoxDecoration(
color: _isPolling ? _successSoft : _accentSoft,
shape: BoxShape.circle,
),
child: Icon(Icons.bluetooth_rounded,
color: _isPolling ? _success : _accent, size: 22),
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
? 'Нет адаптеров / нажмите на BT'
: 'Выберите OBDII адаптер',
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w700,
color: _text2)),
items: _devices.map((d) {
return DropdownMenuItem<String>(
value: d.address,
child: Text(d.name.isNotEmpty ? d.name : d.address,
overflow: TextOverflow.ellipsis,
style: TextStyle(
fontSize: 15,
fontWeight: FontWeight.w700,
color: _text1)),
);
}).toList(),
onChanged: (_isPolling || _devices.isEmpty)
? null
: (val) => setState(() => _selectedAddress = val),
),
),
const SizedBox(height: 2),
Text(_statusText,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w500,
color: _text2)),
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
borderRadius: BorderRadius.circular(14)),
padding:
const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
),
child: Text(_isPolling ? 'Стоп' : 'Старт',
style: const TextStyle(
fontSize: 13, fontWeight: FontWeight.w800)),
),
],
),
);
}

// ===== P16 + P17: ДАТЧИКИ =====
Widget _buildSensorsTab() {
final rpmStatus = (_rpm != null &&
(_rpm! < M86Specs.idleRpmMin || _rpm! > M86Specs.idleRpmMax) &&
(_ect ?? 0) >= 85 &&
(_tps ?? 2.0) <= M86Specs.idleTpsMax)
? 'warn'
: 'normal';
final ectStatus = (_ect ?? 0) > M86Specs.ectFan2On
? 'err'
: ((_ect != null && _ect! < 87) ? 'warn' : 'good');

String mapStatus = 'normal';
if (_map != null &&
(_rpm ?? 0) >= M86Specs.idleRpmMin &&
(_rpm ?? 0) <= M86Specs.idleRpmMax &&
(_tps ?? 2.0) <= M86Specs.idleTpsMax) {
if (_map! > M86Specs.idleMapMaxKpa) {
mapStatus = 'err';
} else if (_map! < M86Specs.idleMapMinKpa) {
mapStatus = 'warn';
} else {
mapStatus = 'good';
}
}

final voltStatus = (_volt != null &&
(_volt! < M86Specs.altVoltMin || _volt! > M86Specs.altVoltMax))
? 'warn'
: (_volt != null ? 'good' : 'normal');
final stftStatus =
(_stft ?? 0.0).abs() > M86Specs.trimNormLimitPct ? 'warn' : 'good';
final ltftStatus =
(_ltft ?? 0.0).abs() > M86Specs.trimNormLimitPct ? 'warn' : 'good';
final evapStatus =
(_evapPurge ?? 0.0) > M86Specs.evapIdleMaxPct && (_rpm ?? 0) < 950
? 'warn'
: 'normal';
final o2Status =
(_o2Voltage != null && _o2Voltage! > M86Specs.o2ColdRefMinV)
? 'warn'
: 'normal';

final minV = _minVoltSession;
final minVBad = minV != null && minV < M86Specs.crankVoltMinHealthy;
final aiVerdict = _buildOutcomeDrivenVerdict();

// P17: MAP unit не прыгает при _map == null
final String mapValue;
final String mapUnit;
final String mapNorm;
if (_map != null) {
mapValue = '$_map';
mapUnit = 'кПа';
mapNorm = 'Норма ХХ: 28–41 кПа ($_mapSourceTag)';
} else if (_engineLoadPct != null) {
mapValue = _engineLoadPct!.toStringAsFixed(0);
mapUnit = '%';
mapNorm = 'Нагрузка 0104 (норма ХХ: 16–26%)';
} else {
mapValue = '---';
mapUnit = 'кПа';
mapNorm = 'Норма ХХ: 28–41 кПа';
}

final allCards = <Map<String, dynamic>>[
{
'icon': Icons.speed_rounded,
'label': 'ОБОРОТЫ ХХ',
'value': '${_rpm ?? "---"}',
'unit': 'об/мин',
'norm': 'Норма: 840 ± 40 | σ ${_rpmSigma.toStringAsFixed(1)}',
'status': rpmStatus,
},
{
'icon': Icons.thermostat_rounded,
'label': 'ТЕМПЕРАТУРА ОЖ',
'value': '${_ect ?? "---"}',
'unit': '°C',
'norm': 'Норма: 90–103 °C',
'status': ectStatus,
},
{
'icon': Icons.compress_rounded,
'label': 'ДАД / НАГРУЗКА',
'value': mapValue,
'unit': mapUnit,
'norm': mapNorm,
'status': mapStatus,
},
{
'icon': Icons.electric_bolt_rounded,
'label': 'БОРТ. СЕТЬ / АКБ',
'value': _volt != null ? _volt!.toStringAsFixed(2) : '---',
'unit': 'В',
'norm':
'13,0–14,5 В | Мин: ${minV != null ? "${minV.toStringAsFixed(2)} В" : "--"}',
'status': minVBad ? 'err' : voltStatus,
},
{
'icon': Icons.tune_rounded,
'label': 'STFT',
'value': _stft != null
? '${_stft! >= 0 ? "+" : ""}${_stft!.toStringAsFixed(1)}'
: '---',
'unit': '%',
'norm': 'Допуск: ±15%',
'status': stftStatus,
},
{
'icon': Icons.history_rounded,
'label': 'LTFT (самообучение)',
'value': _ltft != null
? '${_ltft! >= 0 ? "+" : ""}${_ltft!.toStringAsFixed(1)}'
: '---',
'unit': '%',
'norm':
'Коэфф: ${_selfLearnMult != null ? _selfLearnMult!.toStringAsFixed(2) : "---"} (пред. ±0,25)',
'status': ltftStatus,
},
{
'icon': Icons.flash_on_rounded,
'label': 'УОЗ',
'value': _adv != null ? _adv!.toStringAsFixed(1) : '---',
'unit': '°',
'norm': 'ХХ: 9 ± 5° (3000: 30–35°)',
'status': 'normal',
},
// P16: ДТВ отдельно
{
'icon': Icons.air_rounded,
'label': 'ДТВ (воздух)',
'value': '${_iat ?? "--"}',
'unit': '°C',
'norm': 'Норма: 15–45 °C',
'status': 'normal',
},
// P16: дроссель отдельно
{
'icon': Icons.linear_scale_rounded,
'label': 'ДРОССЕЛЬ',
'value': _tps != null ? _tps!.toStringAsFixed(1) : '---',
'unit': '%',
'norm': 'Норма ХХ: 1–4%',
'status': 'normal',
},
{
'icon': Icons.waves_rounded,
'label': 'УДК (ДК1)',
'value':
_o2Voltage != null ? _o2Voltage!.toStringAsFixed(2) : '---',
'unit': 'В',
'norm': 'Размах: 0,18–0,95 В (холод: 1,70)',
'status': o2Status,
},
{
'icon': Icons.filter_alt_rounded,
'label': 'КПА (EVAP)',
'value':
_evapPurge != null ? _evapPurge!.toStringAsFixed(1) : '---',
'unit': '%',
'norm': 'Норма ХХ: 0–12%',
'status': evapStatus,
},
];

final visibleCards = _focusAnomaliesOnly
? allCards
.where((c) => c['status'] == 'warn' || c['status'] == 'err')
.toList()
: allCards;

return ListView(
padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
children: [
// ИИ-вердикт
Container(
margin: const EdgeInsets.only(bottom: 14),
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: aiVerdict['bg'] as Color,
borderRadius: BorderRadius.circular(22),
border: Border.all(
color: (aiVerdict['color'] as Color)
.withValues(alpha: 0.45)),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(Icons.auto_awesome_rounded,
color: aiVerdict['color'] as Color, size: 20),
const SizedBox(width: 8),
Expanded(
child: Text(aiVerdict['headline'] as String,
style: TextStyle(
fontSize: 15,
fontWeight: FontWeight.w800,
fontFamily: 'Georgia',
color: aiVerdict['color'] as Color)),
),
FilterChip(
label: Text(
_focusAnomaliesOnly ? 'Только сбои' : 'Все датчики',
style: const TextStyle(
fontSize: 11, fontWeight: FontWeight.w700)),
selected: _focusAnomaliesOnly,
onSelected: (v) {
HapticFeedback.selectionClick();
setState(() => _focusAnomaliesOnly = v);
},
),
],
),
const SizedBox(height: 6),
Text(aiVerdict['summary'] as String,
style: TextStyle(
fontSize: 12.5, color: _text1, height: 1.4)),
],
),
),
// Плашка АКБ
InkWell(
borderRadius: BorderRadius.circular(20),
onTap: _showBatteryMinDialog,
child: Container(
margin: const EdgeInsets.only(bottom: 16),
padding:
const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
decoration: BoxDecoration(
color: minVBad ? _errorSoft : _surface,
borderRadius: BorderRadius.circular(20),
border: Border.all(color: minVBad ? _error : _border),
),
child: Row(
children: [
Icon(Icons.battery_alert_rounded,
color: minVBad ? _error : _accent),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
minV != null
? 'Минимум АКБ: ${minV.toStringAsFixed(2)} В'
: 'Монитор просадки АКБ (нажмите)',
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w800,
color: minVBad ? _error : _text1)),
Text(
minVBad
? 'Ниже 10.5 В — умирающий АКБ!'
: 'Норма ≥ 10.5 В · Порог сброса М86: 6.0 В',
style: TextStyle(fontSize: 12, color: _text2)),
],
),
),
Icon(Icons.chevron_right_rounded, color: _text2),
],
),
),
),
_sectionHeader('МАТРИЦА САМООБУЧЕНИЯ (ЛИСТ 19)'),
_buildTrimMapCard(),
const SizedBox(height: 20),
_sectionHeader('ФЛАГИ ЭСУД И КОНДИЦИОНЕР (ЛИСТ 40–41, 46)'),
_buildEcuFlagsPanel(),
const SizedBox(height: 20),
_sectionHeader('ОСНОВНАЯ ТЕЛЕМЕТРИЯ'),
if (visibleCards.isEmpty)
Container(
padding: const EdgeInsets.all(20),
margin: const EdgeInsets.only(bottom: 16),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(20),
border: Border.all(color: _border),
),
child: Text(
'Отклонений не обнаружено! Отключите фильтр, чтобы видеть все карточки.',
style: TextStyle(fontSize: 13, color: _text2)),
)
else
GridView.count(
shrinkWrap: true,
physics: const NeverScrollableScrollPhysics(),
crossAxisCount: 2,
mainAxisSpacing: 12,
crossAxisSpacing: 12,
// P17: 1.05 вместо 1.08 — карточки чуть выше, текст не обрезается
childAspectRatio: 1.05,
children: visibleCards.map((c) {
return _metricCard(
icon: c['icon'] as IconData,
label: c['label'] as String,
value: c['value'] as String,
unit: c['unit'] as String,
norm: c['norm'] as String,
status: c['status'] as String,
);
}).toList(),
),
const SizedBox(height: 22),
_sectionHeader('ОСЦИЛЛОГРАФ УДК vs ДДК (0..1.8В)'),
Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: _border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Row(children: [
Container(
width: 10,
height: 10,
decoration: BoxDecoration(
color: _accent, shape: BoxShape.circle)),
const SizedBox(width: 6),
Text(
'УДК: ${_o2Voltage?.toStringAsFixed(2) ?? "---"} В',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w700,
color: _text1)),
]),
Row(children: [
Container(
width: 10,
height: 10,
decoration: BoxDecoration(
color: _success, shape: BoxShape.circle)),
const SizedBox(width: 6),
Text(
'ДДК: ${_o2Sensor2?.toStringAsFixed(2) ?? "---"} В',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w700,
color: _text1)),
]),
],
),
const SizedBox(height: 12),
SizedBox(
height: 110,
width: double.infinity,
child: CustomPaint(
painter: _O2OscilloscopePainter(
s1: _o2S1History,
s2: _o2S2History,
s1Color: _accent,
s2Color: _success,
gridColor: _border,
),
),
),
const SizedBox(height: 8),
Text(
'Норма: непрогретый = 1,70 В. Прогретый УДК 0,18..0,95 В (<1,8 с). ДДК 0,59..0,75 В.',
style: TextStyle(fontSize: 11, color: _text3)),
],
),
),
const SizedBox(height: 22),
_sectionHeader('ПАРАМЕТРЫ М86 (ПРЯМОЕ ЧТЕНИЕ vs РАСЧЁТ)'),
Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: _border),
),
child: Column(
children: [
_extRow(
'Адаптация топливоподачи на ХХ',
_idleFuelAdaptPct != null
? '${_idleFuelAdaptPct! >= 0 ? "+" : ""}${_idleFuelAdaptPct!.toStringAsFixed(2)} %'
: '---',
'Норма ±2,5% (предел ±5,0%)',
),
_extRow(
'Перетечки через закрытый дроссель',
_throttleLeakKgH != null
? '${_throttleLeakKgH!.toStringAsFixed(1)} кг/ч'
: '---',
'Норма 3–5 кг/ч (жиклёр 1,7 мм)',
),
_extRow(
'Регулятор момента ХХ (А/И/П)',
_idleTorqueAdaptPct != null
? '${_idleTorqueAdaptPct!.toStringAsFixed(1)}% | И:${_idleTorqueIntPct?.toStringAsFixed(1)}% | П:${_idleTorquePropPct?.toStringAsFixed(1)}%'
: '---',
'Адапт. ±5%, Инт./Проп. ±8%',
),
_extRow(
'Пропуски Цил. 1–4',
_misfireCyl != null
? '${_misfireCyl![0]} | ${_misfireCyl![1]} | ${_misfireCyl![2]} | ${_misfireCyl![3]}'
: '---',
'Норма: 0 по всем',
),
_extRow(
'ВСППС (сцепление)',
_clutchSwitchPressed != null
? (_clutchSwitchPressed! ? 'НАЖАТА' : 'ОТПУЩЕНА')
: '---',
'Влияет на момент и ХХ',
),
_extRow(
'ВСТ 1 (C4) / ВСТ 2 (C5)',
(_brakeSwitch1Pressed != null &&
_brakeSwitch2Pressed != null)
? '${_brakeSwitch1Pressed! ? "ВКЛ" : "ВЫКЛ"} / ${_brakeSwitch2Pressed! ? "ВКЛ" : "ВЫКЛ"}'
: '---',
'Рассинхрон → P0504',
),
_extRow(
'Фактор старения катализатора',
_catAgingFactor != null
? '${_catAgingFactor!.toStringAsFixed(2)} (${_catAgingFactor! < M86Specs.catAgingMaxNorm ? "норма" : "износ"})'
: '---',
'Норма < 0,45 (чем меньше — тем лучше)',
),
_extRow(
'Детонация Цил. 1–4',
_knockCyl != null
? '${_knockCyl![0].toStringAsFixed(2)} | ${_knockCyl![1].toStringAsFixed(2)} | ${_knockCyl![2].toStringAsFixed(2)} | ${_knockCyl![3].toStringAsFixed(2)}'
: '---',
'ЭБУ убавляет УОЗ при > 0,45',
),
_extRow(
'ДПДЗ 1 + ДПДЗ 2',
(_tps1Volt != null && _tps2Volt != null)
? '${_tps1Volt!.toStringAsFixed(2)} + ${_tps2Volt!.toStringAsFixed(2)} = ${(_tps1Volt! + _tps2Volt!).toStringAsFixed(2)} В'
: '---',
'Сумма 5,0±0,1 В',
),
_extRow(
'Педали 1 / 2',
(_pedal1Volt != null && _pedal2Volt != null)
? '${_pedal1Volt!.toStringAsFixed(2)} / ${_pedal2Volt!.toStringAsFixed(2)} В'
: '---',
'Отпущена: 0,50–0,85 и 0,25–0,43 В',
),
_extRow(
'АЦП ДАД',
_mapAdcVolt != null
? '${_mapAdcVolt!.toStringAsFixed(2)} В'
: '---',
'ХХ: 1,56–1,66 В (зажигание: ~4,07)',
),
_extRow(
'Цикловое наполнение [расчёт]',
_calcCyclicAir != null
? '~${_calcCyclicAir!.toStringAsFixed(0)} мг/цикл'
: '---',
'Норма ХХ: 115–125 мг/цикл',
),
_extRow(
'Расход воздуха / топлива [расчёт]',
_calcMassAirFlowKgH != null
? '~${_calcMassAirFlowKgH!.toStringAsFixed(1)} кг/ч · ~${_calcFuelRateLh?.toStringAsFixed(2) ?? "--"} л/ч'
: '---',
'ХХ: 7–12 кг/ч, 0.6–0.9 л/ч',
isLast: true,
),
],
),
),
],
);
}

Widget _extRow(String title, String val, String sub,
{bool isLast = false}) {
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
fontWeight: FontWeight.w700,
color: _text1)),
Text(sub, style: TextStyle(fontSize: 11, color: _text3)),
],
),
),
const SizedBox(width: 8),
Text(val,
style: TextStyle(
fontSize: 12.5,
fontWeight: FontWeight.w800,
fontFeatures: const [FontFeature.tabularFigures()],
color: val.startsWith('---') ? _text3 : _accent,
)),
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
fontSize: 11.5,
fontWeight: FontWeight.w800,
letterSpacing: 0.9,
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

return AnimatedContainer(
duration: const Duration(milliseconds: 250),
padding: const EdgeInsets.all(15),
decoration: BoxDecoration(
color: _surface,
borderRadius: BorderRadius.circular(22),
border: Border.all(
color: status == 'err'
? _error
: (status == 'warn' ? _warning : _border),
width: (status == 'err' || status == 'warn') ? 1.5 : 1.0,
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
fontSize: 10.5,
fontWeight: FontWeight.w700,
letterSpacing: 0.4,
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
fontSize: 24,
fontWeight: FontWeight.w800,
fontFeatures: const [FontFeature.tabularFigures()],
color: valColor,
letterSpacing: -0.6,
),
),
TextSpan(
text: ' $unit',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w600,
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
fontSize: 10.5,
fontWeight: FontWeight.w600,
color: _text3),
),
),
],
),
);
}
  // ===== ВКЛАДКА 2: АНАЛИЗ (СНИФФЕР, АДАПТАЦИИ, РУЧНЫЕ ПРОТОКОЛЫ) =====
  Widget _buildTestsTab() {
    final isCold = _ect == null || _ect! < 70;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionHeader('ИНЖЕНЕРНЫЙ СНИФФЕР М86'),
        _testCard(
          icon: Icons.radar_rounded,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: 'Сниффер HEX-дампов (0904 / 2101 / 2102 / 2103)',
          desc:
          'Снимает и копирует в буфер полные HEX-ответы для сверки карты байтов прошивки. Не мутирует живые значения.',
          status: _isRunningSniffer ? TestStatus.running : TestStatus.pending,
          statusText: _snifferDump,
          buttonLabel: _isRunningSniffer
              ? 'Идёт чтение...'
              : 'Снять HEX-дамп (в буфер)',
          isRunning: _isRunningSniffer,
          onPressed: _isRunningSniffer ? null : _runM86HexSniffer,
        ),
        const SizedBox(height: 20),
        _sectionHeader('ЗАВОДСКИЕ ПРОЦЕДУРЫ (ЛИСТ 4–5)'),
        _testCard(
          icon: Icons.timer_outlined,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: '1. Адаптация нуля ДЗ (30+10 сек по Stopwatch)',
          desc:
          'Зажигание ВКЛ, мотор ЗАГЛУШЕН, ОЖ 5..100°C. Контролирует прокрутку, педаль и напряжение (P1564/P1579).',
          status: _isRunningThrottleAdapt
              ? TestStatus.running
              : (_throttleAdaptStatus.startsWith('✅')
              ? TestStatus.ok
              : _throttleAdaptStatus.startsWith('⛔')
              ? TestStatus.error
              : TestStatus.pending),
          statusText: _throttleAdaptStatus,
          buttonLabel: _isRunningThrottleAdapt
              ? 'Остановить таймер'
              : 'Запустить адаптацию ДЗ (40 сек)',
          isRunning: _isRunningThrottleAdapt,
          onPressed: _runThrottleAdaptationMaster,
        ),
        const SizedBox(height: 16),
        _testCard(
          icon: Icons.settings_backup_restore_rounded,
          iconColor: _success,
          iconBg: _successSoft,
          title: '2. Трекер обучения шкива ДПКВ (6 циклов)',
          desc:
          'Лист 5: прогрейте 60–90°C, на 2-й передаче до 4000 об/мин, торможение двигателем до 1000 об/мин × 6.',
          status: _isTrackingPulleyLearn
              ? TestStatus.running
              : (_flagPulleyLearned == true
              ? TestStatus.ok
              : TestStatus.pending),
          statusText:
          'Флаг ЭБУ: ${_flagPulleyLearned == null ? "---" : (_flagPulleyLearned! ? "ДА (Обучен)" : "НЕТ")} · Циклов: $_pulleyBrakingCount / 6\n$_pulleyTrackerStatus',
          buttonLabel: _isTrackingPulleyLearn
              ? 'Остановить трекер'
              : 'Включить трекер 6 торможений',
          isRunning: _isTrackingPulleyLearn,
          onPressed: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isTrackingPulleyLearn = !_isTrackingPulleyLearn;
              if (_isTrackingPulleyLearn) {
                _pulleyBrakingCount = 0;
                _pulleyReached4000 = false;
                _pulleyTrackerStatus =
                'Трекер активен (0/6): разгонитесь на 2-й до 4000 об/мин.';
              }
            });
          },
        ),
        const SizedBox(height: 20),
        _sectionHeader('РУЧНЫЕ ПРОТОКОЛЫ'),
        _testCard(
          icon: Icons.compare_arrows_rounded,
          iconColor: _success,
          iconBg: _successSoft,
          title: 'Концевики педалей: ВСППС и ВСТ 1/2',
          desc:
          'Лист 12, 13, 25: сцепление через ВСМ по CAN. ВСТ 1 (C4) и ВСТ 2 (C5) — безопасность Е-Газа.',
          status: _isRunningPedalSwitchTest
              ? TestStatus.running
              : (_pedalSwitchTestStatus.startsWith('✅')
              ? TestStatus.ok
              : _pedalSwitchTestStatus.startsWith('❌')
              ? TestStatus.error
              : _pedalSwitchTestStatus.startsWith('⚠️')
              ? TestStatus.warning
              : TestStatus.pending),
          statusText: _pedalSwitchTestStatus,
          buttonLabel: _isRunningPedalSwitchTest
              ? 'Остановить опрос'
              : 'Проверить педали (15 сек)',
          isRunning: _isRunningPedalSwitchTest,
          onPressed: _runPedalSwitchesTest,
        ),
        const SizedBox(height: 16),
        _testCard(
          icon: Icons.air_rounded,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: 'Подсос воздуха vs Форсунки',
          desc:
          'Быстрый опрос коррекций на ХХ и в коридоре 2000–3500 об/мин. Отличает негерметичность впуска от нехватки давления ЭБН.',
          warningBanner: isCold
              ? '⛔ Мотор не прогрет (${_ect ?? 0}°C). Прогрейте до 70°C!'
              : null,
          status: _isRunningLeakTest
              ? TestStatus.running
              : (_leakTestStatus.startsWith('✅')
              ? TestStatus.ok
              : _leakTestStatus.startsWith('⚠️')
              ? TestStatus.warning
              : _leakTestStatus.startsWith('⛔')
              ? TestStatus.error
              : TestStatus.pending),
          statusText: _leakTestStatus,
          buttonLabel: _isRunningLeakTest
              ? 'Остановить тест'
              : 'Запустить тест впуска',
          isRunning: _isRunningLeakTest,
          onPressed:
          (isCold && !_isRunningLeakTest) ? null : _runAirLeakAutoTest,
        ),
        const SizedBox(height: 16),
        _testCard(
          icon: Icons.battery_charging_full_rounded,
          iconColor: _warning,
          iconBg: _warningSoft,
          title: 'Утренний пуск и просадка АКБ (18 сек)',
          desc:
          'Перехватывает просадку стартера, сверяет ДТОЖ/ДТВ на холодном моторе (<45°C) с погодой.',
          status: _isRunningStartTest
              ? TestStatus.running
              : (_startTestStatus.startsWith('✅')
              ? TestStatus.ok
              : _startTestStatus.startsWith('⚠️')
              ? TestStatus.warning
              : TestStatus.pending),
          statusText: _startTestStatus,
          buttonLabel: _isRunningStartTest
              ? 'Остановить запись'
              : 'Запустить тест пуска (18 сек)',
          isRunning: _isRunningStartTest,
          onPressed: _runColdStartTest,
        ),
        const SizedBox(height: 16),
        _testCard(
          icon: Icons.analytics_outlined,
          iconColor: _success,
          iconBg: _successSoft,
          title:
          'Mode \$06: УДК / ДДК / Катализатор${_mode06NotSupported ? " (не подд.)" : ""}',
          desc:
          'Размах УДК 0,18–0,95 В, точный хронометраж периода (<1,8 с) за 20 циклов × 200 мс, стабильность ДДК (0,10–0,95 В), фактор старения < 0,45.',
          status: _isRunningMode06Test
              ? TestStatus.running
              : (_mode06TestStatus.startsWith('✅')
              ? TestStatus.ok
              : _mode06TestStatus.startsWith('❌')
              ? TestStatus.error
              : _mode06TestStatus.startsWith('⚠️')
              ? TestStatus.warning
              : TestStatus.pending),
          statusText: _mode06TestStatus,
          buttonLabel: _isRunningMode06Test
              ? 'Идёт опрос Mode \$06...'
              : 'Проверить ДК1 / ДК2 / Катализатор',
          isRunning: _isRunningMode06Test,
          onPressed: _isRunningMode06Test ? null : _runMode06AndCatTest,
        ),
        const SizedBox(height: 16),
        _testCard(
          icon: Icons.precision_manufacturing_rounded,
          iconColor: _accent,
          iconBg: _accentSoft,
          title: 'М86: Пропуски / Перетечки / АЦП (21 01 / 21 02)',
          desc:
          'Счётчики пропусков по цилиндрам, перетечки через закрытый дроссель 3–5 кг/ч, детонация, КПА, ДПДЗ 1/2 (5,0±0,1 В).',
          status: _isRunningM86DeepTest
              ? TestStatus.running
              : (_m86DeepTestStatus.startsWith('✅')
              ? TestStatus.ok
              : _m86DeepTestStatus.startsWith('❌')
              ? TestStatus.error
              : _m86DeepTestStatus.startsWith('⚠️')
              ? TestStatus.warning
              : TestStatus.pending),
          statusText: _m86DeepTestStatus,
          buttonLabel: _isRunningM86DeepTest
              ? 'Чтение 21 01 / 21 02...'
              : 'Запустить опрос М86',
          isRunning: _isRunningM86DeepTest,
          onPressed:
          _isRunningM86DeepTest ? null : _runM86DeepDiagnosticTest,
        ),
      ],
    );
  }

  // ===== ВКЛАДКА 3: АКТИВНЫЕ ТЕСТЫ ИМ =====
  Widget _buildActiveTestsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Сброс ЭБУ
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: _warningSoft,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _warning, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                    Icon(Icons.restart_alt_rounded, color: _warning),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Сброс ЭБУ с инициализацией',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _text1)),
                        Text('Лист 4, 19, 38 · Двухэтапная защита',
                            style: TextStyle(
                                fontSize: 11.5, color: _text2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _confirmAndRunEcuInitializationReset,
                  icon: const Icon(Icons.security_rounded, size: 18),
                  label: const Text('Выполнить сброс ЭБУ (2 шага)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _warning,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Статус ИМ
        Container(
          padding: const EdgeInsets.all(15),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _isRunningActuatorTest ? _accent : _border,
                width: _isRunningActuatorTest ? 1.5 : 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      _isRunningActuatorTest
                          ? Icons.bolt_rounded
                          : Icons.terminal_rounded,
                      color: _accent,
                      size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Статус ИМ: $_activeActuatorName',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _text1)),
                  ),
                  if (_isRunningActuatorTest)
                    TextButton(
                      onPressed: () =>
                          setState(() => _isRunningActuatorTest = false),
                      child: Text('СТОП',
                          style: TextStyle(
                              color: _error,
                              fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_actuatorStatusLog,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: _text2,
                      height: 1.35)),
            ],
          ),
        ),
        // Баланс цилиндров
        _sectionHeader('БАЛАНС ЦИЛИНДРОВ (ЛИСТ 42)'),
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Поочерёдное отключение форсунок 1–4 на ХХ с замером ΔRPM:',
                  style: TextStyle(
                      fontSize: 12, color: _text2, height: 1.35)),
              const SizedBox(height: 12),
              Row(
                children: [1, 2, 3, 4].map((cyl) {
                  return Expanded(
                    child: Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 3),
                      child: ElevatedButton(
                        onPressed: _isRunningActuatorTest
                            ? null
                            : () => _executeActuatorTest(
                          title:
                          'Отключение форсунки Цил. $cyl',
                          warningText:
                          'ЭБУ прекратит подачу топлива через форсунку $cyl-го цилиндра на 5 секунд.\n\n'
                              'На исправном цилиндре обороты просядут на 60–120 об/мин. Если почти не изменятся — цилиндр не работает.',
                          conditionsText:
                          '⚠️ УСЛОВИЯ (Лист 42): Двигатель на ХХ, КПП на нейтрали, стояночный тормоз включён.',
                          kwpCmdOn: '300$cyl' '0700',
                          kwpCmdOff: '300$cyl' '00',
                          udsCmdOn: '2F010$cyl' '0300',
                          udsCmdOff: '2F010$cyl' '00',
                          holdSeconds: 5,
                          requireEngineRunning: true,
                          measureRpmDrop: true,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentSoft,
                          foregroundColor: _accent,
                          elevation: 0,
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                        ),
                        child: Text('Форс. $cyl',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        // Сетка ИМ
        _sectionHeader('ОХЛАЖДЕНИЕ, ТОПЛИВО, ВПУСК (ЛИСТ 42–43)'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.22,
          children: [
            _actuatorGridButton(
              icon: Icons.wind_power_rounded,
              danger: false,
              title: 'Вентилятор 1 (Малая)',
              subtitle: 'X1.1/H2 · 102°C',
              onTap: () => _executeActuatorTest(
                title: 'Реле вентилятора 1 (малая скорость)',
                warningText:
                'ЭБУ замкнёт X1.1/H2 и включит 1-ю скорость вентилятора на 6 секунд (Лист 21, 42).\n\n'
                    'Берегите руки от лопастей!',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 42): Зажигание ВКЛ. Контролируйте на слух.',
                kwpCmdOn: '30110701',
                kwpCmdOff: '301100',
                udsCmdOn: '2F02010301',
                udsCmdOff: '2F020100',
                holdSeconds: 6,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.cyclone_rounded,
              danger: true,
              title: 'Вентилятор 2 (Макс.)',
              subtitle: 'X1.1/H3 · 103°C',
              onTap: () => _executeActuatorTest(
                title: 'Реле вентилятора 2 (макс. скорость)',
                warningText:
                'ЭБУ замкнёт X1.1/H3 и включит 2-ю скорость на 6 секунд (Лист 22, 42).\n\n'
                    'Высокий пусковой ток (F79 40А). Не приближайтесь к крыльчатке!',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 42): Зажигание ВКЛ, АКБ заряжена.',
                kwpCmdOn: '30120701',
                kwpCmdOff: '301200',
                udsCmdOn: '2F02020301',
                udsCmdOff: '2F020200',
                holdSeconds: 6,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.local_gas_station_rounded,
              danger: true,
              title: 'Реле бензонасоса',
              subtitle: 'X1.1/J4 · 364–400 кПа',
              onTap: () => _executeActuatorTest(
                title: 'Реле ЭБН (Карта А-6)',
                warningText:
                'ЭБУ включит электробензонасос (X1.1/J4, реле К7, F26 15А) на 10 секунд на заглушенном двигателе.\n\n'
                    'Давление на штуцере рампы должно быть 364–400 кПа.',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 42, 67): Зажигание ВКЛ, двигатель СТРОГО ЗАГЛУШЕН!',
                kwpCmdOn: '30130701',
                kwpCmdOff: '301300',
                udsCmdOn: '2F02030301',
                udsCmdOff: '2F020300',
                holdSeconds: 10,
                requireEngineStopped: true,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.filter_alt_rounded,
              danger: false,
              title: 'Клапан адсорбера КПА',
              subtitle: 'X1.1/J2 · Продувка',
              onTap: () => _executeActuatorTest(
                title: 'Клапан продувки адсорбера (КПА)',
                warningText:
                'ЭБУ подаст импульсный сигнал (16/32 Гц) на КПА (X1.1/J2) на 6 секунд.\n\n'
                    'Исправный клапан должен издавать чёткие щелчки.',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 43): Зажигание ВКЛ или двигатель на ХХ.',
                kwpCmdOn: '30140764',
                kwpCmdOff: '301400',
                udsCmdOn: '2F02040364',
                udsCmdOff: '2F020400',
                holdSeconds: 6,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.swap_calls_rounded,
              danger: false,
              title: 'Заслонки длины впуска',
              subtitle: 'X1.2/F2 · Геометрия',
              onTap: () => _executeActuatorTest(
                title: 'Клапан длины впускного коллектора',
                warningText:
                'ЭБУ активирует клапан пневмопривода заслонок (X1.2/F2) на 5 секунд.\n\n'
                    'При работающем двигателе шток должен втянуться за счёт разряжения.',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 43): Двигатель на ХХ (нужно разряжение в ресивере).',
                kwpCmdOn: '30150701',
                kwpCmdOff: '301500',
                udsCmdOn: '2F02050301',
                udsCmdOff: '2F020500',
                holdSeconds: 5,
                requireEngineRunning: true,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.ac_unit_rounded,
              danger: false,
              title: 'Муфта кондиционера',
              subtitle: 'X1.1/F2 · Реле К28',
              onTap: () => _executeActuatorTest(
                title: 'Реле муфты кондиционера',
                warningText:
                'ЭБУ замкнёт X1.1/F2 для проверки срабатывания муфты компрессора на слух (Лист 28).',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 43): Двигатель на ХХ, кнопка конд. включена, фреон в норме.',
                kwpCmdOn: '30160701',
                kwpCmdOff: '301600',
                udsCmdOn: '2F02060301',
                udsCmdOff: '2F020600',
                holdSeconds: 4,
                requireEngineRunning: true,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.lightbulb_outline_rounded,
              danger: false,
              title: 'Лампа MIL (Check Engine)',
              subtitle: 'Проверка по CAN (Лист 43)',
              onTap: () => _executeActuatorTest(
                title: 'Индикатор неисправности MIL',
                warningText:
                'ЭБУ отправит по CAN команду зажечь «Check Engine» на 5 секунд (Лист 36, 43).',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 43): Зажигание ВКЛ. Визуально проконтролируйте свечение.',
                kwpCmdOn: '30170701',
                kwpCmdOff: '301700',
                udsCmdOn: '2F02070301',
                udsCmdOff: '2F020700',
                holdSeconds: 5,
              ),
            ),
            _actuatorGridButton(
              icon: Icons.speed_rounded,
              danger: false,
              title: 'Тест ХХ (+200 об/мин)',
              subtitle: 'Подъём до ~1050 об/мин',
              onTap: () => _executeActuatorTest(
                title: 'Управление оборотами ХХ',
                warningText:
                'ЭБУ приоткроет ЭДП для подъёма оборотов с 840 до ~1050 об/мин на 6 секунд (Лист 43).',
                conditionsText:
                '⚠️ УСЛОВИЯ (Лист 43): Двигатель прогрет и на ХХ, КПП на нейтрали, газ отпущен.',
                kwpCmdOn: '30180701',
                kwpCmdOff: '301800',
                udsCmdOn: '2F02080301',
                udsCmdOff: '2F020800',
                holdSeconds: 6,
                requireEngineRunning: true,
                measureRpmDrop: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===== M3: СЕТКА ИМ С ВИЗУАЛЬНЫМ DISABLED =====
  Widget _actuatorGridButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final isDisabled = _isRunningActuatorTest;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: _accent, size: 19),
                  ),
                  Icon(
                    danger
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: danger ? _warning : _text3,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _text1),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: _text3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== M4: TEST CARD C ENUM TestStatus =====
  Widget _testCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String desc,
    String? warningBanner,
    required TestStatus status,
    required String statusText,
    required String buttonLabel,
    required bool isRunning,
    required VoidCallback? onPressed,
  }) {
    Color statusColor;
    Color statusBg;
    switch (status) {
      case TestStatus.ok:
        statusColor = _success;
        statusBg = _successSoft;
        break;
      case TestStatus.warning:
        statusColor = _warning;
        statusBg = _warningSoft;
        break;
      case TestStatus.error:
        statusColor = _error;
        statusBg = _errorSoft;
        break;
      case TestStatus.running:
        statusColor = _accent;
        statusBg = _accentSoft;
        break;
      case TestStatus.pending:
        statusColor = _text1;
        statusBg = _surface2;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
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
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _text1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(desc,
              style: TextStyle(
                  fontSize: 12, color: _text2, height: 1.35)),
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
                    color: _error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
                color: statusColor,
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
              label: Text(buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
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

  // ===== ВКЛАДКА 4: ЖУРНАЛ (N8 — очистка чистит и _blackBox) =====
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _text2)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label:
                const Text('CSV', style: TextStyle(fontSize: 12)),
                onPressed: _exportCsvAndSaveFile,
              ),
              IconButton(
                icon:
                Icon(Icons.delete_sweep_outlined, color: _text2),
                tooltip: 'Очистить журнал и black-box',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: _surface,
                      title: const Text('Очистить всё?'),
                      content: const Text(
                          'Журнал событий и накопленный black-box будут удалены. Корзины коррекций сохранятся.'),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, false),
                            child: const Text('Отмена')),
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, true),
                            child: Text('Очистить',
                                style:
                                TextStyle(color: _error))),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  setState(() {
                    _nuanceLog.clear();
                    _lastNuanceTimes.clear();
                    _blackBox.clear();
                  });
                  _savePersistedState();
                },
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
                  'Журнал чист.\nПовторяющиеся события группируются со счётчиком HZ (Лист 44) и сохраняются в память.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: _text2)),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 8),
            itemCount: _nuanceLog.length,
            itemBuilder: (ctx, i) {
              final e = _nuanceLog[i];
              final color =
              e.severity == NuanceSeverity.critical
                  ? _error
                  : (e.severity ==
                  NuanceSeverity.warning
                  ? _warning
                  : _accent);
              final bg =
              e.severity == NuanceSeverity.critical
                  ? _errorSoft
                  : (e.severity ==
                  NuanceSeverity.warning
                  ? _warningSoft
                  : _accentSoft);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                      child: Icon(
                        e.severity ==
                            NuanceSeverity.critical
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.title,
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight.w800,
                                      fontSize: 14,
                                      color: color),
                                ),
                              ),
                              if (e.hzCount > 1)
                                Container(
                                  margin:
                                  const EdgeInsets.only(
                                      right: 6),
                                  padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius:
                                    BorderRadius.circular(
                                        8),
                                  ),
                                  child: Text(
                                      'HZ: ${e.hzCount}',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight:
                                          FontWeight.w800,
                                          color: color)),
                                ),
                              Text(e.timeStr,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: _text3)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(e.description,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _text1,
                                  height: 1.35)),
                          if (e.snapshot.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: e.snapshot.entries
                                  .map((entry) {
                                return Container(
                                  padding:
                                  const EdgeInsets
                                      .symmetric(
                                      horizontal: 8,
                                      vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _surface2,
                                    borderRadius:
                                    BorderRadius
                                        .circular(8),
                                  ),
                                  child: Text(
                                      '${entry.key}: ${entry.value}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                          FontWeight
                                              .w700,
                                          color: _text2)),
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

  // ===== ВКЛАДКА 5: DTC + паспорт ЭБУ + поиск с debounce =====
  Widget _buildDtcTab() {
    final query = _dtcSearchQuery.trim().toUpperCase();
    final filteredReference =
    kM86DtcDatabase.entries.where((e) {
      if (query.isEmpty) return true;
      return e.key.toUpperCase().contains(query) ||
          e.value.toUpperCase().contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isConnected ? _readDtcAndEcuId : null,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Прочитать DTC и паспорт'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _isConnected ? _clearDtcCodes : null,
              icon: Icon(Icons.delete_forever_rounded,
                  color: _error),
              tooltip: 'Сброс DTC (Mode 04, 2 шага)',
              style: IconButton.styleFrom(
                backgroundColor: _errorSoft,
                padding: const EdgeInsets.all(15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _confirmAndRunEcuInitializationReset,
              icon: Icon(Icons.restart_alt_rounded,
                  color: _warning),
              tooltip: 'Сброс ЭБУ с инициализацией (2 шага)',
              style: IconButton.styleFrom(
                backgroundColor: _warningSoft,
                padding: const EdgeInsets.all(15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionHeader('ПАСПОРТ ЭСУД'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('АРХИТЕКТУРА ЭБУ',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _text3)),
              const SizedBox(height: 4),
              Text(_ecuType,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _text1)),
              const SizedBox(height: 14),
              Text('ИДЕНТИФИКАТОР КАЛИБРОВКИ (ПЗУ)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _text3)),
              const SizedBox(height: 4),
              Text(_ecuId,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _accent)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionHeader('КОДЫ В ПАМЯТИ (Mode \$02)'),
        if (_dtcList.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _successSoft,
                      borderRadius:
                      BorderRadius.circular(12)),
                  child: Icon(Icons.check_circle_rounded,
                      color: _success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                      'Активных кодов в ОЗУ нет (Mode 03/07 чистые).',
                      style: TextStyle(
                          fontSize: 13, color: _text2)),
                ),
              ],
            ),
          )
        else
          ..._dtcList.map((code) {
            final isPrio = kPriorityCodes.contains(code);
            final desc = kM86DtcDatabase[code] ??
                'Код неисправности OBD-II (см. ТИ 3100.25100.12056)';
            return InkWell(
              onTap: () => _showDtcFreezeFrameSheet(code),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isPrio ? _errorSoft : _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _error,
                      width: isPrio ? 1.8 : 1.0),
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: _error),
                        const SizedBox(width: 10),
                        Text(code,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _text1)),
                        if (isPrio) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding:
                            const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3),
                            decoration: BoxDecoration(
                              color: _error,
                              borderRadius:
                              BorderRadius.circular(8),
                            ),
                            child: const Text(
                                'ПРИОРИТЕТ (Лист 29)',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight:
                                    FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ],
                        const Spacer(),
                        Text('Стоп-кадр ➔',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _accent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(desc,
                        style: TextStyle(
                            fontSize: 13,
                            color: _text1,
                            height: 1.35)),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 22),
        _sectionHeader(
            'СПРАВОЧНИК DTC (${filteredReference.length} из ${kM86DtcDatabase.length})'),
        TextField(
          onChanged: (val) {
            _dtcSearchDebounce?.cancel();
            _dtcSearchDebounce = Timer(
                const Duration(milliseconds: 250),
                    () => setState(() => _dtcSearchQuery = val));
          },
          style: TextStyle(fontSize: 13, color: _text1),
          decoration: InputDecoration(
            hintText:
            'Поиск по коду или узлу (P0504, ДПДЗ, КПА, CAN)...',
            hintStyle:
            TextStyle(fontSize: 12.5, color: _text3),
            prefixIcon: Icon(Icons.search_rounded,
                color: _text2, size: 20),
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _border),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: filteredReference.map((e) {
              return InkWell(
                onTap: () => _showDtcFreezeFrameSheet(e.key),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          e.key,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _accent),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          style: TextStyle(
                              fontSize: 12, color: _text2),
                        ),
                      ),
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: _text3),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ===== M1 + M2: ОСЦИЛЛОГРАФ УДК vs ДДК =====
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
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const maxScaleV = 1.80;
    for (final v in [0.20, 0.70, 0.95, 1.70]) {
      final y =
          size.height - ((v / maxScaleV).clamp(0.0, 1.0) * size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    void drawWave(List<double> pts, Color color) {
      if (pts.length < 2) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // M1: denom по фактической длине, не хардкод 39.0
      final denom = (pts.length - 1).clamp(1, 1 << 30);
      final path = Path();
      for (int i = 0; i < pts.length; i++) {
        final x = (i / denom) * size.width;
        final normY = (pts[i] / maxScaleV).clamp(0.0, 1.0);
        final y = size.height - (normY * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawWave(s1, s1Color);
    drawWave(s2, s2Color);
  }

  // M2: перерисовка только при реальных изменениях
  @override
  bool shouldRepaint(covariant _O2OscilloscopePainter oldDelegate) =>
      oldDelegate.s1 != s1 ||
          oldDelegate.s2 != s2 ||
          oldDelegate.s1Color != s1Color ||
          oldDelegate.s2Color != s2Color ||
          oldDelegate.gridColor != gridColor;
}

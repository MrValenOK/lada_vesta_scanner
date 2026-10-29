// lib/core/theme.dart
// Единый core-файл: конвертация OKLCH, токены AppColors, шкалы, адаптив, темы.
// Перенос дизайна vestascan-v4.html по bridge-документу (уточнения от 2026-10-29).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// OKLCH → Flutter Color (sRGB). L: 0.0–1.0, C: 0.0–0.4, H: 0–360°.
/// Единственная точка конвертации: hex-цвета вне этого файла запрещены.
Color oklchToColor(double l, double c, double h) {
  final hRad = h * math.pi / 180.0;
  final a = c * math.cos(hRad);
  final b = c * math.sin(hRad);

  final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

  final lCubed = l_ * l_ * l_;
  final mCubed = m_ * m_ * m_;
  final sCubed = s_ * s_ * s_;

  final r = 4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed;
  final g = -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed;
  final bl = -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed;

  double gamma(double x) {
    if (x <= 0.0031308) return 12.92 * x;
    return 1.055 * math.pow(x, 1.0 / 2.4) - 0.055;
  }
  return Color.fromRGBO(
    (gamma(r.clamp(0.0, 1.0)) * 255).round().clamp(0, 255),
    (gamma(g.clamp(0.0, 1.0)) * 255).round().clamp(0, 255),
    (gamma(bl.clamp(0.0, 1.0)) * 255).round().clamp(0, 255),
    1.0,
  );
}

/// Аналог CSS light-dark(): выбор OKLCH-тройки по теме.
Color ldColor(Brightness brightness, (double, double, double) light, (double, double, double) dark) {
  final t = brightness == Brightness.dark ? dark : light;
  return oklchToColor(t.$1, t.$2, t.$3);
}

/// Токены дизайна. OKLCH → sRGB вычисляется один раз (late final), не в геттерах.
class AppColors extends ThemeExtension<AppColors> {
  AppColors(this.brightness);

  final Brightness brightness;

  static const double _accentL = 0.78;
  static const double _accentC = 0.155;
  static const double _accentHue = 75; // amber; пресеты: teal 170°, blue 250°

  // Акцент
  late final Color accent = oklchToColor(_accentL, _accentC, _accentHue);
  late final Color accentStrong = oklchToColor(_accentL - 0.08, _accentC, _accentHue);
  late final Color accentSoft = accent.withValues(alpha: 0.14);
  late final Color accentSofter = accent.withValues(alpha: 0.07);
  late final Color accentFg = oklchToColor(0.15, 0.010, _accentHue);
  late final Color onAccent = brightness == Brightness.dark
      ? oklchToColor(0.99, 0.002, _accentHue)
      : oklchToColor(0.15, 0.008, _accentHue);

  // Статусы (одна перцептивная громкость)
  late final Color success = oklchToColor(0.75, 0.165, 150);
  late final Color warning = oklchToColor(0.80, 0.150, 75);
  late final Color error = oklchToColor(0.70, 0.190, 25);
  late final Color info = oklchToColor(0.70, 0.140, 245);
  late final Color successSoft = success.withValues(alpha: 0.14);
  late final Color warningSoft = warning.withValues(alpha: 0.14);
  late final Color errorSoft = error.withValues(alpha: 0.14);
  late final Color infoSoft = info.withValues(alpha: 0.14);

  // Нейтрали (тёплый графит, hue 95)
  late final Color bg = ldColor(brightness, (0.97, 0.003, 95), (0.14, 0.008, 95));
  late final Color surface = ldColor(brightness, (0.99, 0.001, 95), (0.19, 0.010, 95));
  late final Color surface2 = ldColor(brightness, (0.94, 0.004, 95), (0.25, 0.012, 95));
  late final Color surface3 = ldColor(brightness, (0.89, 0.006, 95), (0.31, 0.014, 95));
  late final Color border = ldColor(brightness, (0.88, 0.005, 95), (0.27, 0.012, 95));
  late final Color border2 = ldColor(brightness, (0.80, 0.008, 95), (0.36, 0.014, 95));
  late final Color text1 = ldColor(brightness, (0.20, 0.012, 95), (0.95, 0.005, 95));
  late final Color text2 = ldColor(brightness, (0.45, 0.012, 95), (0.73, 0.008, 95));
  late final Color text3 = ldColor(brightness, (0.60, 0.010, 95), (0.52, 0.010, 95));

  // Осциллограф (пара трасс color-blind safe)
  late final Color scopeBg = ldColor(brightness, (0.98, 0.002, 240), (0.11, 0.012, 240));
  late final Color scopeGrid = ldColor(brightness, (0.88, 0.005, 240), (0.25, 0.018, 240));
  late final Color scopeText = ldColor(brightness, (0.55, 0.010, 240), (0.58, 0.012, 240));
  late final Color trace1 = oklchToColor(0.70, 0.155, 250); // УДК
  late final Color trace2 = oklchToColor(0.72, 0.150, 160); // ДДК
  late final Color bandUdk = trace1.withValues(alpha: 0.10);
  late final Color bandDdk = trace2.withValues(alpha: 0.14);
  late final Color bandRef = warning.withValues(alpha: 0.10);

  // Тени
  late final List<BoxShadow> sh1 = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1)),
  ];
  late final List<BoxShadow> sh2 = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 16, offset: const Offset(0, 4)),
  ];
  late final List<BoxShadow> sh3 = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 32, offset: const Offset(0, 12)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2)),
  ];

  @override
  AppColors copyWith({Brightness? brightness}) => AppColors(brightness ?? this.brightness);

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other; // токен-палитры не смешиваем в sRGB (bridge §1.4)
  }
}

/// Доступ из виджетов: `context.appColors`.
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

/// Шкала отступов (4-pt grid).
class S {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double tt = 44; // минимальная зона касания
}

/// Шкала типографики.
class T {
  static const double cap = 11;
  static const double sm = 13;
  static const double body = 15;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 28;
  static const double xxl = 36;
}

/// Шкала радиусов.
class R {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Классы ширины (аналог container queries — от LayoutBuilder.constraints).
enum DeviceSize { phone, tablet, desktop }

DeviceSize classifyDevice(double width) {
  if (width < 480) return DeviceSize.phone;
  if (width < 900) return DeviceSize.tablet;
  return DeviceSize.desktop;
}

/// Темы: Graphite (dark) / Paper (light). Имена lightTheme/darkTheme зафиксированы в main.dart.
abstract class AppTheme {
  static final ThemeData lightTheme = _build(Brightness.light);
  static final ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final c = AppColors(b);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: b,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accent,
        onSecondary: c.onAccent,
        error: c.error,
        onError: Colors.white,
        surface: c.surface,
        onSurface: c.text1,
      ),
      textTheme: _textTheme(c),
      extensions: [c],
    );
  }

  static TextTheme _textTheme(AppColors c) {
    TextStyle m(double size, FontWeight w, {double? ls, Color? color}) => GoogleFonts.manrope(
          fontSize: size, fontWeight: w, color: color ?? c.text1, letterSpacing: ls,
        );
    return TextTheme(
      displayLarge: m(36, FontWeight.w800),
      displayMedium: m(28, FontWeight.w800),
      titleLarge: m(18, FontWeight.w800, ls: -0.3),
      titleMedium: m(15, FontWeight.w800),
      bodyLarge: m(15, FontWeight.w400),
      bodyMedium: m(13, FontWeight.w600, color: c.text2),
      labelSmall: m(11, FontWeight.w700, ls: 0.5, color: c.text3),
    );
  }

  /// Моно-стиль для числовых значений (tabular figures) — для плашек/осциллографа.
  static TextStyle mono({double size = 14, FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

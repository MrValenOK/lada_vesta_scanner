import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Фон и поверхности (Graphite Soft)
  static const darkBg = Color(0xFF0E1116);
  static const darkSurface = Color(0xFF151A21);
  static const darkSurface2 = Color(0xFF1D242E);
  static const darkBorder = Color(0xFF2A323E);
  
  // Текст
  static const darkText1 = Color(0xFFE9EDF2);
  static const darkText2 = Color(0xFFA3ADBA);
  static const darkText3 = Color(0xFF6E7A89);

  // Акцент (Amber)
  static const darkAccent = Color(0xFFFBBF24);
  static const darkAccentSoft = Color(0xFF2D2618);

  // Статусы
  static const success = Color(0xFF43D68B);
  static const successSoft = Color(0xFF142E24);
  static const warning = Color(0xFFF2B44E);
  static const warningSoft = Color(0xFF2E2416);
  static const error = Color(0xFFFF7A76);
  static const errorSoft = Color(0xFF321C1E);

  // Осциллограф и зоны
  static const darkScopeBg = Color(0xFF10151D);
  static const darkScopeGrid = Color(0xFF243040);
  static const darkTrace1 = Color(0xFF6FB1FF); // УДК
  static const darkTrace2 = Color(0xFF43D68B); // ДДК
  static const bandUdk = Color(0x1A6FB1FF);   // Зона УДК
  static const bandDdk = Color(0x2443D68B);   // Окно ДДК
  static const bandRef = Color(0x1AFBBF24);   // Опорная 1.2-1.7
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg,
      primaryColor: AppColors.darkAccent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkAccent,
        surface: AppColors.darkSurface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.manrope(color: AppColors.darkText1),
        bodyMedium: GoogleFonts.manrope(color: AppColors.darkText2),
        bodySmall: GoogleFonts.manrope(color: AppColors.darkText3, fontSize: 12),
        labelSmall: GoogleFonts.manrope(
          color: AppColors.darkText3,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
      fontFamily: GoogleFonts.manrope().fontFamily,
      useMaterial3: true,
    );
  }
}
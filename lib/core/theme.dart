import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Светлая тема
  static const lightBg = Color(0xFFF2F5F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFEAEFF4);
  static const lightBorder = Color(0xFFD8E0E8);
  static const lightText1 = Color(0xFF0E141B);
  static const lightText2 = Color(0xFF4C5A6B);
  static const lightText3 = Color(0xFF7A8798);

  // Темная тема
  static const darkBg = Color(0xFF0E1116);
  static const darkSurface = Color(0xFF151A21);
  static const darkSurface2 = Color(0xFF1D242E);
  static const darkBorder = Color(0xFF2A323E);
  static const darkText1 = Color(0xFFE9EDF2);
  static const darkText2 = Color(0xFFA3ADBA);
  static const darkText3 = Color(0xFF6E7A89);

  // Статусы
  static const success = Color(0xFF43D68B);
  static const warning = Color(0xFFF2B44E);
  static const error = Color(0xFFFF7A76);

  // Графики Осциллографа
  static const darkScopeBg = Color(0xFF10151D);
  static const darkScopeGrid = Color(0xFF243040);
  static const trace1 = Color(0xFF6FB1FF);
  static const trace2 = Color(0xFF43D68B);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg,
      primaryColor: const Color(0xFFFBBF24), // Amber
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFBBF24),
        surface: AppColors.darkSurface,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(color: AppColors.darkText1, fontWeight: FontWeight.w800),
        titleLarge: GoogleFonts.manrope(color: AppColors.darkText1, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        bodyLarge: GoogleFonts.manrope(color: AppColors.darkText1),
        bodyMedium: GoogleFonts.manrope(color: AppColors.darkText2, fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.manrope(color: AppColors.darkText3, letterSpacing: 0.5, fontWeight: FontWeight.bold),
      ),
      fontFamily: GoogleFonts.manrope().fontFamily,
      useMaterial3: true,
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      primaryColor: const Color(0xFFB45309), // Darker Amber for Light Mode
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFB45309),
        surface: AppColors.lightSurface,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.manrope(color: AppColors.lightText1, fontWeight: FontWeight.w800),
        titleLarge: GoogleFonts.manrope(color: AppColors.lightText1, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        bodyLarge: GoogleFonts.manrope(color: AppColors.lightText1),
        bodyMedium: GoogleFonts.manrope(color: AppColors.lightText2, fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.manrope(color: AppColors.lightText3, letterSpacing: 0.5, fontWeight: FontWeight.bold),
      ),
      fontFamily: GoogleFonts.manrope().fontFamily,
      useMaterial3: true,
    );
  }
}
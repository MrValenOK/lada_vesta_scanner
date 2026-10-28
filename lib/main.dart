import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'main_screen.dart';

void main() {
  runApp(
    // Обязательная обертка для Riverpod
    const ProviderScope(
      child: VestaScanApp(),
    ),
  );
}

class VestaScanApp extends StatelessWidget {
  const VestaScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VestaScan Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme, // Используем нашу новую темную тему
      home: const MainScreen(), // Открываем главный экран с вкладками
    );
  }
}
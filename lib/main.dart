import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'main_screen.dart'; // Подключаем новую оболочку

void main() {
  runApp(
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
      theme: AppTheme.lightTheme, // Для проверки темной темы поменяй на darkTheme
      home: const MainScreen(),
    );
  }
}
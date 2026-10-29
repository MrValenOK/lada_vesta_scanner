// lib/main.dart — VestaScan Pro V2.0
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'main_screen.dart';

void main() {
  runApp(const ProviderScope(child: VestaScanApp()));
}

class VestaScanApp extends StatelessWidget {
  const VestaScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VestaScan Pro V2.0',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/tests/tests_screen.dart';
import 'features/dtc/dtc_screen.dart';
import 'services/trip_calculator.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  // Создаем калькулятор здесь, чтобы он жил всё время работы приложения
  // и передавался на нужные экраны
  final TripCalculator _tripCalculator = TripCalculator();

  @override
  Widget build(BuildContext context) {
    // Список экранов для наших вкладок
    final screens = [
      DashboardScreen(tripCalculator: _tripCalculator),
      const TestsScreen(),
      JournalScreen(tripCalculator: _tripCalculator),
      const DtcScreen(),
    ];

    return Scaffold(
      // IndexedStack сохраняет состояние (графики не сбросятся при переключении)
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).textTheme.bodyMedium?.color,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Датчики'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Анализ'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Журнал'),
          BottomNavigationBarItem(icon: Icon(Icons.memory), label: 'Коды'),
        ],
      ),
    );
  }
}
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/obd_provider.dart';
import '../../services/trip_calculator.dart';
import 'widgets/trip_panel.dart';
import 'widgets/oscilloscope.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final TripCalculator tripCalculator;

  const DashboardScreen({super.key, required this.tripCalculator});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final obdState = ref.watch(obdProvider);
    final obdNotifier = ref.read(obdProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('VestaScan Pro', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: const Center(
              child: Text('М86 UDS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TripPanel(
                calculator: widget.tripCalculator,
                onReset: () {
                  setState(() {
                    widget.tripCalculator.reset();
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(
                'ТЕЛЕМЕТРИЯ LIVE',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _buildSensorCard(context, 'ОБОРОТЫ', '${obdState.liveData['rpm']?.toInt() ?? 0}', 'об/мин', true),
                    _buildSensorCard(context, 'ТЕМП. ОЖ', '${obdState.liveData['ect']?.toInt() ?? 0}', '°C', true),
                    _buildSensorCard(context, 'БОРТСЕТЬ', '14.10', 'В', false),
                    _buildSensorCard(context, 'STFT', '-3.9', '%', false),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ОСЦИЛЛОГРАФ',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Oscilloscope(
                  trace1: Queue<double>.from(obdState.trace1),
                  minValue: 0,
                  maxValue: 1500,
                  color1: const Color(0xFF6FB1FF),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: obdState.isPolling ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor,
        onPressed: () {
          if (obdState.isPolling) {
            obdNotifier.stopPolling();
          } else {
            obdNotifier.connect('00:00:00:00:00:00').then((success) {
              if (success) obdNotifier.startPolling();
            });
          }
        },
        child: Icon(
          obdState.isPolling ? Icons.stop : Icons.play_arrow,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildSensorCard(BuildContext context, String title, String value, String unit, bool isLive) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
          right: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
          left: BorderSide(color: isLive ? Colors.green : Colors.grey, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.speed, size: 14, color: Theme.of(context).textTheme.labelSmall?.color),
              const SizedBox(width: 4),
              Text(title, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono'),
              ),
              const SizedBox(width: 4),
              Text(unit, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
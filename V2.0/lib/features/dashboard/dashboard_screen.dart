// lib/features/dashboard/dashboard_screen.dart — телеметрия, БК, осциллограф.
// Карточки — в widgets/dashboard_cards.dart, OTA — в ota_flow.dart
// (лимит 400 строк/файл, AGENTS V2.0). Цвета — только токены AppColors.
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/obd_provider.dart';
import 'ota_flow.dart';
import 'widgets/dashboard_cards.dart';
import 'widgets/oscilloscope.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final st = ref.watch(obdProvider);
    final notifier = ref.read(obdProvider.notifier);
    final d = st.liveData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VestaScan Pro'),
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome, color: c.accent),
            tooltip: 'Скопировать ИИ-Снапшот',
            onPressed: () async {
              await notifier.copyAiSnapshotPrompt();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('🤖 ИИ-Снапшот скопирован в буфер обмена')));
            },
          ),
          IconButton(
            icon: Icon(Icons.cloud_download_outlined, color: c.accent),
            tooltip: 'Проверить обновления',
            onPressed: () => runOtaCheck(context),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: c.border),
            ),
            child: Center(child: Text('M86 UDS', style: AppTheme.mono(size: T.cap))),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, 90),
          children: [
            const ConnectionCard(),
            const SizedBox(height: S.s3),
            TripCard(calc: notifier.tripCalculator, onReset: notifier.resetTrip),
            const SizedBox(height: S.s4),
            Text('ТЕЛЕМЕТРИЯ LIVE', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: S.s2),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: S.s3,
              mainAxisSpacing: S.s3,
              childAspectRatio: 1.5,
              children: [
                SensorCard(
                    title: 'ОБОРОТЫ',
                    value: d['rpm']?.toInt().toString() ?? '---',
                    unit: 'об/мин',
                    isLive: true),
                SensorCard(
                    title: 'ТЕМП. ОЖ',
                    value: d['ect']?.toInt().toString() ?? '---',
                    unit: '°C',
                    isLive: true),
                SensorCard(
                    title: 'БОРТСЕТЬ',
                    value: d['volt']?.toStringAsFixed(2) ?? '---',
                    unit: 'В',
                    isLive: false),
                SensorCard(
                    title: 'STFT',
                    value: d['stft']?.toStringAsFixed(1) ?? '---',
                    unit: '%',
                    isLive: false),
                SensorCard(
                    title: 'LTFT',
                    value: d['ltft']?.toStringAsFixed(1) ?? '---',
                    unit: '%',
                    isLive: false),
                SensorCard(
                    title: 'НАГРУЗКА',
                    value: d['load']?.toStringAsFixed(1) ?? '---',
                    unit: '%',
                    isLive: true),
                SensorCard(
                    title: 'СКОРОСТЬ',
                    value: d['speed']?.toInt().toString() ?? '---',
                    unit: 'км/ч',
                    isLive: false),
                // 010B (MAP) не поддерживается — никаких констант: «НЕТ ДАННЫХ»
                const SensorCard(
                    title: 'ДАД',
                    value: 'НЕТ ДАННЫХ',
                    unit: '',
                    isLive: false),
              ],
            ),
            const SizedBox(height: S.s5),
            ExtendedParamsCard(data: d),
            const SizedBox(height: S.s5),
            Text('ОСЦИЛЛОГРАФ ДК1 / ДК2 (0–1.8 В)',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: S.s2),
            if (st.trace1.isEmpty)
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: c.scopeBg,
                  borderRadius: BorderRadius.circular(R.lg),
                  border: Border.all(color: c.border),
                ),
                child: Center(
                  child: Text('Нет данных для графика',
                      style: TextStyle(color: c.text3)),
                ),
              )
            else
              Oscilloscope(
                trace1: Queue<double>.from(st.trace1),
                trace2: Queue<double>.from(st.trace2),
                minValue: 0,
                maxValue: 1.8,
                color1: c.trace1,
                color2: c.trace2,
              ),
            const SizedBox(height: S.s4),
            if (st.rawLastBlock1 != '---')
              Text('Блок: ${st.rawLastBlock1}',
                  style: AppTheme.mono(size: T.cap, color: c.text3)),
          ],
        ),
      ),
    );
  }
}

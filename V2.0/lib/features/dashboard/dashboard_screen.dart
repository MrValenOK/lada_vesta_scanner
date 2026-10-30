// lib/features/dashboard/dashboard_screen.dart — телеметрия, БК, осциллограф.
// Карточки — в widgets/dashboard_cards.dart, OTA — в ota_flow.dart
// (лимит 400 строк/файл, AGENTS V2.0). Цвета — только токены AppColors.
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/ai_snapshot_provider.dart';
import '../../providers/obd_provider.dart';
import 'ota_flow.dart';
import 'widgets/ai_snapshot_sheet.dart';
import 'widgets/dashboard_cards.dart';
import 'widgets/oscilloscope.dart';
import 'widgets/passport_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/trip_card.dart';
import 'widgets/trim_matrix_card.dart';

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
          // ИИ-Снапшот: сначала предпросмотр (что копируем), затем копирование
          // из шторки. Текст собирается по требованию из обоих провайдеров.
          IconButton(
            icon: Icon(Icons.auto_awesome, color: c.accent),
            tooltip: 'ИИ-Снапшот: предпросмотр и копирование',
            onPressed: () =>
                showAiSnapshotSheet(context, ref.read(aiSnapshotProvider)()),
          ),
          IconButton(
            icon: Icon(Icons.cloud_download_outlined, color: c.accent),
            tooltip: 'Проверить обновления',
            onPressed: () => runOtaCheck(context),
          ),
          // Бейдж — из фактической детекции протокола (не хардкод).
          if (st.isConnected)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: c.border),
              ),
              child: Center(
                  child: Text(st.isUds ? 'M86 UDS' : 'M86 KWP',
                      style: AppTheme.mono(size: T.cap))),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, 90),
          children: [
            const ConnectionCard(),
            const SizedBox(height: S.s3),
            const EcuPassportCard(),
            const SizedBox(height: S.s3),
            TripCard(
              calc: notifier.tripCalculator,
              onReset: () => _confirmResetTrip(context, notifier),
              onCalibrate: () => _showCalibrateDialog(context, notifier),
            ),
            const SizedBox(height: S.s4),
            Text('ТЕЛЕМЕТРИЯ LIVE',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: S.s2),
            // isLive — честно: опрос идёт И значение реально получено.
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: S.s3,
              mainAxisSpacing: S.s3,
              childAspectRatio: 1.5,
              children: [
                SensorCard(
                    title: 'ОБОРОТЫ · 010C',
                    value: d['rpm']?.toInt().toString() ?? '—',
                    unit: 'об/мин',
                    isLive: st.isPolling && d['rpm'] != null,
                    specKey: 'rpm',
                    specData: d),
                SensorCard(
                    title: 'ТЕМП. ОЖ',
                    value: d['ect']?.toInt().toString() ?? '—',
                    unit: '°C',
                    isLive: st.isPolling && d['ect'] != null,
                    specKey: 'ect',
                    specData: d),
                SensorCard(
                    title: 'БОРТСЕТЬ',
                    value: d['volt']?.toStringAsFixed(2) ?? '—',
                    unit: 'В',
                    isLive: st.isPolling && d['volt'] != null,
                    specKey: 'volt',
                    specData: d),
                SensorCard(
                    title: 'STFT',
                    value: d['stft']?.toStringAsFixed(1) ?? '—',
                    unit: '%',
                    isLive: st.isPolling && d['stft'] != null,
                    specKey: 'stft',
                    specData: d),
                SensorCard(
                    title: 'LTFT',
                    value: d['ltft']?.toStringAsFixed(1) ?? '—',
                    unit: '%',
                    isLive: st.isPolling && d['ltft'] != null,
                    specKey: 'ltft',
                    specData: d),
                SensorCard(
                    title: 'НАГРУЗКА',
                    value: d['load']?.toStringAsFixed(1) ?? '—',
                    unit: '%',
                    isLive: st.isPolling && d['load'] != null,
                    specKey: 'load',
                    specData: d),
                SensorCard(
                    title: 'СКОРОСТЬ',
                    value: d['speed']?.toInt().toString() ?? '—',
                    unit: 'км/ч',
                    isLive: st.isPolling && d['speed'] != null,
                    specKey: 'speed',
                    specData: d),
                // 010B (MAP) не поддерживается — никаких констант: «НЕТ ДАННЫХ»
                SensorCard(
                    title: 'ДАД',
                    value: 'НЕТ ДАННЫХ',
                    unit: '',
                    isLive: false,
                    specKey: 'map',
                    specData: d),
              ],
            ),
            const SizedBox(height: S.s5),
            ExtendedParamsCard(
                data: d,
                udsStatus: st.udsStatus,
                minVoltage: notifier.health.minVoltage,
                maxEct: notifier.health.maxEct),
            const SizedBox(height: S.s5),
            Text('МАТРИЦА САМООБУЧЕНИЯ (ЛИСТ 19 ТИ АВТОВАЗ)',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: S.s2),
            const TrimMatrixCard(),
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

  /// Сброс поездки — только по подтверждению (поправка БК сохраняется).
  Future<void> _confirmResetTrip(
      BuildContext context, ObdNotifier notifier) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить поездку?'),
        content: const Text('Пробег, средний расход и израсходованное топливо '
            'будут обнулены. Поправка БК сохранится.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.lightImpact();
      notifier.resetTrip();
    }
  }

  /// Калибровка БК по чеку: ввод фактических литров → новая поправка.
  /// После калибровки накопители сбрасываются (следующий замер — танк-в-танк).
  Future<void> _showCalibrateDialog(
      BuildContext context, ObdNotifier notifier) async {
    final calc = notifier.tripCalculator;
    final ctrl = TextEditingController();
    final actual = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Калибровка расхода по чеку'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Расчёт БК: ${calc.totalFuelLiters.toStringAsFixed(2)} л. '
                  'Текущая поправка: ×${calc.fuelTrimFactor.toStringAsFixed(2)}.'),
              const SizedBox(height: S.s2),
              const Text('Введите фактически залитые литры по чеку за эту '
                  'поездку. После калибровки накопители поездки сбросятся.'),
              const SizedBox(height: S.s2),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Литры по чеку',
                  hintText: 'например, 42.5',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                Navigator.pop(ctx, v);
              },
              child: const Text('Применить')),
        ],
      ),
    );
    ctrl.dispose();
    if (actual == null) return;
    final ok = await notifier.calibrateTripFromFill(actual);
    if (!context.mounted) return;
    final msg = ok
        ? 'Поправка БК: ×${notifier.tripCalculator.fuelTrimFactor.toStringAsFixed(2)}. '
            'Поездка сброшена для следующего замера.'
        : 'Недостаточно данных (нужно ≥ '
            '${M86Specs.tripCalibrationMinLiters.toStringAsFixed(0)} л расхода) '
            'или неверный ввод.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

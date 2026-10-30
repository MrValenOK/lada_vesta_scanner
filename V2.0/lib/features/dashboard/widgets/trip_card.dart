// lib/features/dashboard/widgets/trip_card.dart — карточка БК (П4).
// Пробег, средний/мгновенный расход (л/100 км в движении, л/ч на стоянке),
// средняя и максимальная скорость, израсходованное топливо, поправка БК.
// Сброс — с подтверждением (диалог на дашборде); калибровка — по чеку.
// Цвета — только токены AppColors; лимит 400 строк/файл.
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../services/trip_calculator.dart';

/// Карточка бортового компьютера (пробег/расход/мгновенный/скорости/топливо).
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.calc,
    required this.onReset,
    required this.onCalibrate,
  });

  final TripCalculator calc;
  final VoidCallback onReset;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final instantStr = calc.isMoving
        ? '${calc.instantFuelL100Km.toStringAsFixed(1)} л/100'
        : '${calc.instantFuelLpH.toStringAsFixed(2)} л/ч';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('ПОЕЗДКА · БК',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: c.text3)),
              const Spacer(),
              Text('ПОПРАВКА ×${calc.fuelTrimFactor.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: c.text3)),
              IconButton(
                icon: Icon(Icons.tune, size: 18, color: c.text3),
                tooltip: 'Калибровка по чеку',
                onPressed: onCalibrate,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.restart_alt, size: 18, color: c.text3),
                tooltip: 'Сбросить поездку',
                onPressed: onReset,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: S.s2),
          Wrap(
            spacing: S.s4,
            runSpacing: S.s2,
            alignment: WrapAlignment.spaceBetween,
            children: [
              _stat(context, 'ПРОБЕГ',
                  '${calc.totalDistanceKm.toStringAsFixed(1)} км'),
              _stat(context, 'СРЕДНИЙ',
                  '${calc.averageConsumptionL100Km.toStringAsFixed(1)} л/100'),
              _stat(context, 'МГНОВ.', instantStr),
              _stat(context, 'СР. СКОР.',
                  '${calc.averageSpeedKmh.toStringAsFixed(0)} км/ч'),
              _stat(context, 'МАКС.',
                  '${calc.maxSpeedKmh.toStringAsFixed(0)} км/ч'),
              _stat(context, 'ТОПЛИВО',
                  '${calc.totalFuelLiters.toStringAsFixed(2)} л'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String val) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w800, color: c.text3)),
        const SizedBox(height: S.s1),
        Text(val, style: AppTheme.mono(size: T.sm)),
      ],
    );
  }
}

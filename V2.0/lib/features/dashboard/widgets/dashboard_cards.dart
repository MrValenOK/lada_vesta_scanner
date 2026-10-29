// lib/features/dashboard/widgets/dashboard_cards.dart — карточки дашборда.
// Вынесено из dashboard_screen.dart (лимит 400 строк/файл). Цвета — только
// токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/obd_provider.dart';
import '../../../services/trip_calculator.dart';

/// Карточка подключения: статус + Старт/Стоп (выбор устройства — в диалоге).
class ConnectionCard extends ConsumerWidget {
  const ConnectionCard({super.key});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDeviceAndConnect(BuildContext context, WidgetRef ref) async {
    final devices = await ref.read(bluetoothServiceProvider).getPairedDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      _toast(context,
          'Нет спаренных Bluetooth-устройств. Спарьте ELM327 в настройках телефона!');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выберите ELM327'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (c2, i) {
              final d = devices[i];
              return ListTile(
                title: Text(d.name.isNotEmpty ? d.name : 'Unknown'),
                subtitle: Text(d.address,
                    style: Theme.of(ctx).textTheme.labelSmall),
                onTap: () {
                  Navigator.pop(ctx);
                  _connectAndStart(context, ref, d.address);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _connectAndStart(
      BuildContext context, WidgetRef ref, String address) async {
    final notifier = ref.read(obdProvider.notifier);
    final ok = await notifier.connect(address);
    if (!context.mounted) return;
    if (ok) {
      final st = ref.read(obdProvider);
      _toast(context,
          st.initOk ? 'Подключено · init OK · ${st.ecuId}' : 'Подключено · ВНИМАНИЕ: init частичный');
      notifier.startPolling();
    } else {
      _toast(context, 'Не удалось подключиться к адаптеру');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final st = ref.watch(obdProvider);
    final notifier = ref.read(obdProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(
          color: st.isPolling ? c.success : c.border,
          width: st.isPolling ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: st.isPolling ? c.successSoft : c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bluetooth_rounded,
                color: st.isPolling ? c.success : c.accent, size: 22),
          ),
          const SizedBox(width: S.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  st.isPolling
                      ? 'На связи'
                      : (st.isConnected ? 'Подключен' : 'Выберите ELM327 адаптер'),
                  style: TextStyle(
                    fontSize: T.sm,
                    fontWeight: FontWeight.w800,
                    color: st.isPolling ? c.success : c.text1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  st.statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: T.cap, color: c.text2),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: st.isPolling ? c.errorSoft : c.accentSoft,
              foregroundColor: st.isPolling ? c.error : c.accent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
            ),
            onPressed: () async {
              if (st.isPolling) {
                notifier.stopPolling();
              } else if (st.isConnected) {
                notifier.startPolling();
              } else {
                await _pickDeviceAndConnect(context, ref);
              }
            },
            child: Text(st.isPolling ? 'Стоп' : 'Старт',
                style:
                    const TextStyle(fontSize: T.sm, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Карточка бортового компьютера (пробег/расход/мгновенный).
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.calc, required this.onReset});

  final TripCalculator calc;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final isMoving = calc.totalDistanceKm > 0;
    final instantStr = isMoving
        ? '${calc.instantFuelL100Km.toStringAsFixed(1)} л/100'
        : '${calc.instantFuelLpH.toStringAsFixed(2)} л/ч';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(context, 'ПРОБЕГ', '${calc.totalDistanceKm.toStringAsFixed(1)} км'),
          Container(width: 1, height: 24, color: c.border),
          _stat(context, 'СРЕДНИЙ',
              '${calc.averageConsumptionL100Km.toStringAsFixed(1)} л/100'),
          Container(width: 1, height: 24, color: c.border),
          _stat(context, 'МГНОВ.', instantStr),
          IconButton(
            icon: Icon(Icons.restart_alt, size: 18, color: c.text3),
            tooltip: 'Сбросить поездку',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String val) {
    final c = context.appColors;
    return Column(
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

/// Плашка телеметрии.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.isLive,
  });

  final String title;
  final String value;
  final String unit;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(S.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border(
          left: BorderSide(color: isLive ? c.success : c.border, width: 4),
          top: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: T.cap, fontWeight: FontWeight.bold, color: c.text3)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: AppTheme.mono(size: value.length > 6 ? T.sm : T.lg)),
              const SizedBox(width: S.s1),
              Text(unit, style: TextStyle(fontSize: T.cap, color: c.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Параметры М86 (UDS) — честные значения: не читается → «—».
class ExtendedParamsCard extends StatelessWidget {
  const ExtendedParamsCard({super.key, required this.data});

  final Map<String, double> data;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(S.s4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ПАРАМЕТРЫ М86 (UDS 220001)',
              style: TextStyle(color: c.text3, fontWeight: FontWeight.bold)),
          Divider(color: c.border),
          // Реверс 220001 (дамп 2026-10-29): подтверждённые параметры блока —
          // для полевой сверки с Mode 01 (значения должны совпадать)
          _row(context, 'Обороты (UDS)',
              data['uds_rpm'] != null ? '${data['uds_rpm']!.toInt()} об/мин' : '—'),
          _row(context, 'ТОЖ (UDS)',
              data['uds_ect'] != null ? '${data['uds_ect']!.toInt()} °C' : '—'),
          _row(context, 'LTFT (UDS)',
              data['uds_ltft'] != null ? '${data['uds_ltft']!.toStringAsFixed(1)} %' : '—'),
          _row(context, 'Бортсеть (UDS)',
              data['uds_volt'] != null ? '${data['uds_volt']!.toStringAsFixed(1)} В' : '—'),
          // Mode 06 (0621) отвечает, но структура TBD: пропуски не хардкодим
          _row(context, 'Пропуски Цил. 1-4', 'TBD (0621)'),
          _row(context, 'ДАД (010B)', 'НЕТ ДАННЫХ'),
          _row(context, 'Воздух (расчётный)',
              '${data['air_mass_kgh']?.toStringAsFixed(1) ?? '—'} кг/ч'),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title, String val) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: T.sm, color: c.text2)),
          Text(val, style: AppTheme.mono(size: T.sm, color: c.accent)),
        ],
      ),
    );
  }
}

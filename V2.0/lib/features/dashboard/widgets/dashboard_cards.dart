// lib/features/dashboard/widgets/dashboard_cards.dart — карточки дашборда:
// подключение, поездка (БК), параметры М86 (UDS). Плашка датчика с нормами —
// widgets/sensor_card.dart, паспорт ЭСУД — widgets/passport_card.dart
// (выносы по лимиту 400 строк/файл). Цвета — только токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/spec_notes.dart';
import '../../../core/theme.dart';
import '../../../providers/obd_provider.dart';
import 'spec_sheet.dart';

/// Карточка подключения: статус + Старт/Стоп (выбор устройства — в диалоге).
class ConnectionCard extends ConsumerWidget {
  const ConnectionCard({super.key});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDeviceAndConnect(
      BuildContext context, WidgetRef ref) async {
    final devices = await ref.read(bluetoothServiceProvider).getPairedDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      _toast(context,
          'Нет спаренных Bluetooth-устройств. Спарьте ELM327 в настройках телефона!');
      return;
    }
    // Автовыбор: последний успешный адаптер (П5) — первым в списке.
    final last = ref.read(obdProvider.notifier).lastAdapterAddress;
    final sorted = [...devices]..sort((a, b) {
        if (a['address'] == last) return -1;
        if (b['address'] == last) return 1;
        return 0;
      });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выберите ELM327'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sorted.length,
            itemBuilder: (c2, i) {
              final d = sorted[i];
              final isLast = d['address'] == last;
              return ListTile(
                title: Text(d['name'] ?? 'Unknown'),
                subtitle: Text('${d['address'] ?? ''}'
                    '${isLast ? ' · последний' : ''}',
                    style: Theme.of(ctx).textTheme.labelSmall),
                onTap: () {
                  Navigator.pop(ctx);
                  _connectAndStart(context, ref, d['address']!, d['name']);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _connectAndStart(BuildContext context, WidgetRef ref,
      String address, String? name) async {
    final notifier = ref.read(obdProvider.notifier);
    final ok = await notifier.connect(address, name: name);
    if (!context.mounted) return;
    if (ok) {
      final st = ref.read(obdProvider);
      _toast(
          context,
          st.initOk
              ? 'Подключено · init OK · ${st.ecuId}'
              : 'Подключено · ВНИМАНИЕ: init частичный');
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
                      : (st.isConnected
                          ? 'Подключен'
                          : 'Выберите ELM327 адаптер'),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.md)),
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
                style: const TextStyle(
                    fontSize: T.sm, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Параметры М86 (UDS) — честные значения: не читается → «—».
/// Статусы (2026-10-30, утренний дамп): rpm/ect@3 — ожидают синхронной пары
/// ≤1 c (ТОЖ@3: 9 пар↔0105, Δ≤1.8); iat@33/ltft/stft/volt — кандидаты;
/// ect@54 отозван (0x77-константа во всех 321 кадре).
/// Тап по строке — справка: норма (M86Specs/ТИ) и причины отклонения.
class ExtendedParamsCard extends StatelessWidget {
  const ExtendedParamsCard(
      {super.key,
      required this.data,
      this.udsStatus = '—',
      this.minVoltage,
      this.maxEct});

  final Map<String, double> data;
  final String udsStatus;

  /// Сессионные экстремумы (П5): мин. напряжение АКБ и макс. ТОЖ.
  final double? minVoltage;
  final double? maxEct;

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
          Row(
            children: [
              Expanded(
                child: Text('ПАРАМЕТРЫ М86 (UDS 220001)',
                    style:
                        TextStyle(color: c.text3, fontWeight: FontWeight.bold)),
              ),
              Text('тап — норма',
                  style: TextStyle(fontSize: T.cap, color: c.text3)),
            ],
          ),
          Divider(color: c.border),
          _row(
              context,
              'Обороты (UDS @4..5)',
              data['uds_rpm'] != null
                  ? '${data['uds_rpm']!.toInt()} об/мин'
                  : '—',
              specKey: 'uds_rpm'),
          _row(
              context,
              'ТОЖ (UDS @3)',
              data['uds_ect'] != null
                  ? '${data['uds_ect']!.toStringAsFixed(1)} °C'
                  : '—',
              specKey: 'uds_ect'),
          _row(
              context,
              'LTFT (UDS)',
              data['uds_ltft'] != null
                  ? '${data['uds_ltft']!.toStringAsFixed(1)} %'
                  : '—',
              specKey: 'uds_ltft'),
          _row(
              context,
              'Бортсеть (UDS)',
              data['uds_volt'] != null
                  ? '${data['uds_volt']!.toStringAsFixed(1)} В'
                  : '—',
              specKey: 'uds_volt'),
          // Mode 06 (0621) отвечает, но структура TBD: пропуски не хардкодим
          _row(context, 'Пропуски Цил. 1-4', 'TBD (0621)'),
          _row(context, 'ДАД (010B)', 'НЕТ ДАННЫХ', specKey: 'map'),
          _row(context, 'Воздух (расчётный)',
              '${data['air_mass_kgh']?.toStringAsFixed(1) ?? '—'} кг/ч',
              specKey: 'air'),
          // Честный статус чтения блока (H2): OK / сверка 010C / отказ+причина
          Divider(color: c.border),
          Tooltip(
            message: '«OK» — кадр принят; сверка с 010C — при паре ≤1 c. '
                '«Отказ» — кадр отброшен валидатором (последние значения '
                'сохранены, следующий кадр обычно чистый). «—» — сверки ещё нет.',
            child: Text('220001: $udsStatus',
                style: AppTheme.mono(size: T.cap, color: c.text3)),
          ),
          const SizedBox(height: 2),
          Text(
              'Оборотов два источника: «ОБОРОТЫ · 010C» (Mode 01) и «Обороты (UDS @4..5)» — сверка при паре ≤1 c',
              style: TextStyle(fontSize: T.cap, color: c.text3)),
          const SizedBox(height: 2),
          Text(
              'ТОЖ/ДТВ @3/@33: кандидаты (0.75·raw−48) · ect@54 отозван (0x77-константа, 321 кадр)',
              style: TextStyle(fontSize: T.cap, color: c.text3)),
          const SizedBox(height: 2),
          Text(
              'За сессию: мин. АКБ ${minVoltage?.toStringAsFixed(2) ?? '—'} В · '
              'макс. ТОЖ ${maxEct?.toStringAsFixed(0) ?? '—'} °C',
              style: TextStyle(fontSize: T.cap, color: c.text3)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title, String val,
      {String? specKey}) {
    final c = context.appColors;
    final isOut = specKey != null &&
        checkSpec(specKey, data).status == SpecStatus.out;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: T.sm, color: c.text2)),
          Text(val,
              style: AppTheme.mono(
                  size: T.sm, color: isOut ? c.warning : c.accent)),
        ],
      ),
    );
    if (specKey == null) return row;
    return InkWell(
      onTap: () =>
          showSpecSheet(context, specKey: specKey, data: data, currentText: val),
      child: row,
    );
  }
}

// lib/features/dtc/dtc_screen.dart — коды неисправностей (Mode 03/07 + UDS
// 19 02 FF + стоп-кадр Mode 02) с расшифровкой из kM86DtcDatabase (ТИ 3100...).
// Портировано из lada_vesta_scanner; цвета — только токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/obd_provider.dart';

class DtcScreen extends ConsumerStatefulWidget {
  const DtcScreen({super.key});

  @override
  ConsumerState<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends ConsumerState<DtcScreen> {
  bool _isLoading = false;
  bool _hasScanned = false;
  List<String> _dtcs = [];
  Map<String, double?> _freezeFrameData = {};

  Future<void> _scanDtc() async {
    if (!ref.read(obdProvider).isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Сначала подключитесь к автомобилю!'),
        backgroundColor: context.appColors.error,
      ));
      return;
    }
    setState(() => _isLoading = true);
    final codes = await ref.read(obdProvider.notifier).readDtcs();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasScanned = true;
      _dtcs = codes;
    });
  }

  Future<void> _clearDtc() async {
    setState(() => _isLoading = true);
    await ref.read(obdProvider.notifier).clearDtcs();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _dtcs = [];
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Коды ошибок стёрты!'),
      backgroundColor: context.appColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Коды неисправностей')),
      body: Padding(
        padding: const EdgeInsets.all(S.s4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.surface,
                      foregroundColor: c.accent,
                      side: BorderSide(color: c.accent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isLoading ? null : _scanDtc,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: const Text('ПРОЧИТАТЬ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: S.s3),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.errorSoft,
                      foregroundColor: c.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (_isLoading || _dtcs.isEmpty) ? null : _clearDtc,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('СБРОСИТЬ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.s6),
            if (_hasScanned && _dtcs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: S.s2),
                child: Text('Тап по коду — стоп-кадр параметров (Mode 02)',
                    style: TextStyle(fontSize: T.cap, color: c.text3)),
              ),
            Expanded(
              child: !_hasScanned
                  ? Center(
                      child: Text('Нажмите "Прочитать", чтобы опросить ЭБУ',
                          style: TextStyle(color: c.text3)))
                  : _dtcs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: c.success, size: 64),
                              const SizedBox(height: S.s4),
                              const Text('Ошибок не обнаружено',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _dtcs.length,
                          itemBuilder: (context2, index) {
                            final code = _dtcs[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: S.s3),
                              color: c.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(R.md),
                                side: BorderSide(color: c.error),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(R.md),
                                onTap: () => _showFreezeFrame(code),
                                child: ListTile(
                                  leading:
                                      Icon(Icons.warning_amber_rounded, color: c.error),
                                  title: Text(code,
                                      style: AppTheme.mono(
                                          size: T.md, color: c.error)),
                                  subtitle: Text(
                                      kM86DtcDatabase[code] ??
                                          'Нет описания в базе М86 '
                                              '(ТИ 3100.25100.12056)',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.text2, fontSize: 12)),
                                  trailing: Icon(Icons.chevron_right, color: c.text3),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFreezeFrame(String code) async {
    _freezeFrameData = {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl))),
      builder: (ctx) {
        final c = ctx.appColors;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (_freezeFrameData.isEmpty) {
              Future.microtask(() async {
                final data = await ref
                    .read(obdProvider.notifier)
                    .getFreezeFrame(code);
                if (mounted) setSheetState(() => _freezeFrameData = data);
              });
            }
            return Padding(
              padding: const EdgeInsets.all(S.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: c.errorSoft,
                            borderRadius: BorderRadius.circular(R.sm)),
                        child: Text(code,
                            style: TextStyle(
                                color: c.error,
                                fontWeight: FontWeight.bold,
                                fontSize: T.md)),
                      ),
                      const SizedBox(width: S.s3),
                      const Expanded(
                          child: Text('Стоп-кадр',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold))),
                      if (_freezeFrameData.isEmpty)
                        const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: S.s2),
                  Text(
                      kM86DtcDatabase[code] ??
                          'Нет описания в базе М86 (ТИ 3100.25100.12056)',
                      style:
                          TextStyle(fontSize: T.sm, color: c.text2, height: 1.3)),
                  const SizedBox(height: S.s4),
                  if (_freezeFrameData.isEmpty)
                    Text('Запрос данных у ЭБУ...', style: TextStyle(color: c.text3))
                  else
                    ..._freezeFrameData.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: TextStyle(color: c.text3)),
                              Text(e.value?.toStringAsFixed(2) ?? '---',
                                  style: AppTheme.mono(size: T.sm, color: c.accent)),
                            ],
                          ),
                        )),
                  const SizedBox(height: S.s6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: c.surface2),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

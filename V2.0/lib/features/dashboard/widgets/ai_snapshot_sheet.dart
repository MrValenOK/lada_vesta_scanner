// lib/features/dashboard/widgets/ai_snapshot_sheet.dart — предпросмотр
// ИИ-Снапшота перед копированием (П6). Показываем ровно тот текст, который
// уйдёт в буфер: водитель видит, что копирует (включая «—» и метки
// КАНДИДАТ/TBD), а не верит вслепую. Цвета — только токены AppColors.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

Future<void> showAiSnapshotSheet(BuildContext context, String text) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.appColors.surface,
    builder: (ctx) {
      final c = ctx.appColors;
      final messenger = ScaffoldMessenger.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text('ИИ-Снапшот · предпросмотр',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  Text('${text.length} симв.',
                      style: AppTheme.mono(size: T.cap, color: c.text3)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: S.s4),
                child: SelectableText(text,
                    style: AppTheme.mono(size: T.cap, color: c.text2)),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(S.s4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.copy_all),
                    label: const Text('Скопировать промпт'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      messenger.showSnackBar(SnackBar(
                        content: Text('🤖 ИИ-Снапшот скопирован: '
                            '${text.length} символов, 6 разделов'),
                      ));
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

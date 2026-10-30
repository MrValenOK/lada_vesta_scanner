// lib/features/dashboard/ota_flow.dart — проверка обновлений (GitHub Releases)
// и шит установки. Вынесено из dashboard_screen.dart (лимит 400 строк/файл).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../services/ota_service.dart';

Future<void> runOtaCheck(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
      const SnackBar(content: Text('Проверка обновлений на GitHub...')));

  final result = await OtaService.checkForUpdates();
  if (!context.mounted) return;

  if (result['error'] == 'REPO_NOT_PUBLISHED') {
    messenger.showSnackBar(const SnackBar(
        content:
            Text('Обновления недоступны (репозиторий ещё не опубликован)')));
    return;
  }

  if (result['error'] == 'API_UNREACHABLE') {
    messenger.showSnackBar(const SnackBar(
        content:
            Text('Не удалось проверить обновления (нет сети или GitHub недоступен)')));
    return;
  }

  if (result['hasUpdate'] == true) {
    final apkUrl = result['apkUrl'] as String;
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl))),
      builder: (ctx) {
        final c = ctx.appColors;
        return Padding(
          padding: const EdgeInsets.all(S.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Обновление ${result['latestVersion']}',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: S.s3),
              Text('${result['releaseNotes']}',
                  style: TextStyle(color: c.text2, fontSize: T.sm, height: 1.4)),
              const SizedBox(height: S.s5),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.success,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await launchUrl(Uri.parse(apkUrl),
                        mode: LaunchMode.externalApplication);
                    if (!ok) {
                      await Clipboard.setData(ClipboardData(text: apkUrl));
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Ссылка скопирована в буфер')));
                    }
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text('Скачать и установить',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  } else {
    messenger.showSnackBar(const SnackBar(
        content: Text('У вас последняя версия (${OtaService.currentVersion})')));
  }
}

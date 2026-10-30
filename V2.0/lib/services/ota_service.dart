import 'dart:convert';
import 'dart:io';

class OtaService {
  // Версия приложения — из pubspec.yaml (version: 2.1.0+1); менять вместе с pubspec.
  static const String currentVersion = '2.1.0+1';

  // Репозиторий релизов ПРОЕКТА (владелец/имя), а не чужой старый.
  // Пока проект не опубликован — пусто: проверка честно отказывает и НИЧЕГО не предлагает.
  // П8: после публикации в GitHub вписать сюда 'владелец/репозиторий'.
  static const String projectRepo = '';

  static Future<Map<String, dynamic>> checkForUpdates() async {
    if (projectRepo.isEmpty) {
      return {'hasUpdate': false, 'error': 'REPO_NOT_PUBLISHED'};
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5); // Уменьшили с 8

    try {
      final req = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$projectRepo/releases/latest'),
      );
      req.headers.set('User-Agent', 'VestaScanPro-App');
      req.headers.set('Accept', 'application/vnd.github+json');
      
      final resp = await req.close();

      if (resp.statusCode == 200) {
        final bodyStr = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(bodyStr) as Map<String, dynamic>;

        final tagName = (data['tag_name'] ?? currentVersion).toString();
        final notes = (data['body'] ?? '').toString().trim();
        
        String apkUrl = 'https://github.com/$projectRepo/releases/latest/download/app-release.apk';
        if (data['assets'] is List && (data['assets'] as List).isNotEmpty) {
          for (final asset in (data['assets'] as List)) {
            final name = (asset['name'] ?? '').toString().toLowerCase();
            if (name.endsWith('.apk') && asset['browser_download_url'] != null) {
              apkUrl = asset['browser_download_url'].toString();
              break;
            }
          }
        }

        final isNewer = _isVersionHigher(tagName, currentVersion);

        return {
          'hasUpdate': isNewer,
          'latestVersion': tagName,
          'releaseNotes': notes.isNotEmpty ? notes : 'Обновление алгоритмов диагностики.',
          'apkUrl': apkUrl,
        };
      }

      // Репозиторий проекта не найден (ещё не опубликован или переименован).
      if (resp.statusCode == 404) {
        return {'hasUpdate': false, 'error': 'REPO_NOT_PUBLISHED'};
      }
    } catch (_) {
      // Сеть/GitHub недоступны — честный отказ ниже; чужой репозиторий не предлагаем.
    } finally {
      client.close(force: true);
    }
    return {'hasUpdate': false, 'error': 'API_UNREACHABLE'};
  }

  // Сравнение версий (например, v2.2.0 > v2.1.0)
  static bool _isVersionHigher(String remote, String local) {
    String clean(String v) => v.split('+').first.split('-').first.replaceAll(RegExp(r'[^0-9.]'), '');
    
    final rParts = clean(remote).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lParts = clean(local).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;
    for (int i = 0; i < maxLen; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }
}
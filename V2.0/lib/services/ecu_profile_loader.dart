// lib/services/ecu_profile_loader.dart — загрузка профиля ЭБУ из asset
// `m86_uds.json` и создание читателя блока 220001 (M86BlockReader).
// Профиль не загрузился — честный null + запись в debug-лог (не молчим).
// Вынесено из obd_provider (правило лимита 400 строк, AGENTS: вынос).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models/ecu_profile.dart';
import 'm86_block_reader.dart';
import 'obd_parser.dart';

class EcuProfileLoader {
  static const String assetPath = 'lib/data/json_profiles/m86_uds.json';

  /// null — профиль недоступен (файл/парсинг): провайдер работает без
  /// читателя блока (в UI «НЕТ ДАННЫХ»), а не с выдуманными значениями.
  static Future<M86BlockReader?> loadBlockReader(ElmSendCommand send) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final profile = EcuProfile.fromJson(jsonDecode(jsonString));
      final blocks = profile.blocks;
      if (blocks.isEmpty) return null;
      return M86BlockReader(send: send, block: blocks.first);
    } catch (e) {
      debugPrint('[OBD] профиль ЭБУ не загружен: $e');
      return null;
    }
  }
}

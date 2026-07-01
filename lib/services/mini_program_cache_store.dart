import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import 'api_service.dart';

class MiniProgramCacheStore {
  MiniProgramCacheStore._();

  static const int _maxItems = 60;
  static MMKV get _kv => MMKV.defaultMMKV();

  static String _key(int userId) => 'mini_program_cache_list_$userId';

  static Future<List<MiniProgramItem>> load(int userId) async {
    final raw = _kv.decodeString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return const <MiniProgramItem>[];
    try {
      final decoded = jsonDecode(raw);
      final source = decoded is List ? decoded : const <dynamic>[];
      final result = <MiniProgramItem>[];
      for (final item in source) {
        if (item is Map<String, dynamic>) {
          result.add(MiniProgramItem.fromJson(item));
        } else if (item is Map) {
          result.add(MiniProgramItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return result
          .where((item) => item.name.isNotEmpty && item.url.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <MiniProgramItem>[];
    }
  }

  static Future<void> save(int userId, List<MiniProgramItem> items) async {
    final trimmed = items.length > _maxItems
        ? items.sublist(0, _maxItems)
        : items;
    _kv.encodeString(
      _key(userId),
      jsonEncode(trimmed.map((item) => item.toCacheJson()).toList()),
    );
  }
}

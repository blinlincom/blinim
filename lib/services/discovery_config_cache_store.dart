import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import 'api_service.dart';

class DiscoveryConfigCacheStore {
  DiscoveryConfigCacheStore._();

  static MMKV get _kv => MMKV.defaultMMKV();

  static String _key(int userId) => 'discovery_config_cache_$userId';

  static Future<DiscoveryConfig?> load(int userId) async {
    final raw = _kv.decodeString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DiscoveryConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return DiscoveryConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(int userId, DiscoveryConfig config) async {
    _kv.encodeString(_key(userId), jsonEncode(config.toCacheJson()));
  }
}

import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import 'api_service.dart';

class ProfileCacheStore {
  ProfileCacheStore._();

  static MMKV get _kv => MMKV.defaultMMKV();

  static String _selfProfileKey(int userId) =>
      'profile_cache_self_profile_$userId';

  static Future<UserProfileSummary?> loadSelfProfile(int userId) async {
    final raw = _kv.decodeString(_selfProfileKey(userId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserProfileSummary.fromJson(decoded);
      }
      if (decoded is Map) {
        return UserProfileSummary.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveSelfProfile(
    int userId,
    UserProfileSummary profile,
  ) async {
    _kv.encodeString(
      _selfProfileKey(userId),
      jsonEncode(profile.toCacheJson()),
    );
  }
}

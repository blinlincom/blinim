import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import 'api_service.dart';

class MomentsCacheStore {
  MomentsCacheStore._();

  static const int _maxMoments = 80;
  static const int _maxNotifications = 80;
  static MMKV get _kv => MMKV.defaultMMKV();

  static String _momentsKey(int userId) => 'moments_cache_list_$userId';
  static String _notificationsKey(int userId) =>
      'moments_cache_notifications_$userId';
  static Future<List<MomentItem>> loadMoments(int userId) {
    return _readList(_momentsKey(userId), MomentItem.fromJson);
  }

  static Future<void> saveMoments(int userId, List<MomentItem> moments) async {
    final sorted = [...moments]
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    final trimmed = sorted.length > _maxMoments
        ? sorted.sublist(0, _maxMoments)
        : sorted;
    await _writeList(
      _momentsKey(userId),
      trimmed.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<List<MomentNotificationItem>> loadNotifications(int userId) {
    return _readList(
      _notificationsKey(userId),
      MomentNotificationItem.fromJson,
    );
  }

  static Future<void> saveNotifications(
    int userId,
    List<MomentNotificationItem> notifications,
  ) async {
    final sorted = [...notifications]
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    final trimmed = sorted.length > _maxNotifications
        ? sorted.sublist(0, _maxNotifications)
        : sorted;
    await _writeList(
      _notificationsKey(userId),
      trimmed.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<void> clearNotifications(int userId) async {
    _kv.removeValue(_notificationsKey(userId));
  }

  static Future<List<T>> _readList<T>(
    String key,
    T Function(Map<String, dynamic> json) decode,
  ) async {
    final raw = _kv.decodeString(key);
    if (raw == null || raw.trim().isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      final source = decoded is List ? decoded : const <dynamic>[];
      final result = <T>[];
      for (final item in source) {
        if (item is Map<String, dynamic>) {
          result.add(decode(item));
        } else if (item is Map) {
          result.add(decode(Map<String, dynamic>.from(item)));
        }
      }
      return result;
    } catch (_) {
      return <T>[];
    }
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    _kv.encodeString(key, jsonEncode(items));
  }
}

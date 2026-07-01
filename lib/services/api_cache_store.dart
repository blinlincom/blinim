import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mmkv/mmkv.dart';

class ApiCacheStore {
  ApiCacheStore._();

  static const _prefix = 'api_response_cache_v1';
  static MMKV get _kv => MMKV.defaultMMKV();

  static String key({
    required String baseUrl,
    required String path,
    required Map<String, dynamic> body,
  }) {
    final source = jsonEncode({
      'base_url': baseUrl,
      'path': path,
      'body': _stableValue(body),
    });
    final digest = crypto.sha256.convert(utf8.encode(source)).toString();
    return '$_prefix:$digest';
  }

  static Future<Map<String, dynamic>?> read(
    String key, {
    Duration maxAge = const Duration(days: 7),
  }) async {
    final raw = _kv.decodeString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final entry = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
      if (entry == null) return null;
      final updatedAt =
          int.tryParse('${entry['updated_at'] ?? entry['updatedAt'] ?? 0}') ??
          0;
      if (updatedAt <= 0) return null;
      final age = DateTime.now().millisecondsSinceEpoch - updatedAt;
      if (age > maxAge.inMilliseconds) return null;
      final response = entry['response'];
      if (response is Map<String, dynamic>) return response;
      if (response is Map) return Map<String, dynamic>.from(response);
    } catch (_) {}
    return null;
  }

  static Future<void> write(String key, Map<String, dynamic> response) async {
    _kv.encodeString(
      key,
      jsonEncode({
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'response': response,
      }),
    );
  }

  static Object? _stableValue(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      final keys = value.keys.map((key) => '$key').toList()..sort();
      for (final key in keys) {
        result[key] = _stableValue(value[key]);
      }
      return result;
    }
    if (value is Iterable) {
      return value.map(_stableValue).toList();
    }
    return value;
  }
}

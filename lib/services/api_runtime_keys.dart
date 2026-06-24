import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/safe_random.dart';
import 'api_errors.dart';
import 'client_device_context.dart';
import 'wukong_rest_guard.dart';

class ApiRuntimeKeys {
  final String apiAppKey;
  final String apiSignKey;
  final String apiAesKey;
  final String keyId;
  final DateTime expiresAt;

  const ApiRuntimeKeys({
    required this.apiAppKey,
    required this.apiSignKey,
    required this.apiAesKey,
    required this.keyId,
    required this.expiresAt,
  });

  bool get isFresh =>
      apiAppKey.isNotEmpty &&
      apiSignKey.isNotEmpty &&
      apiAesKey.length == 16 &&
      DateTime.now().isBefore(expiresAt.subtract(const Duration(seconds: 45)));

  factory ApiRuntimeKeys.fromJson(Map<String, dynamic> data) {
    final now = DateTime.now();
    final ttl = int.tryParse('${data['expires_in'] ?? data['ttl'] ?? 0}') ?? 0;
    final expiresAtRaw = int.tryParse('${data['expires_at'] ?? 0}') ?? 0;
    final expiresAt = expiresAtRaw > 0
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtRaw * 1000)
        : now.add(Duration(seconds: ttl > 0 ? ttl : 600));
    final keys = ApiRuntimeKeys(
      apiAppKey: '${data['apiAppKey'] ?? data['api_app_key'] ?? ''}'.trim(),
      apiSignKey: '${data['apiSignKey'] ?? data['api_sign_key'] ?? ''}'.trim(),
      apiAesKey: '${data['apiAesKey'] ?? data['api_aes_key'] ?? ''}'.trim(),
      keyId: '${data['key_id'] ?? data['keyId'] ?? ''}'.trim(),
      expiresAt: expiresAt,
    );
    if (keys.apiAppKey.isEmpty ||
        keys.apiSignKey.isEmpty ||
        keys.apiAesKey.length != 16) {
      throw ApiException('安全密钥读取失败，请重新打开应用');
    }
    return keys;
  }
}

class ApiRuntimeKeyManager {
  ApiRuntimeKeyManager._();

  static const String _prefsKeyPrefix = 'api_runtime_keys_v2';
  static ApiRuntimeKeys? _current;
  static Future<ApiRuntimeKeys>? _pending;

  static Future<ApiRuntimeKeys> ensureFresh({bool forceRefresh = false}) async {
    final current = _current;
    if (!forceRefresh && current != null && current.isFresh) {
      return current;
    }
    if (forceRefresh) {
      _current = null;
      _pending = null;
      unawaited(_removeCached());
    }
    if (!forceRefresh) {
      final cached = await _loadCached();
      if (cached != null && cached.isFresh) {
        _current = cached;
        return cached;
      }
    }
    final pending = _pending;
    if (pending != null) return pending;
    final next = _fetch()
        .then((value) {
          _current = value;
          unawaited(_saveCached(value));
          return value;
        })
        .whenComplete(() {
          _pending = null;
        });
    _pending = next;
    return next;
  }

  static void clear() {
    _current = null;
    _pending = null;
    unawaited(_removeCached());
  }

  static void invalidate(ApiRuntimeKeys keys) {
    final current = _current;
    if (current == null) return;
    final sameKey =
        current.keyId == keys.keyId &&
        current.apiAppKey == keys.apiAppKey &&
        current.apiSignKey == keys.apiSignKey;
    if (sameKey) {
      _current = null;
      unawaited(_removeCached());
    }
  }

  static Future<ApiRuntimeKeys?> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey());
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ApiRuntimeKeys.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCached(ApiRuntimeKeys keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey(),
        jsonEncode({
          'api_app_key': keys.apiAppKey,
          'api_sign_key': keys.apiSignKey,
          'api_aes_key': keys.apiAesKey,
          'key_id': keys.keyId,
          'expires_at': keys.expiresAt.millisecondsSinceEpoch ~/ 1000,
        }),
      );
    } catch (_) {}
  }

  static Future<void> _removeCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey());
    } catch (_) {}
  }

  static String _prefsKey() => '${_prefsKeyPrefix}_${AppConfig.appId}';

  static Future<ApiRuntimeKeys> _fetch() async {
    final device = ClientDeviceContext.current();
    final deviceId = await device.persistentDeviceId();
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = <String, String>{
      'appid': '${AppConfig.appId}',
      'timestamp': '$nowSeconds',
      'time': '$nowSeconds',
      'nonce': _nonce(),
      ...device.toApiFields().map((key, value) => MapEntry(key, '$value')),
      'device_id': deviceId,
      'client_device_id': deviceId,
    };
    final uri = Uri.parse('${AppConfig.apiBase}/get_api_dynamic_key');
    WukongRestGuard.assertClientUriAllowed(uri);
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw ApiException('安全密钥读取失败，请稍后再试');
      }
      final jsonBody = Map<String, dynamic>.from(decoded);
      if ('${jsonBody['code']}' != '1') {
        final message = '${jsonBody['msg'] ?? ''}'.trim();
        throw ApiException(message.isEmpty ? '安全密钥读取失败，请稍后再试' : message);
      }
      final data = jsonBody['data'];
      if (data is Map<String, dynamic>) return ApiRuntimeKeys.fromJson(data);
      if (data is Map) {
        return ApiRuntimeKeys.fromJson(Map<String, dynamic>.from(data));
      }
      throw ApiException('安全密钥读取失败，请稍后再试');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('安全密钥读取失败，请检查网络后重试');
    }
  }

  static String _nonce() {
    final bytes = SafeRandom.bytes(12);
    return '${DateTime.now().microsecondsSinceEpoch}_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

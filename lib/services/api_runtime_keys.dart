import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/safe_random.dart';
import 'api_errors.dart';
import 'client_device_context.dart';

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

  static ApiRuntimeKeys? _current;
  static Future<ApiRuntimeKeys>? _pending;

  static Future<ApiRuntimeKeys> ensureFresh({bool forceRefresh = false}) {
    final current = _current;
    if (!forceRefresh && current != null && current.isFresh) {
      return Future.value(current);
    }
    final pending = _pending;
    if (!forceRefresh && pending != null) return pending;
    final next = _fetch()
        .then((value) {
          _current = value;
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
  }

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

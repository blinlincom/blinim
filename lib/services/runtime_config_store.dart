import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import '../core/app_config.dart';

class ApiRuntimeConfig {
  final String apiAppKey;
  final String apiSignSecretKey;
  final String apiAesKey;
  final bool verifyResponseSign;

  const ApiRuntimeConfig({
    required this.apiAppKey,
    required this.apiSignSecretKey,
    required this.apiAesKey,
    required this.verifyResponseSign,
  });

  static const fallback = ApiRuntimeConfig(
    apiAppKey: AppConfig.apiAppKey,
    apiSignSecretKey: AppConfig.apiSignSecretKey,
    apiAesKey: AppConfig.apiAesKey,
    verifyResponseSign: AppConfig.verifyResponseSign,
  );

  bool get isValid =>
      apiAppKey.isNotEmpty &&
      apiSignSecretKey.isNotEmpty &&
      (apiAesKey.isEmpty || apiAesKey.length == 16);

  Map<String, dynamic> toJson() => {
    'api_app_key': apiAppKey,
    'api_sign_secret_key': apiSignSecretKey,
    'api_aes_key': apiAesKey,
    'verify_response_sign': verifyResponseSign,
  };

  factory ApiRuntimeConfig.fromJson(Map<String, dynamic> json) {
    bool truthy(Object? value, {required bool fallback}) {
      if (value == null) return fallback;
      final text = '$value'.trim().toLowerCase();
      if (text == '1' || text == 'true' || text == 'yes' || text == 'on') {
        return true;
      }
      if (text == '0' || text == 'false' || text == 'no' || text == 'off') {
        return false;
      }
      return fallback;
    }

    return ApiRuntimeConfig(
      apiAppKey:
          '${json['api_app_key'] ?? json['apiAppKey'] ?? AppConfig.apiAppKey}'
              .trim(),
      apiSignSecretKey:
          '${json['api_sign_secret_key'] ?? json['apiSignSecretKey'] ?? json['api_sign_key'] ?? json['apiSignKey'] ?? AppConfig.apiSignSecretKey}'
              .trim(),
      apiAesKey:
          '${json['api_aes_key'] ?? json['apiAesKey'] ?? AppConfig.apiAesKey}'
              .trim(),
      verifyResponseSign: truthy(
        json['verify_response_sign'] ?? json['verifyResponseSign'],
        fallback: AppConfig.verifyResponseSign,
      ),
    );
  }
}

class ClientRuntimeConfig {
  final ApiRuntimeConfig api;
  final List<Map<String, dynamic>> iceServers;
  final int updatedAt;

  const ClientRuntimeConfig({
    required this.api,
    required this.iceServers,
    required this.updatedAt,
  });

  static ClientRuntimeConfig fallback() => ClientRuntimeConfig(
    api: ApiRuntimeConfig.fallback,
    iceServers: AppConfig.rtcIceServers,
    updatedAt: 0,
  );

  Map<String, dynamic> toJson() => {
    'api_security': api.toJson(),
    'rtc': {'ice_servers': iceServers},
    'updated_at': updatedAt,
  };

  factory ClientRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final apiRaw =
        json['api_security'] ?? json['apiSecurity'] ?? json['api'] ?? json;
    final rtcRaw = json['rtc'] ?? json['audio_video'] ?? json['audioVideo'];
    final iceRaw = rtcRaw is Map
        ? rtcRaw['ice_servers'] ?? rtcRaw['iceServers']
        : json['ice_servers'] ?? json['iceServers'];
    final iceServers = _parseIceServers(iceRaw);
    final updatedAt =
        int.tryParse('${json['updated_at'] ?? json['updatedAt'] ?? 0}') ?? 0;
    final api = apiRaw is Map
        ? ApiRuntimeConfig.fromJson(Map<String, dynamic>.from(apiRaw))
        : ApiRuntimeConfig.fallback;
    return ClientRuntimeConfig(
      api: api.isValid ? api : ApiRuntimeConfig.fallback,
      iceServers: iceServers.isNotEmpty ? iceServers : AppConfig.rtcIceServers,
      updatedAt: updatedAt,
    );
  }

  static List<Map<String, dynamic>> _parseIceServers(Object? raw) {
    Object? source = raw;
    if (source is String && source.trim().isNotEmpty) {
      try {
        source = jsonDecode(source);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    if (source is! List) return const <Map<String, dynamic>>[];
    return source
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['urls'] != null)
        .toList();
  }
}

class RuntimeConfigStore {
  RuntimeConfigStore._();

  static const _key = 'client_runtime_config_v1';
  static MMKV? _kv;
  static ClientRuntimeConfig _current = ClientRuntimeConfig.fallback();

  static ClientRuntimeConfig get current => _current;
  static ApiRuntimeConfig get api => _current.api;
  static List<Map<String, dynamic>> get iceServers => _current.iceServers;

  static Future<void> initialize() async {
    await MMKV.initialize(logLevel: MMKVLogLevel.Warning);
    _kv = MMKV.defaultMMKV();
    _current = _readCached() ?? ClientRuntimeConfig.fallback();
  }

  static Future<void> updateFromApi(Map<String, dynamic> data) async {
    final config = ClientRuntimeConfig.fromJson(data);
    _current = config;
    _kv?.encodeString(_key, jsonEncode(config.toJson()));
  }

  static ClientRuntimeConfig? _readCached() {
    final raw = _kv?.decodeString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ClientRuntimeConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return ClientRuntimeConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }
}

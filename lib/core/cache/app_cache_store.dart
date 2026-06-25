import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

import '../../models/im_models.dart';
import '../app_logger.dart';
import '../events/app_event_bus.dart';
import 'app_cache_database.dart';
import 'lru_memory_cache.dart';

class AppCacheStore {
  AppCacheStore._();

  static final AppCacheStore instance = AppCacheStore._();

  final AppCacheDatabase _db = AppCacheDatabase();
  final LruMemoryCache<String, Map<String, dynamic>> _apiMemory =
      LruMemoryCache<String, Map<String, dynamic>>(
        capacity: 256,
        ttl: const Duration(minutes: 15),
      );
  final LruMemoryCache<String, Map<String, dynamic>> _entityMemory =
      LruMemoryCache<String, Map<String, dynamic>>(
        capacity: 512,
        ttl: const Duration(minutes: 30),
      );
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _db.open();
    _initialized = true;
    unawaited(_pruneExpired());
  }

  Future<void> writeApiResponse({
    required String path,
    required Map<String, dynamic> request,
    required Map<String, dynamic> response,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    if (!isCacheableApiPath(path)) return;
    await initialize();
    final key = apiRequestKey(path, request);
    final memoryKey = '$path::$key';
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + ttl.inMilliseconds;
    final jsonText = jsonEncode(response);
    _apiMemory.put(memoryKey, response, ttl: ttl);
    await _db.insert(
      '''
INSERT OR REPLACE INTO api_responses
(path, request_key, response_json, updated_at, expires_at)
VALUES (?, ?, ?, ?, ?)
''',
      <Object?>[path, key, jsonText, now, expiresAt],
    );
    AppEventBus.emit(ApiCacheUpdatedEvent(path: path, requestKey: key));
  }

  Future<Map<String, dynamic>?> readApiResponse({
    required String path,
    required Map<String, dynamic> request,
  }) async {
    if (!isCacheableApiPath(path)) return null;
    await initialize();
    final key = apiRequestKey(path, request);
    final memoryKey = '$path::$key';
    final memory = _apiMemory.get(memoryKey);
    if (memory != null) return memory;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.select(
      '''
SELECT response_json FROM api_responses
WHERE path = ? AND request_key = ? AND (expires_at = 0 OR expires_at > ?)
LIMIT 1
''',
      <Object?>[path, key, now],
    );
    if (rows.isEmpty) return null;
    final decoded = _decodeMap('${rows.first['response_json'] ?? ''}');
    if (decoded == null) return null;
    _apiMemory.put(memoryKey, decoded);
    return decoded;
  }

  Future<void> invalidateApiPath(String path) async {
    await initialize();
    _apiMemory.removeWhere((key) => key.startsWith('$path::'));
    await _db.delete('DELETE FROM api_responses WHERE path = ?', <Object?>[
      path,
    ]);
  }

  Future<void> invalidateApiPrefixes(Iterable<String> prefixes) async {
    await initialize();
    for (final prefix in prefixes) {
      _apiMemory.removeWhere((key) => key.startsWith(prefix));
      await _db.delete('DELETE FROM api_responses WHERE path LIKE ?', <Object?>[
        '$prefix%',
      ]);
    }
  }

  Future<void> putEntity({
    required String scope,
    required String key,
    required Map<String, dynamic> value,
    Duration ttl = const Duration(hours: 6),
  }) async {
    await initialize();
    final memoryKey = '$scope::$key';
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + ttl.inMilliseconds;
    _entityMemory.put(memoryKey, value, ttl: ttl);
    await _db.insert(
      '''
INSERT OR REPLACE INTO cache_entries
(scope, cache_key, value_json, updated_at, expires_at)
VALUES (?, ?, ?, ?, ?)
''',
      <Object?>[scope, key, jsonEncode(value), now, expiresAt],
    );
    AppEventBus.emit(EntityCacheUpdatedEvent(scope: scope, key: key));
  }

  Future<Map<String, dynamic>?> getEntity({
    required String scope,
    required String key,
  }) async {
    await initialize();
    final memoryKey = '$scope::$key';
    final memory = _entityMemory.get(memoryKey);
    if (memory != null) return memory;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.select(
      '''
SELECT value_json FROM cache_entries
WHERE scope = ? AND cache_key = ? AND (expires_at = 0 OR expires_at > ?)
LIMIT 1
''',
      <Object?>[scope, key, now],
    );
    if (rows.isEmpty) return null;
    final decoded = _decodeMap('${rows.first['value_json'] ?? ''}');
    if (decoded == null) return null;
    _entityMemory.put(memoryKey, decoded);
    return decoded;
  }

  Future<void> cacheMessage({
    required String conversationKey,
    required UnifiedMessage message,
  }) async {
    await initialize();
    final key = messageCacheKey(message);
    if (key.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = message.createTime.millisecondsSinceEpoch;
    await _db.insert(
      '''
INSERT OR REPLACE INTO im_messages
(conversation_key, message_key, payload_json, msg_type, created_at, updated_at, deleted)
VALUES (?, ?, ?, ?, ?, ?, 0)
''',
      <Object?>[
        conversationKey,
        key,
        jsonEncode(message.raw),
        message.msgType,
        createdAt,
        now,
      ],
    );
    AppEventBus.emit(
      ImMessageCachedEvent(conversationKey: conversationKey, messageKey: key),
    );
  }

  Future<void> cacheMessages({
    required String conversationKey,
    required Iterable<UnifiedMessage> messages,
  }) async {
    for (final message in messages) {
      await cacheMessage(conversationKey: conversationKey, message: message);
    }
  }

  Future<List<Map<String, dynamic>>> loadMessagePayloads({
    required String conversationKey,
    int limit = 50,
    int beforeTime = 0,
  }) async {
    await initialize();
    final rows = await _db.select(
      '''
SELECT payload_json FROM im_messages
WHERE conversation_key = ? AND deleted = 0
${beforeTime > 0 ? 'AND created_at < ?' : ''}
ORDER BY created_at DESC
LIMIT ?
''',
      <Object?>[conversationKey, if (beforeTime > 0) beforeTime, limit],
    );
    return rows
        .map((row) => _decodeMap('${row['payload_json'] ?? ''}'))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  Future<void> markMessageDeleted({
    required String conversationKey,
    required String messageKey,
  }) async {
    await initialize();
    await _db.update(
      '''
UPDATE im_messages
SET deleted = 1, updated_at = ?
WHERE conversation_key = ? AND message_key = ?
''',
      <Object?>[
        DateTime.now().millisecondsSinceEpoch,
        conversationKey,
        messageKey,
      ],
    );
  }

  Future<void> clearConversation(String conversationKey) async {
    await initialize();
    await _db.delete(
      'DELETE FROM im_messages WHERE conversation_key = ?',
      <Object?>[conversationKey],
    );
  }

  String apiRequestKey(String path, Map<String, dynamic> request) {
    final normalized = <String, dynamic>{};
    final entries = request.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      normalized[entry.key] = _stableValue(entry.value);
    }
    return crypto.sha256
        .convert(utf8.encode(jsonEncode(<Object?>[path, normalized])))
        .toString();
  }

  String messageCacheKey(UnifiedMessage message) {
    final content = message.content;
    for (final value in <Object?>[
      content['client_msg_no'],
      content['client_no'],
      message.raw['client_msg_no'],
      message.raw['client_no'],
      message.messageId > 0 ? message.messageId : null,
    ]) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != '0' && text != 'null') return text;
    }
    final raw = jsonEncode(message.raw);
    return crypto.sha1.convert(utf8.encode(raw)).toString();
  }

  bool isCacheableApiPath(String path) {
    final lower = path.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.contains('captcha') ||
        lower.contains('verification_code') ||
        lower.contains('upload') ||
        lower.contains('login') ||
        lower.contains('register') ||
        lower.contains('retrieve')) {
      return false;
    }
    const blockedPrefixes = [
      '/send',
      '/clear',
      '/mark',
      '/create',
      '/update',
      '/delete',
      '/add',
      '/remove',
      '/join',
      '/leave',
      '/dismiss',
      '/accept',
      '/return',
      '/buy',
      '/redeem',
      '/claim',
      '/report',
      '/recall',
      '/set',
      '/change',
      '/handle',
    ];
    if (blockedPrefixes.any(lower.startsWith)) return false;
    return lower.startsWith('/get') ||
        lower.startsWith('/search') ||
        lower.startsWith('/api') ||
        lower.startsWith('/im_');
  }

  Future<void> invalidateForMutation(String path) async {
    final lower = path.toLowerCase();
    final prefixes = <String>{
      if (lower.contains('message') || lower.contains('chat')) '/get_message',
      if (lower.contains('message') || lower.contains('chat')) '/get_chat',
      if (lower.contains('group')) '/get_im_group',
      if (lower.contains('friend')) '/get_friend',
      if (lower.contains('moment')) '/get_moment',
      if (lower.contains('wallet') ||
          lower.contains('money') ||
          lower.contains('transfer') ||
          lower.contains('red_packet') ||
          lower.contains('bill'))
        '/api',
      if (lower.contains('shop') || lower.contains('goods')) '/api',
      if (lower.contains('emoji')) '/get_emoji',
    };
    if (prefixes.isEmpty) return;
    await invalidateApiPrefixes(prefixes);
  }

  Future<void> close() async {
    await _db.close();
    _apiMemory.clear();
    _entityMemory.clear();
    _initialized = false;
  }

  Future<void> _pruneExpired() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.delete(
        'DELETE FROM api_responses WHERE expires_at > 0 AND expires_at <= ?',
        <Object?>[now],
      );
      await _db.delete(
        'DELETE FROM cache_entries WHERE expires_at > 0 AND expires_at <= ?',
        <Object?>[now],
      );
    } catch (e, stack) {
      AppLogger.exception('CACHE', e, stack, context: '清理本地缓存失败');
    }
  }

  Map<String, dynamic>? _decodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  dynamic _stableValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList(growable: false)
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return <String, dynamic>{
        for (final entry in entries) '${entry.key}': _stableValue(entry.value),
      };
    }
    if (value is Iterable) return value.map(_stableValue).toList();
    return value;
  }
}

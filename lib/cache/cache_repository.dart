import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import '../models/im_models.dart';
import '../services/api_service.dart';
import 'cache_database.dart';
import 'cache_event_bus.dart';
import 'memory_lru_cache.dart';

class CacheRepository {
  final CacheDatabase database;
  final CacheEventBus eventBus;
  final MemoryLruCache<int, List<ConversationItem>> _conversationMemory;
  final MemoryLruCache<String, List<UnifiedMessage>> _messageMemory;
  final MemoryLruCache<int, List<ImGroup>> _groupMemory;
  final MemoryLruCache<String, Map<String, dynamic>> _apiMemory;

  CacheRepository({
    required this.database,
    required this.eventBus,
    MemoryLruCache<int, List<ConversationItem>>? conversationMemory,
    MemoryLruCache<String, List<UnifiedMessage>>? messageMemory,
    MemoryLruCache<int, List<ImGroup>>? groupMemory,
    MemoryLruCache<String, Map<String, dynamic>>? apiMemory,
  }) : _conversationMemory =
           conversationMemory ??
           MemoryLruCache<int, List<ConversationItem>>(capacity: 12),
       _messageMemory =
           messageMemory ??
           MemoryLruCache<String, List<UnifiedMessage>>(capacity: 96),
       _groupMemory =
           groupMemory ?? MemoryLruCache<int, List<ImGroup>>(capacity: 12),
       _apiMemory =
           apiMemory ??
           MemoryLruCache<String, Map<String, dynamic>>(capacity: 256);

  Future<void> initialize() async {
    try {
      await database.assertReady();
      eventBus.emit(CacheReadyEvent(time: DateTime.now()));
    } catch (error, stackTrace) {
      eventBus.emitFailure(error, stackTrace);
      rethrow;
    }
  }

  Future<void> cacheConversations({
    required int ownerId,
    required List<ConversationItem> conversations,
  }) async {
    final now = DateTime.now();
    await database.upsertConversations(
      conversations.map(
        (item) => CachedConversationsCompanion(
          ownerId: Value(ownerId),
          conversationKey: Value(peerKey(item.userId)),
          kind: const Value('peer'),
          targetId: Value(item.userId),
          title: Value(item.nickname),
          avatar: Value(item.avatar),
          preview: Value(item.preview),
          lastMessageAt: Value(item.msgDateTime),
          unread: Value(item.unread),
          rawJson: Value(_encodeJson(item.raw)),
          updatedAt: Value(now),
        ),
      ),
    );
    _conversationMemory.set(ownerId, List.unmodifiable(conversations));
    eventBus.emit(ConversationCacheChangedEvent(time: now, ownerId: ownerId));
  }

  Future<List<ConversationItem>> loadConversations(int ownerId) async {
    final memory = _conversationMemory.get(ownerId);
    if (memory != null) return List<ConversationItem>.from(memory);
    final rows = await database.loadConversations(ownerId);
    final result = rows
        .where((row) => row.kind == 'peer')
        .map(_conversationFromRow)
        .toList(growable: false);
    _conversationMemory.set(ownerId, List.unmodifiable(result));
    return result;
  }

  Future<void> cacheMessages({
    required int ownerId,
    required String conversationKey,
    required List<UnifiedMessage> messages,
  }) async {
    final now = DateTime.now();
    await database.upsertMessages(
      messages.map(
        (message) => _messageCompanion(
          ownerId: ownerId,
          conversationKey: conversationKey,
          message: message,
          updatedAt: now,
        ),
      ),
    );
    final cacheKey = _messageCacheKey(ownerId, conversationKey);
    final current = _messageMemory.get(cacheKey) ?? const <UnifiedMessage>[];
    final merged = _mergeMessages(current, messages);
    _messageMemory.set(cacheKey, List.unmodifiable(merged));
    eventBus.emit(
      MessageCacheChangedEvent(
        time: now,
        ownerId: ownerId,
        conversationKey: conversationKey,
      ),
    );
  }

  Future<void> cacheMessage({
    required int ownerId,
    required String conversationKey,
    required UnifiedMessage message,
  }) {
    return cacheMessages(
      ownerId: ownerId,
      conversationKey: conversationKey,
      messages: [message],
    );
  }

  Future<List<UnifiedMessage>> loadMessages({
    required int ownerId,
    required String conversationKey,
    int limit = 80,
  }) async {
    final cacheKey = _messageCacheKey(ownerId, conversationKey);
    final memory = _messageMemory.get(cacheKey);
    if (memory != null) return List<UnifiedMessage>.from(memory);
    final rows = await database.loadMessages(
      ownerId: ownerId,
      conversationKey: conversationKey,
      limit: limit,
    );
    final messages = rows.map(_messageFromRow).toList(growable: false);
    _messageMemory.set(cacheKey, List.unmodifiable(messages));
    return messages;
  }

  Future<void> clearConversation({
    required int ownerId,
    required String conversationKey,
  }) async {
    await database.deleteConversationMessages(
      ownerId: ownerId,
      conversationKey: conversationKey,
    );
    _messageMemory.remove(_messageCacheKey(ownerId, conversationKey));
    eventBus.emit(
      MessageCacheChangedEvent(
        time: DateTime.now(),
        ownerId: ownerId,
        conversationKey: conversationKey,
      ),
    );
  }

  Future<void> deleteMessages({
    required int ownerId,
    required String conversationKey,
    required Iterable<UnifiedMessage> messages,
  }) async {
    final keys = messages.map(messageKey).toSet();
    await database.deleteMessages(
      ownerId: ownerId,
      conversationKey: conversationKey,
      messageKeys: keys,
    );
    _messageMemory.remove(_messageCacheKey(ownerId, conversationKey));
    eventBus.emit(
      MessageCacheChangedEvent(
        time: DateTime.now(),
        ownerId: ownerId,
        conversationKey: conversationKey,
      ),
    );
  }

  Future<void> cacheProfiles({
    required int ownerId,
    required List<UserSearchResult> users,
  }) async {
    final now = DateTime.now();
    await database.upsertProfiles(
      users.map(
        (user) => CachedProfilesCompanion(
          ownerId: Value(ownerId),
          userId: Value(user.id),
          username: Value(user.username),
          nickname: Value(user.nickname),
          avatar: Value(user.avatar),
          title: Value(user.title),
          titleColor: Value(user.titleColor),
          rawJson: Value(
            _encodeJson({
              'id': user.id,
              'username': user.username,
              'nickname': user.nickname,
              'avatar': user.avatar,
              'user_title': user.title,
              'title_color': user.titleColor,
            }),
          ),
          updatedAt: Value(now),
        ),
      ),
    );
    eventBus.emit(ProfileCacheChangedEvent(time: now, ownerId: ownerId));
  }

  Future<void> cacheGroups({
    required int ownerId,
    required List<ImGroup> groups,
  }) async {
    final now = DateTime.now();
    await database.upsertGroups(
      groups.map(
        (group) => CachedGroupsCompanion(
          ownerId: Value(ownerId),
          groupId: Value(group.id),
          groupNo: Value(group.groupNo),
          name: Value(group.name),
          avatar: Value(group.avatar),
          memberCount: Value(group.memberCount),
          rawJson: Value(_encodeJson(group.raw)),
          updatedAt: Value(now),
        ),
      ),
    );
    _groupMemory.set(ownerId, List.unmodifiable(groups));
    eventBus.emit(GroupCacheChangedEvent(time: now, ownerId: ownerId));
  }

  Future<List<ImGroup>> loadGroups(int ownerId) async {
    final memory = _groupMemory.get(ownerId);
    if (memory != null) return List<ImGroup>.from(memory);
    final rows = await database.loadGroups(ownerId);
    final groups = rows.map(_groupFromRow).toList(growable: false);
    _groupMemory.set(ownerId, List.unmodifiable(groups));
    return groups;
  }

  Future<void> cacheApiResponse({
    required String namespace,
    required String cacheKey,
    required String path,
    required Map<String, dynamic> response,
    Duration? ttl,
  }) async {
    final now = DateTime.now();
    await database.upsertApiResponse(
      CachedApiResponsesCompanion(
        namespace: Value(namespace),
        cacheKey: Value(cacheKey),
        path: Value(path),
        responseJson: Value(_encodeJson(response)),
        updatedAt: Value(now),
        expiresAt: Value(ttl == null ? null : now.add(ttl)),
      ),
    );
    _apiMemory.set(
      _apiCacheKey(namespace, cacheKey),
      Map.unmodifiable(response),
    );
    unawaited(database.deleteExpiredApiResponses(now));
  }

  Future<Map<String, dynamic>?> loadApiResponse({
    required String namespace,
    required String cacheKey,
  }) async {
    final memoryKey = _apiCacheKey(namespace, cacheKey);
    final memory = _apiMemory.get(memoryKey);
    if (memory != null) return Map<String, dynamic>.from(memory);
    final row = await database.loadApiResponse(
      namespace: namespace,
      cacheKey: cacheKey,
    );
    if (row == null) return null;
    final expiresAt = row.expiresAt;
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      return null;
    }
    final decoded = _decodeJsonMap(row.responseJson);
    _apiMemory.set(memoryKey, Map.unmodifiable(decoded));
    return decoded;
  }

  Future<void> clearUser(int ownerId) async {
    await database.clearUser(ownerId);
    _conversationMemory.remove(ownerId);
    _groupMemory.remove(ownerId);
    final prefix = '$ownerId::';
    final stale = <String>[];
    for (final key in _messageMemory.keys) {
      if (key.startsWith(prefix)) stale.add(key);
    }
    for (final key in stale) {
      _messageMemory.remove(key);
    }
    eventBus.emit(
      UserCacheClearedEvent(time: DateTime.now(), ownerId: ownerId),
    );
  }

  void clearMemory() {
    _conversationMemory.clear();
    _messageMemory.clear();
    _groupMemory.clear();
    _apiMemory.clear();
  }

  static String peerKey(int peerId) => 'peer:$peerId';

  static String groupKey(int groupId) => 'group:$groupId';

  static String _apiCacheKey(String namespace, String cacheKey) {
    return '$namespace::$cacheKey';
  }

  static String messageKey(UnifiedMessage message) {
    final direct = _firstText([
      message.raw['client_msg_no'],
      message.raw['clientMsgNo'],
      message.content['client_msg_no'],
      message.content['clientMsgNo'],
      message.messageId > 0 ? 'm:${message.messageId}' : '',
      message.raw['id'],
    ]);
    if (direct.isNotEmpty && direct != '0') return direct;
    final payload = _encodeJson({
      'from': message.fromUserId,
      'to': message.toUserId,
      'type': message.msgType,
      'time': message.createTime.toIso8601String(),
      'content': message.content,
    });
    return 'h:${crypto.sha1.convert(utf8.encode(payload))}';
  }

  static String _messageCacheKey(int ownerId, String conversationKey) {
    return '$ownerId::$conversationKey';
  }

  static CachedMessagesCompanion _messageCompanion({
    required int ownerId,
    required String conversationKey,
    required UnifiedMessage message,
    required DateTime updatedAt,
  }) {
    final key = messageKey(message);
    return CachedMessagesCompanion(
      ownerId: Value(ownerId),
      conversationKey: Value(conversationKey),
      messageKey: Value(key),
      messageId: Value(message.messageId),
      clientMsgNo: Value(
        _firstText([
          message.raw['client_msg_no'],
          message.raw['clientMsgNo'],
          message.content['client_msg_no'],
          message.content['clientMsgNo'],
        ]),
      ),
      fromUserId: Value(message.fromUserId),
      toUserId: Value(message.toUserId),
      fromUid: Value(message.fromUid),
      toUid: Value(message.toUid),
      msgType: Value(message.msgType),
      contentJson: Value(_encodeJson(message.content)),
      rawJson: Value(_encodeJson(message.raw)),
      createdAt: Value(message.createTime),
      isMe: Value(message.isMe),
      read: Value(message.read),
      readAt: Value(message.readAt),
      updatedAt: Value(updatedAt),
    );
  }

  static UnifiedMessage _messageFromRow(CachedMessage row) {
    return UnifiedMessage(
      messageId: row.messageId,
      fromUserId: row.fromUserId,
      toUserId: row.toUserId,
      fromUid: row.fromUid,
      toUid: row.toUid,
      msgType: row.msgType,
      content: _decodeJsonMap(row.contentJson),
      createTime: row.createdAt,
      isMe: row.isMe,
      read: row.read,
      readAt: row.readAt,
      raw: _decodeJsonMap(row.rawJson),
    );
  }

  static ConversationItem _conversationFromRow(CachedConversation row) {
    final raw = _decodeJsonMap(row.rawJson);
    return ConversationItem(
      userId: row.targetId,
      username: '${raw['username'] ?? ''}',
      nickname: row.title,
      avatar: row.avatar,
      preview: row.preview,
      msgTime: row.lastMessageAt?.toIso8601String() ?? '',
      msgDateTime: row.lastMessageAt,
      unread: row.unread,
      raw: raw,
    );
  }

  static ImGroup _groupFromRow(CachedGroup row) {
    final raw = _decodeJsonMap(row.rawJson);
    raw.putIfAbsent('id', () => row.groupId);
    raw.putIfAbsent('group_id', () => row.groupId);
    raw.putIfAbsent('group_no', () => row.groupNo);
    raw.putIfAbsent('name', () => row.name);
    raw.putIfAbsent('avatar', () => row.avatar);
    raw.putIfAbsent('member_count', () => row.memberCount);
    return ImGroup.fromJson(raw);
  }

  static List<UnifiedMessage> _mergeMessages(
    List<UnifiedMessage> current,
    List<UnifiedMessage> incoming,
  ) {
    final byKey = <String, UnifiedMessage>{};
    for (final message in [...current, ...incoming]) {
      byKey[messageKey(message)] = message;
    }
    final merged = byKey.values.toList()
      ..sort((a, b) => a.createTime.compareTo(b.createTime));
    return merged.length > 120 ? merged.sublist(merged.length - 120) : merged;
  }

  static String _encodeJson(Object value) => jsonEncode(value);

  static Map<String, dynamic> _decodeJsonMap(String value) {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded);
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Cached JSON is not an object: $value');
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }
}

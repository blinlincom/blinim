import 'dart:convert';

import 'package:mmkv/mmkv.dart';

import '../models/im_models.dart';
import 'api_service.dart';

class ChatCacheStore {
  ChatCacheStore._();

  static const int _maxMessagesPerConversation = 120;
  static MMKV get _kv => MMKV.defaultMMKV();

  static String _conversationListKey(int userId) =>
      'chat_cache_conversation_list_$userId';
  static String _friendsKey(int userId) => 'chat_cache_friends_$userId';
  static String _groupsKey(int userId) => 'chat_cache_groups_$userId';
  static String _groupMembersKey(int userId, int groupId) =>
      'chat_cache_group_members_${userId}_$groupId';
  static String _peerMessagesKey(int userId, int peerId) =>
      'chat_cache_peer_messages_${userId}_$peerId';
  static String _groupMessagesKey(int userId, int groupId) =>
      'chat_cache_group_messages_${userId}_$groupId';

  static Future<List<ConversationItem>> loadConversations(int userId) async {
    return _readList(
      _conversationListKey(userId),
      (json) => ConversationItem.fromJson(json),
    );
  }

  static Future<void> saveConversations(
    int userId,
    List<ConversationItem> conversations,
  ) async {
    await _writeList(
      _conversationListKey(userId),
      conversations.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<List<UserSearchResult>> loadFriends(int userId) async {
    return _readList(_friendsKey(userId), UserSearchResult.fromJson);
  }

  static Future<void> saveFriends(
    int userId,
    List<UserSearchResult> friends,
  ) async {
    await _writeList(
      _friendsKey(userId),
      friends.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<List<ImGroup>> loadGroups(int userId) async {
    return _readList(_groupsKey(userId), ImGroup.fromJson);
  }

  static Future<void> saveGroups(int userId, List<ImGroup> groups) async {
    await _writeList(
      _groupsKey(userId),
      groups.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<List<ImGroupMember>> loadGroupMembers(
    int userId,
    int groupId,
  ) async {
    return _readList(_groupMembersKey(userId, groupId), ImGroupMember.fromJson);
  }

  static Future<void> saveGroupMembers(
    int userId,
    int groupId,
    List<ImGroupMember> members,
  ) async {
    await _writeList(
      _groupMembersKey(userId, groupId),
      members.map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<List<UnifiedMessage>> loadPeerMessages({
    required int userId,
    required int peerId,
  }) async {
    return _readList(
      _peerMessagesKey(userId, peerId),
      (json) => UnifiedMessage.fromCacheJson(json, userId),
    );
  }

  static Future<void> savePeerMessages({
    required int userId,
    required int peerId,
    required List<UnifiedMessage> messages,
  }) async {
    await _writeList(
      _peerMessagesKey(userId, peerId),
      _trimMessages(messages).map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<void> clearPeerMessages({
    required int userId,
    required int peerId,
  }) async {
    _kv.removeValue(_peerMessagesKey(userId, peerId));
  }

  static Future<List<UnifiedMessage>> loadGroupMessages({
    required int userId,
    required int groupId,
  }) async {
    return _readList(
      _groupMessagesKey(userId, groupId),
      (json) => UnifiedMessage.fromCacheJson(json, userId),
    );
  }

  static Future<void> saveGroupMessages({
    required int userId,
    required int groupId,
    required List<UnifiedMessage> messages,
  }) async {
    await _writeList(
      _groupMessagesKey(userId, groupId),
      _trimMessages(messages).map((item) => item.toCacheJson()).toList(),
    );
  }

  static Future<void> clearGroupMessages({
    required int userId,
    required int groupId,
  }) async {
    _kv.removeValue(_groupMessagesKey(userId, groupId));
  }

  static List<UnifiedMessage> _trimMessages(List<UnifiedMessage> messages) {
    final sorted = [...messages]
      ..sort((a, b) => a.createTime.compareTo(b.createTime));
    if (sorted.length <= _maxMessagesPerConversation) return sorted;
    return sorted.sublist(sorted.length - _maxMessagesPerConversation);
  }

  static Future<List<T>> _readList<T>(
    String key,
    T Function(Map<String, dynamic> json) decode,
  ) async {
    final raw = _kv.decodeString(key);
    if (raw == null || raw.trim().isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is List ? decoded : const [];
      final result = <T>[];
      for (final item in list) {
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

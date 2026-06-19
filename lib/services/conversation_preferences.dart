import 'package:shared_preferences/shared_preferences.dart';

class ConversationPreferences {
  static String pinnedStorageKey(int userId) => 'pinned_conversations_$userId';
  static String mutedStorageKey(int userId) => 'muted_conversations_$userId';
  static String hiddenStorageKey(int userId) => 'hidden_conversations_$userId';
  static String pendingFriendRequestsStorageKey(int userId) =>
      'pending_friend_requests_$userId';
  static String savedGroupsStorageKey(int userId) => 'saved_groups_$userId';
  static String groupRemarkStorageKey(int userId, int groupId) =>
      'group_remark_${userId}_$groupId';
  static String peerKey(int peerId) => 'peer:$peerId';
  static String groupKey(int groupId) => 'group:$groupId';

  static Future<Set<String>> loadPinned(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(pinnedStorageKey(userId)) ?? const <String>[])
        .toSet();
  }

  static Future<Set<String>> loadMuted(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(mutedStorageKey(userId)) ?? const <String>[])
        .toSet();
  }

  static Future<Map<String, int>> loadHidden(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(hiddenStorageKey(userId)) ?? const <String>[];
    final result = <String, int>{};
    for (final item in raw) {
      final divider = item.lastIndexOf('|');
      if (divider <= 0) continue;
      final key = item.substring(0, divider);
      final timestamp = int.tryParse(item.substring(divider + 1)) ?? 0;
      if (key.isNotEmpty) result[key] = timestamp;
    }
    return result;
  }

  static Future<void> setPinned(
    int userId,
    String conversationKey,
    bool enabled,
  ) => _setValue(pinnedStorageKey(userId), conversationKey, enabled);

  static Future<void> setMuted(
    int userId,
    String conversationKey,
    bool enabled,
  ) => _setValue(mutedStorageKey(userId), conversationKey, enabled);

  static Future<void> setHidden(
    int userId,
    String conversationKey,
    int hiddenAtMillis,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final next = await loadHidden(userId);
    if (hiddenAtMillis <= 0) {
      next.remove(conversationKey);
    } else {
      next[conversationKey] = hiddenAtMillis;
    }
    await prefs.setStringList(
      hiddenStorageKey(userId),
      next.entries.map((entry) => '${entry.key}|${entry.value}').toList()
        ..sort(),
    );
  }

  static Future<Set<int>> loadPendingFriendRequests(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(pendingFriendRequestsStorageKey(userId)) ??
            const <String>[])
        .map((e) => int.tryParse(e) ?? 0)
        .where((e) => e > 0)
        .toSet();
  }

  static Future<void> setPendingFriendRequest(
    int userId,
    int peerId,
    bool pending,
  ) async {
    if (peerId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final next = await loadPendingFriendRequests(userId);
    if (pending) {
      next.add(peerId);
    } else {
      next.remove(peerId);
    }
    await prefs.setStringList(
      pendingFriendRequestsStorageKey(userId),
      next.map((e) => '$e').toList()..sort(),
    );
  }

  static Future<Set<int>> loadSavedGroups(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(savedGroupsStorageKey(userId)) ??
            const <String>[])
        .map((e) => int.tryParse(e) ?? 0)
        .where((e) => e > 0)
        .toSet();
  }

  static Future<void> setSavedGroup(
    int userId,
    int groupId,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final next =
        (prefs.getStringList(savedGroupsStorageKey(userId)) ?? const <String>[])
            .map((e) => int.tryParse(e) ?? 0)
            .where((e) => e > 0)
            .toSet();
    if (enabled) {
      next.add(groupId);
    } else {
      next.remove(groupId);
    }
    await prefs.setStringList(
      savedGroupsStorageKey(userId),
      next.map((e) => '$e').toList()..sort(),
    );
  }

  static Future<String> loadGroupRemark(int userId, int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(groupRemarkStorageKey(userId, groupId)) ?? '';
  }

  static Future<void> setGroupRemark(
    int userId,
    int groupId,
    String remark,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = groupRemarkStorageKey(userId, groupId);
    final value = remark.trim();
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static Future<void> _setValue(
    String storageKey,
    String conversationKey,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
    if (enabled) {
      next.add(conversationKey);
    } else {
      next.remove(conversationKey);
    }
    await prefs.setStringList(storageKey, next.toList()..sort());
  }
}

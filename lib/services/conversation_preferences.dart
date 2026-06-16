import 'package:shared_preferences/shared_preferences.dart';

class ConversationPreferences {
  static String pinnedStorageKey(int userId) => 'pinned_conversations_$userId';
  static String mutedStorageKey(int userId) => 'muted_conversations_$userId';
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

  static Future<void> setPinned(
    int userId,
    String conversationKey,
    bool enabled,
  ) =>
      _setValue(pinnedStorageKey(userId), conversationKey, enabled);

  static Future<void> setMuted(
    int userId,
    String conversationKey,
    bool enabled,
  ) =>
      _setValue(mutedStorageKey(userId), conversationKey, enabled);

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

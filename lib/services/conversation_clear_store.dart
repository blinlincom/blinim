import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConversationClearStore {
  const ConversationClearStore._();

  static String storageKey(int userId, String conversationKey) {
    final encoded = base64UrlEncode(
      utf8.encode(conversationKey),
    ).replaceAll('=', '');
    return 'conversation_clear_time_${userId}_$encoded';
  }

  static Future<DateTime?> load(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(storageKey(userId, conversationKey)) ?? 0;
    if (value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static Future<void> mark(
    int userId,
    String conversationKey,
    DateTime clearTime,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      storageKey(userId, conversationKey),
      clearTime.millisecondsSinceEpoch,
    );
  }

  static Future<void> clear(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey(userId, conversationKey));
  }
}

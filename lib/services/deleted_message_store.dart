import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DeletedMessageStore {
  static const int _maxKeys = 1200;

  const DeletedMessageStore._();

  static String storageKey(int userId, String conversationKey) {
    final encoded = base64UrlEncode(
      utf8.encode(conversationKey),
    ).replaceAll('=', '');
    return 'deleted_message_keys_${userId}_$encoded';
  }

  static Future<Set<String>> load(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(storageKey(userId, conversationKey)) ??
        const <String>[];
    return raw
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != '0' && item != 'null')
        .toSet();
  }

  static Future<void> add(
    int userId,
    String conversationKey,
    Iterable<String> keys,
  ) async {
    final next = <String>[
      ...await load(userId, conversationKey),
      ...keys
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && item != '0' && item != 'null'),
    ];
    final deduped = <String>[];
    final seen = <String>{};
    for (final key in next) {
      if (seen.add(key)) deduped.add(key);
    }
    final trimmed = deduped.length > _maxKeys
        ? deduped.sublist(deduped.length - _maxKeys)
        : deduped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey(userId, conversationKey), trimmed);
  }

  static Future<void> clear(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey(userId, conversationKey));
  }
}

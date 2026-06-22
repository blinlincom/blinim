import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/im_models.dart';

class LocalNoticeStore {
  static const int _maxNotices = 120;

  const LocalNoticeStore._();

  static String storageKey(int userId, String conversationKey) {
    final encoded = base64UrlEncode(
      utf8.encode(conversationKey),
    ).replaceAll('=', '');
    return 'local_notice_messages_${userId}_$encoded';
  }

  static Future<List<UnifiedMessage>> load(
    int userId,
    String conversationKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(storageKey(userId, conversationKey)) ??
        const <String>[];
    final messages = <UnifiedMessage>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final message = _messageFromJson(decoded, userId);
          if (message != null) messages.add(message);
        } else if (decoded is Map) {
          final message = _messageFromJson(
            Map<String, dynamic>.from(decoded),
            userId,
          );
          if (message != null) messages.add(message);
        }
      } catch (_) {}
    }
    messages.sort((a, b) => a.createTime.compareTo(b.createTime));
    return messages;
  }

  static Future<void> upsert(
    int userId,
    String conversationKey,
    UnifiedMessage message,
  ) async {
    final current = await load(userId, conversationKey);
    final key = messageKey(message);
    final next = <UnifiedMessage>[
      for (final item in current)
        if (messageKey(item) != key) item,
      message,
    ]..sort((a, b) => a.createTime.compareTo(b.createTime));
    final trimmed = next.length > _maxNotices
        ? next.sublist(next.length - _maxNotices)
        : next;
    await _save(userId, conversationKey, trimmed);
  }

  static Future<void> remove(
    int userId,
    String conversationKey,
    Iterable<String> keys,
  ) async {
    final removeKeys = keys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != '0' && item != 'null')
        .toSet();
    if (removeKeys.isEmpty) return;
    final current = await load(userId, conversationKey);
    final next = current
        .where((message) => !removeKeys.contains(messageKey(message)))
        .toList();
    await _save(userId, conversationKey, next);
  }

  static Future<void> clear(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey(userId, conversationKey));
  }

  static String messageKey(UnifiedMessage message) {
    if (message.msgType == 'red_packet_receipt') {
      final receiptKey = '${message.content['receipt_key'] ?? ''}'.trim();
      final claimerId = '${message.content['claimer_id'] ?? ''}'.trim();
      if (receiptKey.isNotEmpty && claimerId.isNotEmpty) {
        return 'red_packet_receipt_${receiptKey}_$claimerId';
      }
    }
    final raw = message.raw;
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
    if (direct.isNotEmpty && direct != '0' && direct != 'null') return direct;
    return '${message.fromUserId}_${message.toUserId}_${message.msgType}_${message.createTime.millisecondsSinceEpoch ~/ 1000}_${jsonEncode(message.content)}';
  }

  static Future<void> _save(
    int userId,
    String conversationKey,
    List<UnifiedMessage> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey(userId, conversationKey),
      messages.map((message) => jsonEncode(_messageToJson(message))).toList(),
    );
  }

  static Map<String, dynamic> _messageToJson(UnifiedMessage message) => {
    'message_id': message.messageId,
    'from_user_id': message.fromUserId,
    'to_user_id': message.toUserId,
    'from_uid': message.fromUid,
    'to_uid': message.toUid,
    'msg_type': message.msgType,
    'content': message.content,
    'create_time': message.createTime.toIso8601String(),
    'is_me': message.isMe,
    'read': message.read,
    if (message.readAt != null) 'read_at': message.readAt!.toIso8601String(),
    'raw': message.raw,
  };

  static UnifiedMessage? _messageFromJson(Map<String, dynamic> json, int myId) {
    final raw = json['raw'] is Map
        ? Map<String, dynamic>.from(json['raw'] as Map)
        : <String, dynamic>{};
    final content = json['content'] is Map
        ? Map<String, dynamic>.from(json['content'] as Map)
        : <String, dynamic>{};
    final createTime =
        DateTime.tryParse('${json['create_time'] ?? ''}') ?? DateTime.now();
    final readAt = DateTime.tryParse('${json['read_at'] ?? ''}');
    final fromUserId = int.tryParse('${json['from_user_id'] ?? 0}') ?? 0;
    return UnifiedMessage(
      messageId: int.tryParse('${json['message_id'] ?? 0}') ?? 0,
      fromUserId: fromUserId,
      toUserId: int.tryParse('${json['to_user_id'] ?? 0}') ?? 0,
      fromUid: '${json['from_uid'] ?? ''}',
      toUid: '${json['to_uid'] ?? ''}',
      msgType: '${json['msg_type'] ?? ''}',
      content: content,
      createTime: createTime,
      isMe: json['is_me'] == true || fromUserId == myId,
      read: json['read'] == true || '${json['read']}' == '1',
      readAt: readAt,
      raw: raw,
    );
  }
}

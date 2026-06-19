import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FailedMessageDraft {
  final Map<String, dynamic> payload;
  final String fallbackContent;
  final int messageType;

  const FailedMessageDraft({
    required this.payload,
    required this.fallbackContent,
    required this.messageType,
  });

  String get key {
    final direct =
        '${payload['client_msg_no'] ?? payload['message_id'] ?? payload['id'] ?? ''}'
            .trim();
    if (direct.isNotEmpty && direct != '0' && direct != 'null') return direct;
    return jsonEncode(payload);
  }

  Map<String, dynamic> toJson() => {
    'payload': payload,
    'fallback_content': fallbackContent,
    'message_type': messageType,
  };

  factory FailedMessageDraft.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final payload = rawPayload is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawPayload)
        : rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    return FailedMessageDraft(
      payload: payload,
      fallbackContent: '${json['fallback_content'] ?? json['content'] ?? ''}',
      messageType: int.tryParse('${json['message_type'] ?? 0}') ?? 0,
    );
  }
}

class FailedMessageStore {
  static const int _maxDrafts = 80;

  static String storageKey(int userId, String conversationKey) {
    final encoded = base64UrlEncode(
      utf8.encode(conversationKey),
    ).replaceAll('=', '');
    return 'failed_message_drafts_${userId}_$encoded';
  }

  static Future<List<FailedMessageDraft>> load(
    int userId,
    String conversationKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(storageKey(userId, conversationKey)) ??
        const <String>[];
    final drafts = <FailedMessageDraft>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final draft = FailedMessageDraft.fromJson(decoded);
          if (draft.payload.isNotEmpty) drafts.add(draft);
        } else if (decoded is Map) {
          final draft = FailedMessageDraft.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (draft.payload.isNotEmpty) drafts.add(draft);
        }
      } catch (_) {}
    }
    drafts.sort((a, b) => _draftTime(a).compareTo(_draftTime(b)));
    return drafts;
  }

  static Future<void> upsert(
    int userId,
    String conversationKey,
    FailedMessageDraft draft,
  ) async {
    final current = await load(userId, conversationKey);
    final next = <FailedMessageDraft>[
      for (final item in current)
        if (item.key != draft.key) item,
      draft,
    ]..sort((a, b) => _draftTime(a).compareTo(_draftTime(b)));
    final trimmed = next.length > _maxDrafts
        ? next.sublist(next.length - _maxDrafts)
        : next;
    await _save(userId, conversationKey, trimmed);
  }

  static Future<void> remove(
    int userId,
    String conversationKey,
    String messageKey,
  ) async {
    final current = await load(userId, conversationKey);
    final next = current.where((draft) => draft.key != messageKey).toList();
    await _save(userId, conversationKey, next);
  }

  static Future<void> clear(int userId, String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey(userId, conversationKey));
  }

  static Future<void> _save(
    int userId,
    String conversationKey,
    List<FailedMessageDraft> drafts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey(userId, conversationKey),
      drafts.map((draft) => jsonEncode(draft.toJson())).toList(),
    );
  }

  static int _draftTime(FailedMessageDraft draft) {
    final payload = draft.payload;
    final direct = int.tryParse('${payload['timestamp'] ?? ''}');
    if (direct != null && direct > 0) return direct;
    final parsed = DateTime.tryParse('${payload['create_time'] ?? ''}');
    return parsed?.millisecondsSinceEpoch ?? 0;
  }
}

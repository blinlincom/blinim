import 'dart:convert';

class ImConnectInfo {
  final String uid;
  final String token;
  final String wsAddr;
  const ImConnectInfo({
    required this.uid,
    required this.token,
    required this.wsAddr,
  });
  factory ImConnectInfo.fromJson(Map<String, dynamic> json) => ImConnectInfo(
    uid: '${json['uid'] ?? ''}',
    token: '${json['token'] ?? ''}',
    wsAddr: '${json['ws_addr'] ?? json['route']?['ws_addr'] ?? ''}',
  );
}

class UnifiedMessage {
  final int messageId;
  final int fromUserId;
  final int toUserId;
  final String fromUid;
  final String toUid;
  final String msgType;
  final Map<String, dynamic> content;
  final DateTime createTime;
  final bool isMe;
  final Map<String, dynamic> raw;

  const UnifiedMessage({
    required this.messageId,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUid,
    required this.toUid,
    required this.msgType,
    required this.content,
    required this.createTime,
    required this.isMe,
    required this.raw,
  });

  String get preview {
    if (msgType == 'image') return '[图片] ${content['text'] ?? ''}';
    if (msgType == 'video') return '[视频] ${content['name'] ?? ''}';
    if (msgType == 'transfer') return '[转账] ${content['amount'] ?? ''}';
    if (msgType == 'file') return '[文件] ${content['name'] ?? ''}';
    return '${content['text'] ?? content['content'] ?? ''}';
  }

  factory UnifiedMessage.fromPayload(Map<String, dynamic> payload, int myId) {
    final contentRaw = payload['content'];
    final content = contentRaw is Map
        ? Map<String, dynamic>.from(contentRaw)
        : {'text': '${contentRaw ?? payload['legacy']?['content'] ?? ''}'};
    final fromId =
        int.tryParse(
          '${payload['from_user_id'] ?? payload['sender_id'] ?? payload['legacy']?['sender_id'] ?? 0}',
        ) ??
        0;
    final toId =
        int.tryParse(
          '${payload['to_user_id'] ?? payload['receiver_id'] ?? payload['legacy']?['receiver_id'] ?? 0}',
        ) ??
        0;
    return UnifiedMessage(
      messageId: int.tryParse('${payload['message_id'] ?? 0}') ?? 0,
      fromUserId: fromId,
      toUserId: toId,
      fromUid: '${payload['from_uid'] ?? ''}',
      toUid: '${payload['to_uid'] ?? ''}',
      msgType: '${payload['msg_type'] ?? _legacyType(payload)}',
      content: content,
      createTime:
          DateTime.tryParse('${payload['create_time'] ?? ''}') ??
          DateTime.now(),
      isMe: fromId == myId,
      raw: payload,
    );
  }

  factory UnifiedMessage.fromHistory(Map<String, dynamic> item, int myId) {
    final msg = Map<String, dynamic>.from(item['message'] ?? item);
    final payload = msg['im_payload'] ?? item['im_payload'];
    final payloadMap = _decodeAnyPayload(payload);
    if (payloadMap != null) {
      return UnifiedMessage.fromPayload(payloadMap, myId);
    }
    return UnifiedMessage.fromPayload({
      'message_id': msg['id'],
      'from_user_id': item['fromUser']?['id'],
      'to_user_id': 0,
      'msg_type': _legacyType(msg),
      'message_type': msg['message_type'],
      'content': msg['message_type'] == 1
          ? {'url': msg['image_path'], 'text': msg['content']}
          : {'text': msg['content']},
      'legacy': msg,
      'create_time': msg['create_time'],
    }, myId);
  }

  static Map<String, dynamic>? _decodeAnyPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final text = raw.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>)
          return Map<String, dynamic>.from(decoded);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      try {
        var compact = text.replaceAll(RegExp(r'\s+'), '');
        var padded = compact.replaceAll('-', '+').replaceAll('_', '/');
        while (padded.length % 4 != 0) {
          padded += '=';
        }
        final decodedText = utf8.decode(
          base64.decode(padded),
          allowMalformed: true,
        );
        final decoded = jsonDecode(decodedText);
        if (decoded is Map<String, dynamic>)
          return Map<String, dynamic>.from(decoded);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String _legacyType(Map payload) {
    final t =
        int.tryParse(
          '${payload['message_type'] ?? payload['type'] ?? payload['legacy']?['type'] ?? 0}',
        ) ??
        0;
    if (t == 1) return 'image';
    if (t == 2) return 'transfer';
    if (t == 3) return 'file';
    if (t == 4) return 'video';
    return 'text';
  }
}

class ConversationItem {
  final int userId;
  final String username;
  final String nickname;
  final String avatar;
  final String preview;
  final String msgTime;
  final int unread;

  const ConversationItem({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.preview,
    required this.msgTime,
    required this.unread,
  });

  factory ConversationItem.fromJson(Map<String, dynamic> j) {
    final user = _asMap(
      j['user'] ?? j['friend'] ?? j['toUser'] ?? j['fromUser'] ?? j['userinfo'],
    );
    final msg = _asMap(
      j['message'] ?? j['last_message'] ?? j['lastMessage'] ?? j['msg'],
    );
    final payload = _decodePayload(
      j['im_payload'] ?? msg['im_payload'] ?? j['payload'] ?? msg['payload'],
    );
    final content = _asMap(payload['content']);

    final userId = _toInt(
      j['userid'] ??
          j['user_id'] ??
          j['friend_id'] ??
          j['id'] ??
          user['id'] ??
          user['userid'] ??
          user['uid'] ??
          payload['from_user_id'] ??
          payload['to_user_id'],
    );
    final username = _str(
      j['username'] ?? user['username'] ?? user['user'] ?? '',
    );
    final nicknameCandidate = _str(
      j['nickname'] ?? user['nickname'] ?? user['username'] ?? username,
    );
    final nickname = nicknameCandidate.isNotEmpty
        ? nicknameCandidate
        : '用户$userId';
    final avatar = _str(
      j['usertx'] ?? j['avatar'] ?? user['usertx'] ?? user['avatar'] ?? '',
    );

    return ConversationItem(
      userId: userId,
      username: username,
      nickname: nickname,
      avatar: avatar,
      preview: _conversationPreview(j, msg, payload, content),
      msgTime: _str(
        j['msg_time'] ??
            j['create_time'] ??
            j['updated_at'] ??
            msg['create_time'] ??
            payload['create_time'] ??
            '',
      ),
      unread: _toInt(
        j['unread_quantity'] ?? j['unread'] ?? j['unread_count'] ?? 0,
      ),
    );
  }

  static String _conversationPreview(
    Map<String, dynamic> j,
    Map<String, dynamic> msg,
    Map<String, dynamic> payload,
    Map<String, dynamic> content,
  ) {
    final msgType = _str(
      payload['msg_type'] ??
          payload['message_type'] ??
          msg['msg_type'] ??
          msg['message_type'],
    );
    if (msgType == 'image' || msgType == '1')
      return '[图片] ${_str(content['text'] ?? msg['content'])}'.trim();
    if (msgType == 'transfer' || msgType == '2')
      return '[转账] ${_str(content['amount'] ?? content['money'] ?? msg['money'])}'
          .trim();
    if (msgType == 'file' || msgType == '3')
      return '[文件] ${_str(content['name'] ?? msg['file_name'])}'.trim();
    if (msgType == 'video' || msgType == '4')
      return '[视频] ${_str(content['name'] ?? msg['file_name'] ?? msg['content'])}'
          .trim();
    final text = _str(
      content['text'] ??
          content['content'] ??
          payload['content'] ??
          msg['content'] ??
          j['content'] ??
          j['preview'],
    );
    return text.isEmpty ? '[消息]' : text;
  }

  static Map<String, dynamic> _decodePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final text = raw.trim();
      final direct = _jsonMap(text);
      if (direct != null) return direct;
      final compact = text.replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^[A-Za-z0-9_\-+/=]+$').hasMatch(compact)) {
        try {
          var padded = compact.replaceAll('-', '+').replaceAll('_', '/');
          while (padded.length % 4 != 0) {
            padded += '=';
          }
          final decoded = utf8.decode(
            base64.decode(padded),
            allowMalformed: true,
          );
          final map = _jsonMap(decoded.trim());
          if (map != null) return map;
        } catch (_) {}
      }
    }
    return const {};
  }

  static Map<String, dynamic>? _jsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>)
        return Map<String, dynamic>.from(decoded);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static int _toInt(dynamic value) => int.tryParse('$value') ?? 0;
  static String _str(dynamic value) => value == null ? '' : '$value';
}

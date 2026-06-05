class ImConnectInfo {
  final String uid;
  final String token;
  final String wsAddr;
  const ImConnectInfo({required this.uid, required this.token, required this.wsAddr});
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
    if (msgType == 'transfer') return '[转账] ${content['amount'] ?? ''}';
    if (msgType == 'file') return '[文件] ${content['name'] ?? ''}';
    return '${content['text'] ?? content['content'] ?? ''}';
  }

  factory UnifiedMessage.fromPayload(Map<String, dynamic> payload, int myId) {
    final contentRaw = payload['content'];
    final content = contentRaw is Map ? Map<String, dynamic>.from(contentRaw) : {'text': '${contentRaw ?? payload['legacy']?['content'] ?? ''}'};
    final fromId = int.tryParse('${payload['from_user_id'] ?? payload['sender_id'] ?? payload['legacy']?['sender_id'] ?? 0}') ?? 0;
    final toId = int.tryParse('${payload['to_user_id'] ?? payload['receiver_id'] ?? payload['legacy']?['receiver_id'] ?? 0}') ?? 0;
    return UnifiedMessage(
      messageId: int.tryParse('${payload['message_id'] ?? 0}') ?? 0,
      fromUserId: fromId,
      toUserId: toId,
      fromUid: '${payload['from_uid'] ?? ''}',
      toUid: '${payload['to_uid'] ?? ''}',
      msgType: '${payload['msg_type'] ?? _legacyType(payload)}',
      content: content,
      createTime: DateTime.tryParse('${payload['create_time'] ?? ''}') ?? DateTime.now(),
      isMe: fromId == myId,
      raw: payload,
    );
  }

  factory UnifiedMessage.fromHistory(Map<String, dynamic> item, int myId) {
    final msg = Map<String, dynamic>.from(item['message'] ?? item);
    final payload = msg['im_payload'];
    if (payload is Map) return UnifiedMessage.fromPayload(Map<String, dynamic>.from(payload), myId);
    return UnifiedMessage.fromPayload({
      'message_id': msg['id'],
      'from_user_id': item['fromUser']?['id'],
      'to_user_id': 0,
      'msg_type': _legacyType(msg),
      'message_type': msg['message_type'],
      'content': msg['message_type'] == 1 ? {'url': msg['image_path'], 'text': msg['content']} : {'text': msg['content']},
      'legacy': msg,
      'create_time': msg['create_time'],
    }, myId);
  }

  static String _legacyType(Map payload) {
    final t = int.tryParse('${payload['message_type'] ?? payload['type'] ?? payload['legacy']?['type'] ?? 0}') ?? 0;
    if (t == 1) return 'image';
    if (t == 2) return 'transfer';
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
  const ConversationItem({required this.userId, required this.username, required this.nickname, required this.avatar, required this.preview, required this.msgTime, required this.unread});
  factory ConversationItem.fromJson(Map<String, dynamic> j) => ConversationItem(
    userId: int.tryParse('${j['userid'] ?? j['id'] ?? 0}') ?? 0,
    username: '${j['username'] ?? ''}',
    nickname: '${j['nickname'] ?? j['username'] ?? '用户'}',
    avatar: '${j['usertx'] ?? ''}',
    preview: '${j['content'] ?? ''}',
    msgTime: '${j['msg_time'] ?? ''}',
    unread: int.tryParse('${j['unread_quantity'] ?? 0}') ?? 0,
  );
}

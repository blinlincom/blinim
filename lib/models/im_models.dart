import 'dart:convert';

class ImConnectInfo {
  final String uid;
  final String token;
  final String tcpAddr;
  const ImConnectInfo({
    required this.uid,
    required this.token,
    required this.tcpAddr,
  });
  factory ImConnectInfo.fromJson(Map<String, dynamic> json) => ImConnectInfo(
    uid: '${json['uid'] ?? ''}',
    token: '${json['token'] ?? ''}',
    tcpAddr:
        '${json['tcp_addr'] ?? json['addr'] ?? json['im_addr'] ?? json['route']?['tcp_addr'] ?? json['route']?['addr'] ?? ''}',
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
  final bool read;
  final DateTime? readAt;
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
    this.read = false,
    this.readAt,
    required this.raw,
  });

  UnifiedMessage copyWith({
    int? messageId,
    String? msgType,
    Map<String, dynamic>? content,
    DateTime? createTime,
    bool? read,
    DateTime? readAt,
    Map<String, dynamic>? raw,
  }) => UnifiedMessage(
    messageId: messageId ?? this.messageId,
    fromUserId: fromUserId,
    toUserId: toUserId,
    fromUid: fromUid,
    toUid: toUid,
    msgType: msgType ?? this.msgType,
    content: content ?? this.content,
    createTime: createTime ?? this.createTime,
    isMe: isMe,
    read: read ?? this.read,
    readAt: readAt ?? this.readAt,
    raw: raw ?? this.raw,
  );

  String get preview {
    if (msgType == 'recall') return '${content['text'] ?? '消息已撤回'}';
    if (msgType == 'screenshot') return '${content['text'] ?? '[截屏]'}';
    if (msgType == 'image') {
      return _mediaPreview(
        _isGifContent(content) ? 'GIF' : '图片',
        _decodeEscapedText('${content['text'] ?? ''}'),
      );
    }
    if (msgType == 'video') return _mediaPreview('视频', content['name']);
    if (msgType == 'voice') {
      return '[语音] ${_formatVoiceDuration(content['duration'])}';
    }
    if (msgType == 'transfer') return '[转账] ${content['amount'] ?? ''}';
    if (msgType == 'red_packet') {
      final greeting = '${content['greeting'] ?? content['text'] ?? ''}'
          .replaceFirst('[红包]', '')
          .trim();
      return greeting.isEmpty ? '[红包]' : '[红包] $greeting';
    }
    if (msgType == 'transfer_receipt') {
      return '${content['text'] ?? content['status'] ?? '[转账回执]'}';
    }
    if (msgType == 'red_packet_receipt') {
      return '${content['text'] ?? content['status'] ?? '[红包回执]'}';
    }
    if (msgType == 'emoji') {
      return _decodeEscapedText('${content['emoji'] ?? content['text'] ?? ''}');
    }
    if (msgType == 'file') return _mediaPreview('文件', content['name']);
    if (msgType == 'call_record') {
      final media = '${content['media']}'.contains('video') ? '视频' : '语音';
      final status = '${content['status']}';
      if (status == 'finished') {
        return '[$media通话] ${_formatCallDuration(content['duration'])}';
      }
      if (status == 'busy') return '[$media通话] 对方忙线';
      if (status == 'missed') return '[$media通话] 未接听';
      if (status == 'rejected') return '[$media通话] 已拒绝';
      if (status == 'failed') return '[$media通话] 连接失败';
      return '[$media通话] 已取消';
    }
    if (msgType == 'call') {
      final media = '${content['media']}'.contains('video') ? '视频' : '语音';
      final action = '${content['action'] ?? content['type'] ?? ''}';
      final visible =
          content['visible'] == true || '${content['visible']}' == 'true';
      if (visible && (action.contains('invite') || action.contains('offer'))) {
        return '[$media通话邀请]';
      }
      return '';
    }
    if (msgType == 'group_call_invite') {
      final media = '${content['media']}'.contains('video') ? '视频' : '语音';
      final name =
          '${content['starter_nickname'] ?? content['nickname'] ?? '群成员'}';
      return '[群$media通话] $name 发起了群通话';
    }
    if (msgType == 'group_call_record') {
      final media = '${content['media']}'.contains('video') ? '视频' : '语音';
      final status = '${content['status']}';
      if (status == 'finished') {
        return '[群$media通话] ${_formatCallDuration(content['duration'])}';
      }
      if (status == 'busy') return '[群$media通话] 忙线';
      if (status == 'missed') return '[群$media通话] 未接听';
      if (status == 'rejected') return '[群$media通话] 已拒绝';
      if (status == 'failed') return '[群$media通话] 连接失败';
      return '[群$media通话] 已取消';
    }
    if (msgType == 'group_call_join' || msgType == 'group_call_leave') {
      return '';
    }
    return _decodeEscapedText('${content['text'] ?? content['content'] ?? ''}');
  }

  factory UnifiedMessage.fromPayload(Map<String, dynamic> payload, int myId) {
    final legacy = payload['legacy'] is Map
        ? Map<String, dynamic>.from(payload['legacy'])
        : const <String, dynamic>{};
    final contentRaw = payload['content'];
    final content = contentRaw is Map
        ? Map<String, dynamic>.from(contentRaw)
        : {'text': '${contentRaw ?? legacy['content'] ?? ''}'};
    _mergeMediaHints(content, payload, legacy);
    final fromId =
        int.tryParse(
          '${payload['from_user_id'] ?? payload['sender_id'] ?? legacy['sender_id'] ?? 0}',
        ) ??
        0;
    final toId =
        int.tryParse(
          '${payload['to_user_id'] ?? payload['receiver_id'] ?? legacy['receiver_id'] ?? 0}',
        ) ??
        0;
    final msgType = _newProtocolType({
      ...payload,
      'content': contentRaw is Map ? contentRaw : content['text'],
    });
    final normalizedMsgType = msgType != 'image' && _isGifContent(content)
        ? 'image'
        : msgType;
    final normalizedContentRaw = content;
    _mergeMediaHints(normalizedContentRaw, payload, legacy);
    final normalizedContent = _decodeTextFields(normalizedContentRaw);
    final readAt = _parseDate(
      payload['read_at'] ??
          payload['read_time'] ??
          payload['readAt'] ??
          legacy['read_at'] ??
          legacy['read_time'],
    );
    final read =
        _truthy(
          payload['is_read'] ??
              payload['read'] ??
              payload['read_status'] ??
              legacy['is_read'] ??
              legacy['read'],
        ) ||
        readAt != null;
    return UnifiedMessage(
      messageId: int.tryParse('${payload['message_id'] ?? 0}') ?? 0,
      fromUserId: fromId,
      toUserId: toId,
      fromUid: '${payload['from_uid'] ?? ''}',
      toUid: '${payload['to_uid'] ?? ''}',
      msgType: normalizedMsgType,
      content: normalizedContent,
      createTime:
          DateTime.tryParse('${payload['create_time'] ?? ''}') ??
          DateTime.now(),
      isMe: fromId == myId,
      read: read,
      readAt: readAt,
      raw: payload,
    );
  }

  factory UnifiedMessage.fromHistory(
    Map<String, dynamic> item,
    int myId, {
    bool isGroup = false,
  }) {
    final msg = Map<String, dynamic>.from(item['message'] ?? item);
    final payload = msg['im_payload'] ?? item['im_payload'];
    final payloadMap = _decodeAnyPayload(payload);
    if (payloadMap != null) {
      _mergeHistoryEnvelope(payloadMap, item, msg, myId, isGroup: isGroup);
      return UnifiedMessage.fromPayload(payloadMap, myId);
    }
    final fromUserId =
        int.tryParse(
          '${item['fromUser']?['id'] ?? msg['sender_id'] ?? msg['from_user_id'] ?? 0}',
        ) ??
        0;
    final recalled = _truthy(msg['is_recalled'] ?? item['is_recalled']);
    final type = recalled ? 'recall' : _newProtocolType(msg);
    final content = recalled
        ? {
            'message_id': msg['id'] ?? item['message_id'],
            'text': _recallText(fromUserId, myId, isGroup: isGroup),
          }
        : {'text': _decodeEscapedText('${msg['content'] ?? ''}')};
    return UnifiedMessage.fromPayload({
      'message_id': msg['id'],
      'from_user_id': fromUserId,
      'to_user_id': msg['receiver_id'] ?? msg['to_user_id'] ?? 0,
      'msg_type': type,
      'content': content,
      'legacy': msg,
      'create_time': msg['create_time'],
      'is_read': msg['is_read'] ?? item['is_read'],
      'read': msg['read'] ?? item['read'],
      'read_at': msg['read_at'] ?? item['read_at'],
    }, myId);
  }

  static void _mergeHistoryEnvelope(
    Map<String, dynamic> payload,
    Map<String, dynamic> item,
    Map<String, dynamic> msg,
    int myId, {
    bool isGroup = false,
  }) {
    final messageId = msg['id'] ?? msg['message_id'] ?? item['message_id'];
    final currentId = int.tryParse('${payload['message_id'] ?? 0}') ?? 0;
    if (currentId <= 0 && messageId != null) {
      payload['message_id'] = messageId;
    }
    payload.putIfAbsent('create_time', () => msg['create_time']);
    payload.putIfAbsent('from_user_id', () => msg['sender_id']);
    payload.putIfAbsent('to_user_id', () => msg['receiver_id']);
    final read =
        msg['is_read'] ?? item['is_read'] ?? msg['read'] ?? item['read'];
    if (read != null) {
      payload['is_read'] = read;
      payload['read'] = read;
    }
    final readAt = msg['read_at'] ?? item['read_at'] ?? msg['read_time'];
    if (readAt != null) {
      payload['read_at'] = readAt;
    }
    final fromUser = _asMap(
      item['fromUser'] ??
          item['from_user'] ??
          item['sender'] ??
          msg['fromUser'] ??
          msg['from_user'] ??
          msg['sender'],
    );
    if (fromUser.isNotEmpty) {
      payload.putIfAbsent('fromUser', () => fromUser);
      _putNonEmpty(
        payload,
        'nickname',
        fromUser['nickname'] ?? fromUser['username'] ?? fromUser['name'],
      );
      _putNonEmpty(
        payload,
        'avatar',
        fromUser['avatar'] ?? fromUser['usertx'] ?? fromUser['user_avatar'],
      );
    }
    _putNonEmpty(
      payload,
      'nickname',
      item['nickname'] ?? msg['nickname'] ?? item['sender_name'],
    );
    _putNonEmpty(
      payload,
      'avatar',
      item['avatar'] ?? msg['avatar'] ?? item['usertx'] ?? msg['usertx'],
    );
    final payloadMsgType =
        '${payload['msg_type'] ?? payload['type_name'] ?? ''}'.toLowerCase();
    final recalled =
        _truthy(msg['is_recalled'] ?? item['is_recalled']) ||
        payloadMsgType == 'recall';
    if (recalled) {
      final fromUserId =
          int.tryParse('${payload['from_user_id'] ?? msg['sender_id'] ?? 0}') ??
          0;
      payload['msg_type'] = 'recall';
      payload['content'] = {
        'message_id': messageId,
        'client_msg_no': payload['client_msg_no'] ?? msg['client_msg_no'],
        'text': _recallText(fromUserId, myId, isGroup: isGroup),
      };
    }
  }

  static String _recallText(int fromUserId, int myId, {bool isGroup = false}) {
    if (fromUserId > 0 && fromUserId == myId) return '你撤回了一条消息';
    return isGroup ? '撤回了一条消息' : '对方撤回了一条消息';
  }

  static void _putNonEmpty(
    Map<String, dynamic> target,
    String key,
    Object? value,
  ) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return;
    final current = '${target[key] ?? ''}'.trim();
    if (current.isEmpty || current == 'null') target[key] = text;
  }

  static String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static void _mergeMediaHints(
    Map<String, dynamic> content,
    Map<String, dynamic> payload,
    Map<String, dynamic> legacy,
  ) {
    final url = _firstNonEmpty([
      content['url'],
      content['file_url'],
      content['image_path'],
      content['file_path'],
      content['path'],
      content['src'],
      payload['url'],
      payload['file_url'],
      payload['image_path'],
      payload['file_path'],
      payload['path'],
      payload['src'],
      legacy['url'],
      legacy['file_url'],
      legacy['image_path'],
      legacy['file_path'],
      legacy['path'],
      legacy['src'],
    ]);
    if (url.isNotEmpty) {
      content.putIfAbsent('url', () => url);
      content.putIfAbsent('file_url', () => url);
      content.putIfAbsent('image_path', () => url);
    }
    final name = _firstNonEmpty([
      content['name'],
      content['file_name'],
      payload['name'],
      payload['file_name'],
      legacy['name'],
      legacy['file_name'],
    ]);
    if (name.isNotEmpty) {
      content.putIfAbsent('name', () => name);
      content.putIfAbsent('file_name', () => name);
    }
    final text = _firstNonEmpty([
      content['text'],
      content['content'],
      payload['content'] is Map ? null : payload['content'],
      legacy['content'],
    ]);
    final format =
        '${content['media_format'] ?? content['format'] ?? payload['media_format'] ?? payload['format'] ?? legacy['media_format'] ?? legacy['format'] ?? ''}'
            .toLowerCase();
    final isGif =
        text == '[GIF]' ||
        format == 'gif' ||
        _truthy(
          content['animated'] ??
              content['is_gif'] ??
              payload['animated'] ??
              payload['is_gif'] ??
              legacy['animated'] ??
              legacy['is_gif'],
        ) ||
        _looksLikeGif(url) ||
        _looksLikeGif(name);
    if (isGif) {
      content['media_format'] = 'gif';
      content['format'] = 'gif';
      content['animated'] = true;
      content['is_gif'] = true;
      if (text == '[GIF]') {
        content.remove('text');
        content.remove('content');
      }
    }
  }

  static Map<String, dynamic> _decodeTextFields(Map<String, dynamic> source) {
    final decoded = Map<String, dynamic>.from(source);
    for (final key in const ['text', 'content', 'emoji', 'name', 'note']) {
      final value = decoded[key];
      if (value is String) decoded[key] = _decodeEscapedText(value);
    }
    return decoded;
  }

  static String _decodeEscapedText(String text) {
    var source = text;
    if (source.contains(r'\\u')) {
      source = source.replaceAll(r'\\u', r'\u');
    }
    if (!source.contains(r'\u') && !source.contains(r'\/')) return source;
    try {
      return jsonDecode('"${source.replaceAll('"', r'\"')}"');
    } catch (_) {
      return source;
    }
  }

  static DateTime? _parseDate(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text);
  }

  static bool _truthy(Object? value) {
    if (value == true) return true;
    final text = '${value ?? ''}'.trim().toLowerCase();
    return text == '1' ||
        text == 'true' ||
        text == 'yes' ||
        text == 'read' ||
        text == '已读';
  }

  static Map<String, dynamic>? _decodeAnyPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final text = raw.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
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
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String _newProtocolType(Map payload) {
    final msgType = '${payload['msg_type'] ?? ''}'.trim().toLowerCase();
    if (msgType.isNotEmpty) return msgType;
    final sdkType = int.tryParse('${payload['type'] ?? 0}') ?? 0;
    if (sdkType == 2 || sdkType == 3) return 'image';
    if (sdkType == 4) return 'voice';
    if (sdkType == 5) return 'video';
    if (sdkType == 8) return 'file';
    return 'text';
  }

  static String _formatCallDuration(dynamic value) {
    final total = int.tryParse('$value') ?? 0;
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }

  static String _formatVoiceDuration(dynamic value) {
    final total = int.tryParse('$value') ?? 1;
    final safe = total < 1 ? 1 : total;
    if (safe < 60) return '$safe"';
    final minutes = safe ~/ 60;
    final seconds = safe % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _mediaPreview(String label, Object? value) {
    final prefix = '[$label]';
    final text = _decodeEscapedText('$value').trim();
    if (text.isEmpty || text == 'null' || text == prefix) return prefix;
    if (text.startsWith(prefix)) {
      final rest = text.substring(prefix.length).trim();
      return rest.isEmpty ? prefix : '$prefix $rest';
    }
    return '$prefix $text';
  }

  static bool _isGifContent(Map<String, dynamic> content) {
    final format = '${content['media_format'] ?? content['format'] ?? ''}'
        .toLowerCase();
    if (format == 'gif') return true;
    if (_truthy(content['animated'] ?? content['is_gif'])) return true;
    return _looksLikeGif('${content['name'] ?? content['file_name'] ?? ''}') ||
        _looksLikeGif(
          '${content['url'] ?? content['file_url'] ?? content['image_path'] ?? content['file_path'] ?? content['path'] ?? content['src'] ?? ''}',
        );
  }

  static bool _looksLikeGif(String value) {
    final clean = value.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.gif');
  }
}

class ImGroup {
  final int id;
  final String groupNo;
  final String groupNoRule;
  final String name;
  final String avatar;
  final String notice;
  final String noticeRichText;
  final int memberCount;
  final int ownerId;
  final String myRole;
  final bool qrEnabled;
  final bool noticeEnabled;
  final bool adminNoticeEnabled;
  final bool noticePinned;
  final bool screenshotNotifyEnabled;
  final bool groupNoChangeEnabled;
  final bool groupNoChangePaid;
  final double groupNoChangeAmount;
  final Map<String, dynamic> raw;

  const ImGroup({
    required this.id,
    required this.groupNo,
    this.groupNoRule = 'alnum',
    required this.name,
    required this.avatar,
    this.notice = '',
    this.noticeRichText = '',
    required this.memberCount,
    this.ownerId = 0,
    this.myRole = 'member',
    this.qrEnabled = true,
    this.noticeEnabled = true,
    this.adminNoticeEnabled = true,
    this.noticePinned = true,
    this.screenshotNotifyEnabled = false,
    this.groupNoChangeEnabled = false,
    this.groupNoChangePaid = false,
    this.groupNoChangeAmount = 0,
    this.raw = const <String, dynamic>{},
  });

  bool get isOwner =>
      myRole == 'owner' || myRole == 'creator' || myRole == 'master';
  bool get isAdmin => isOwner || myRole == 'admin' || myRole == 'manager';

  ImGroup copyWith({
    String? groupNo,
    String? groupNoRule,
    String? name,
    String? avatar,
    String? notice,
    String? noticeRichText,
    int? memberCount,
    int? ownerId,
    String? myRole,
    bool? qrEnabled,
    bool? noticeEnabled,
    bool? adminNoticeEnabled,
    bool? noticePinned,
    bool? screenshotNotifyEnabled,
    bool? groupNoChangeEnabled,
    bool? groupNoChangePaid,
    double? groupNoChangeAmount,
    Map<String, dynamic>? raw,
  }) => ImGroup(
    id: id,
    groupNo: groupNo ?? this.groupNo,
    groupNoRule: groupNoRule ?? this.groupNoRule,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    notice: notice ?? this.notice,
    noticeRichText: noticeRichText ?? this.noticeRichText,
    memberCount: memberCount ?? this.memberCount,
    ownerId: ownerId ?? this.ownerId,
    myRole: myRole ?? this.myRole,
    qrEnabled: qrEnabled ?? this.qrEnabled,
    noticeEnabled: noticeEnabled ?? this.noticeEnabled,
    adminNoticeEnabled: adminNoticeEnabled ?? this.adminNoticeEnabled,
    noticePinned: noticePinned ?? this.noticePinned,
    screenshotNotifyEnabled:
        screenshotNotifyEnabled ?? this.screenshotNotifyEnabled,
    groupNoChangeEnabled: groupNoChangeEnabled ?? this.groupNoChangeEnabled,
    groupNoChangePaid: groupNoChangePaid ?? this.groupNoChangePaid,
    groupNoChangeAmount: groupNoChangeAmount ?? this.groupNoChangeAmount,
    raw: raw ?? this.raw,
  );

  factory ImGroup.fromJson(Map<String, dynamic> j) {
    final config = j['config'] is Map
        ? Map<String, dynamic>.from(j['config'])
        : const <String, dynamic>{};
    return ImGroup(
      id: int.tryParse('${j['id'] ?? j['group_id'] ?? 0}') ?? 0,
      groupNo: '${j['group_no'] ?? j['groupNo'] ?? ''}',
      groupNoRule:
          '${j['group_no_rule'] ?? config['group_no_rule'] ?? 'alnum'}',
      name: '${j['name'] ?? j['group_name'] ?? '群聊'}',
      avatar: '${j['avatar'] ?? j['group_avatar'] ?? ''}',
      notice: _firstText([
        j['notice'],
        j['announcement'],
        j['group_notice'],
        j['notice_text'],
        config['notice'],
      ]),
      noticeRichText: _firstText([
        j['notice_rich_text'],
        j['notice_rich'],
        j['notice_html'],
        j['notice_delta'],
        config['notice_rich_text'],
      ]),
      memberCount:
          int.tryParse('${j['member_count'] ?? j['members'] ?? 0}') ?? 0,
      ownerId:
          int.tryParse(
            '${j['owner_id'] ?? j['creator_id'] ?? j['master_id'] ?? 0}',
          ) ??
          0,
      myRole: '${j['my_role'] ?? j['role'] ?? j['member_role'] ?? 'member'}',
      qrEnabled: _flag([
        j['qr_enabled'],
        j['qrcode_enabled'],
        j['group_qr_enabled'],
        config['qr_enabled'],
      ], true),
      noticeEnabled: _flag([
        j['notice_enabled'],
        j['group_notice_enabled'],
        j['announcement_enabled'],
        config['notice_enabled'],
      ], true),
      adminNoticeEnabled: _flag([
        j['admin_notice_enabled'],
        j['admin_can_edit_notice'],
        config['admin_notice_enabled'],
      ], true),
      noticePinned: _flag([
        j['notice_pinned'],
        j['pin_notice'],
        config['notice_pinned'],
      ], true),
      screenshotNotifyEnabled: _flag([
        j['screenshot_notify_enabled'],
        j['screenshot_notice_enabled'],
        j['screen_capture_notice'],
        config['screenshot_notify_enabled'],
      ], false),
      groupNoChangeEnabled: _zeroMeansEnabled(
        [
          j['group_no_change_enabled'],
          j['group_no_change_switch'],
          j['group_no_edit_switch'],
          j['group_no_modify_switch'],
          config['group_no_change_enabled'],
          config['group_no_change_switch'],
          config['group_no_edit_switch'],
          config['group_no_modify_switch'],
        ],
        _flag([
          j['group_no_edit_enabled'],
          config['group_no_edit_enabled'],
        ], false),
      ),
      groupNoChangePaid: _zeroMeansEnabled(
        [
          j['group_no_change_paid'],
          j['group_no_paid_switch'],
          j['group_no_change_paid_switch'],
          config['group_no_change_paid'],
          config['group_no_paid_switch'],
          config['group_no_change_paid_switch'],
        ],
        _flag([
          j['group_no_paid_change'],
          config['group_no_paid_change'],
        ], false),
      ),
      groupNoChangeAmount: _double([
        j['group_no_change_amount'],
        j['group_no_change_price'],
        config['group_no_change_amount'],
      ]),
      raw: Map<String, dynamic>.from(j),
    );
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static bool _flag(Iterable<Object?> values, bool fallback) {
    for (final value in values) {
      if (value == null) continue;
      if (value is bool) return value;
      final text = '$value'.trim().toLowerCase();
      if (text.isEmpty || text == 'null') continue;
      if (text == '1' || text == 'true' || text == 'yes' || text == 'on') {
        return true;
      }
      if (text == '0' || text == 'false' || text == 'no' || text == 'off') {
        return false;
      }
    }
    return fallback;
  }

  static bool _zeroMeansEnabled(Iterable<Object?> values, bool fallback) {
    for (final value in values) {
      if (value == null) continue;
      if (value is bool) return value;
      final text = '$value'.trim().toLowerCase();
      if (text.isEmpty || text == 'null') continue;
      if (text == '0' || text == 'true' || text == 'yes' || text == 'on') {
        return true;
      }
      if (text == '1' || text == 'false' || text == 'no' || text == 'off') {
        return false;
      }
    }
    return fallback;
  }

  static double _double(Iterable<Object?> values) {
    for (final value in values) {
      final parsed = double.tryParse('${value ?? ''}');
      if (parsed != null) return parsed;
    }
    return 0;
  }
}

class ImGroupMember {
  final int userId;
  final String username;
  final String nickname;
  final String avatar;
  final String role;
  const ImGroupMember({
    required this.userId,
    this.username = '',
    required this.nickname,
    required this.avatar,
    this.role = 'member',
  });

  bool get isOwner => role == 'owner' || role == 'creator' || role == 'master';
  bool get isAdmin => isOwner || role == 'admin' || role == 'manager';

  factory ImGroupMember.fromJson(Map<String, dynamic> j) {
    final user = j['user'] is Map
        ? Map<String, dynamic>.from(j['user'])
        : const <String, dynamic>{};
    final id =
        int.tryParse(
          '${j['user_id'] ?? j['member_id'] ?? j['uid'] ?? user['id'] ?? user['userid'] ?? 0}',
        ) ??
        0;
    final nickname = UnifiedMessage._firstNonEmpty([
      j['nickname'],
      j['name'],
      user['nickname'],
      user['username'],
      '用户$id',
    ]);
    final username = UnifiedMessage._firstNonEmpty([
      j['username'],
      j['user_name'],
      user['username'],
    ]);
    final avatar = UnifiedMessage._firstNonEmpty([
      j['avatar'],
      j['usertx'],
      user['avatar'],
      user['usertx'],
    ]);
    return ImGroupMember(
      userId: id,
      username: username,
      nickname: nickname.isEmpty ? '用户$id' : nickname,
      avatar: avatar,
      role: '${j['role'] ?? j['group_role'] ?? j['member_role'] ?? 'member'}',
    );
  }
}

class ConversationItem {
  final int userId;
  final String username;
  final String nickname;
  final String avatar;
  final String preview;
  final String msgTime;
  final DateTime? msgDateTime;
  final int unread;
  final Map<String, dynamic> raw;

  const ConversationItem({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.preview,
    required this.msgTime,
    this.msgDateTime,
    required this.unread,
    this.raw = const <String, dynamic>{},
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
      preview: _conversationPreview(j, msg, payload, content, userId),
      msgTime: _str(
        j['msg_time'] ??
            j['create_time'] ??
            j['updated_at'] ??
            msg['create_time'] ??
            payload['create_time'] ??
            '',
      ),
      msgDateTime: _parseConversationDateTime(
        j['msg_time'] ??
            j['create_time'] ??
            j['updated_at'] ??
            msg['create_time'] ??
            payload['create_time'],
      ),
      unread: _toInt(
        j['unread_quantity'] ??
            j['unread_num'] ??
            j['unread_count'] ??
            j['unread'] ??
            j['badge'] ??
            j['red_dot'] ??
            0,
      ),
      raw: {...j, '_message': msg, '_payload': payload, '_content': content},
    );
  }

  static String _conversationPreview(
    Map<String, dynamic> j,
    Map<String, dynamic> msg,
    Map<String, dynamic> payload,
    Map<String, dynamic> content,
    int peerUserId,
  ) {
    final msgType = _str(payload['msg_type'] ?? msg['msg_type']);
    if (msgType == 'call') {
      return '';
    }
    final recalled =
        msgType == 'recall' ||
        UnifiedMessage._truthy(
          msg['is_recalled'] ?? j['is_recalled'] ?? payload['is_recalled'],
        );
    if (recalled) {
      final text = _str(content['text'] ?? payload['text'] ?? msg['content']);
      if (text.isNotEmpty && text != '[消息已撤回]' && text != '消息已撤回') {
        return text;
      }
      final fromUserId = _toInt(
        payload['from_user_id'] ?? msg['sender_id'] ?? msg['from_user_id'],
      );
      if (fromUserId > 0 && peerUserId > 0 && fromUserId != peerUserId) {
        return '你撤回了一条消息';
      }
      return '对方撤回了一条消息';
    }
    if (msgType == 'call_record') {
      final parsed = content;
      final media = _str(parsed['media']).contains('video') ? '视频' : '语音';
      final status = _str(parsed['status']);
      if (status == 'finished') {
        return '[$media通话] ${UnifiedMessage._formatCallDuration(parsed['duration'])}';
      }
      if (status == 'busy') return '[$media通话] 对方忙线';
      if (status == 'missed') return '[$media通话] 未接听';
      if (status == 'rejected') return '[$media通话] 已拒绝';
      if (status == 'failed') return '[$media通话] 连接失败';
      return '[$media通话] 已取消';
    }
    if (msgType == 'group_call_invite') {
      final media = _str(content['media']).contains('video') ? '视频' : '语音';
      final name = _str(content['starter_nickname'] ?? content['nickname']);
      return '[群$media通话] ${name.isEmpty ? '群成员' : name} 发起了群通话';
    }
    if (msgType == 'group_call_record') {
      final media = _str(content['media']).contains('video') ? '视频' : '语音';
      final status = _str(content['status']);
      if (status == 'finished') {
        return '[群$media通话] ${UnifiedMessage._formatCallDuration(content['duration'])}';
      }
      if (status == 'busy') return '[群$media通话] 忙线';
      if (status == 'missed') return '[群$media通话] 未接听';
      if (status == 'rejected') return '[群$media通话] 已拒绝';
      if (status == 'failed') return '[群$media通话] 连接失败';
      return '[群$media通话] 已取消';
    }
    if (msgType == 'group_call_join' || msgType == 'group_call_leave') {
      return '';
    }
    if (msgType == 'image') {
      return UnifiedMessage._mediaPreview(
        UnifiedMessage._isGifContent(content) ? 'GIF' : '图片',
        content['text'] ?? msg['content'],
      );
    }
    if (msgType == 'voice') {
      return '[语音] ${UnifiedMessage._formatVoiceDuration(content['duration'])}';
    }
    if (msgType == 'transfer') {
      return '[转账] ${_str(content['amount'] ?? content['money'] ?? msg['money'])}'
          .trim();
    }
    if (msgType == 'red_packet') {
      final greeting = _str(
        content['greeting'] ?? content['text'] ?? msg['content'],
      ).replaceFirst('[红包]', '').trim();
      return greeting.isEmpty ? '[红包]' : '[红包] $greeting';
    }
    if (msgType == 'transfer_receipt') {
      return _str(content['text'] ?? msg['content'] ?? '[转账回执]');
    }
    if (msgType == 'red_packet_receipt') {
      return _str(content['text'] ?? msg['content'] ?? '[红包回执]');
    }
    if (msgType == 'emoji') {
      final emoji = UnifiedMessage._decodeEscapedText(
        _str(content['emoji'] ?? content['text'] ?? msg['content']),
      );
      return emoji.isEmpty ? '[消息]' : emoji;
    }
    if (msgType == 'file') {
      return UnifiedMessage._mediaPreview(
        '文件',
        content['name'] ?? msg['file_name'],
      );
    }
    if (msgType == 'video') {
      return UnifiedMessage._mediaPreview(
        '视频',
        content['name'] ?? msg['file_name'] ?? msg['content'],
      );
    }
    final text = UnifiedMessage._decodeEscapedText(
      _str(
        content['text'] ??
            content['content'] ??
            payload['content'] ??
            msg['content'] ??
            j['content'] ??
            j['preview'],
      ),
    );
    if (text == '[通话信令]') return '';
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
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
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

DateTime? _parseConversationDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  final timestamp = int.tryParse(text);
  if (timestamp != null) {
    if (timestamp > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    if (timestamp > 0) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }
  }
  final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
  return DateTime.tryParse(normalized);
}

import 'dart:convert';

/// Blinlin 通话结构化信令 v2。
///
/// 目标：
/// - 废弃纯 cmd 字符串作为业务主协议。
/// - 所有客户端业务层只处理结构化 JSON。
/// - 兼容旧后端/悟空 IM 返回的 call_invite、call_action、payload 字符串等旧格式，
///   但归一化后必须是合法 CallSignal。
class CallSignal {
  static const schema = 'blinlin.call.signal.v2';
  static const msgType = 'call_signal';
  static const legacyMsgType = 'call';
  static const allowedActions = <String>{
    'invite',
    'offer',
    'accept',
    'answer',
    'ice',
    'hangup',
    'reject',
    'cancel',
    'timeout',
    'busy',
    'ack',
  };

  final String callId;
  final String signalId;
  final String action;
  final String media;
  final int fromUserId;
  final int toUserId;
  final String fromUid;
  final String toUid;
  final String deviceId;
  final int seq;
  final int timestamp;
  final Map<String, dynamic> content;
  final Map<String, dynamic> raw;

  const CallSignal({
    required this.callId,
    required this.signalId,
    required this.action,
    required this.media,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUid,
    required this.toUid,
    required this.deviceId,
    required this.seq,
    required this.timestamp,
    required this.content,
    required this.raw,
  });

  bool get isValid =>
      callId.isNotEmpty &&
      signalId.isNotEmpty &&
      allowedActions.contains(action) &&
      (media == 'audio' || media == 'video') &&
      fromUserId > 0 &&
      toUserId > 0 &&
      fromUserId != toUserId;

  bool get isInviteLike => action == 'invite' || action == 'offer';
  bool get isTerminal =>
      action == 'hangup' ||
      action == 'reject' ||
      action == 'cancel' ||
      action == 'timeout' ||
      action == 'busy';

  Map<String, dynamic> toPayload() {
    final normalizedContent = <String, dynamic>{
      ...content,
      'call_id': callId,
      'signal_id': signalId,
      'action': action,
      'type': 'call_$action',
      'media': media,
      'silent': action != 'invite',
      'visible': action == 'invite',
      if (deviceId.isNotEmpty) 'from_device_id': deviceId,
    };
    return {
      'schema': schema,
      'msg_type': legacyMsgType,
      'signal_type': msgType,
      'client_msg_no': signalId,
      'call_id': callId,
      'signal_id': signalId,
      'action': action,
      'type': 'call_$action',
      'media': media,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'from_uid': fromUid,
      'to_uid': toUid,
      if (deviceId.isNotEmpty) 'from_device_id': deviceId,
      'seq': seq,
      'timestamp': timestamp,
      'content': normalizedContent,
      'create_time': DateTime.fromMillisecondsSinceEpoch(
        timestamp,
      ).toIso8601String(),
    };
  }

  static CallSignal? tryParse(dynamic input) {
    final root = _decodeMap(input);
    if (root == null) return null;

    final rowPayload =
        _decodeMap(root['payload']) ??
        _decodeMap(root['im_payload']) ??
        _decodeMap(root['data']) ??
        root;
    final payload = Map<String, dynamic>.from(rowPayload);
    final content = _decodeMap(payload['content']) ?? <String, dynamic>{};

    final action = normalizeAction(
      content['action'] ??
          content['type'] ??
          payload['action'] ??
          payload['type'] ??
          payload['call_action'] ??
          payload['signal_action'] ??
          root['action'] ??
          root['type'] ??
          root['call_action'] ??
          root['signal_action'] ??
          root['cmd'] ??
          '',
    );
    final callId = _text(
      content['call_id'] ??
          payload['call_id'] ??
          root['call_id'] ??
          content['callId'] ??
          payload['callId'],
    );
    final signalId = _text(
      content['signal_id'] ??
          payload['signal_id'] ??
          payload['client_msg_no'] ??
          payload['client_no'] ??
          root['signal_id'] ??
          root['client_msg_no'] ??
          root['id'],
    );
    final mediaRaw = _text(
      content['media'] ?? payload['media'] ?? root['media'],
    ).toLowerCase();
    final media = mediaRaw.contains('video') ? 'video' : 'audio';
    final fromUserId = _int(
      payload['from_user_id'] ??
          content['from_user_id'] ??
          root['from_user_id'] ??
          payload['sender_id'],
    );
    final toUserId = _int(
      payload['to_user_id'] ??
          content['to_user_id'] ??
          root['to_user_id'] ??
          payload['receiver_id'],
    );
    final fromUid = _text(
      payload['from_uid'] ??
          payload['fromUID'] ??
          root['from_uid'] ??
          root['fromUID'] ??
          content['from_uid'],
    );
    final toUid = _text(
      payload['to_uid'] ??
          payload['toUID'] ??
          root['to_uid'] ??
          root['toUID'] ??
          payload['channel_id'] ??
          root['channel_id'] ??
          content['to_uid'],
    );
    final normalizedFromUserId = fromUserId > 0
        ? fromUserId
        : _userIdFromUid(fromUid);
    final normalizedToUserId = toUserId > 0 ? toUserId : _userIdFromUid(toUid);
    final deviceId = _text(
      content['from_device_id'] ??
          payload['from_device_id'] ??
          root['from_device_id'],
    );
    final seq = _int(content['seq'] ?? payload['seq'] ?? root['seq']);
    final timestamp = _timestamp(
      payload['timestamp'] ??
          root['timestamp'] ??
          payload['create_time'] ??
          root['create_time'],
    );

    final normalizedContent = <String, dynamic>{
      ...content,
      if (payload['description'] != null) 'description': payload['description'],
      if (root['description'] != null) 'description': root['description'],
      if (payload['candidate'] != null) 'candidate': payload['candidate'],
      if (root['candidate'] != null) 'candidate': root['candidate'],
      if (callId.isNotEmpty) 'call_id': callId,
      if (signalId.isNotEmpty) 'signal_id': signalId,
      if (action.isNotEmpty) 'action': action,
      if (action.isNotEmpty) 'type': 'call_$action',
      'media': media,
      'silent': action != 'invite',
      'visible': action == 'invite',
      if (normalizedFromUserId > 0) 'from_user_id': normalizedFromUserId,
      if (normalizedToUserId > 0) 'to_user_id': normalizedToUserId,
      if (deviceId.isNotEmpty) 'from_device_id': deviceId,
    };

    final signal = CallSignal(
      callId: callId,
      signalId: signalId.isNotEmpty ? signalId : '${callId}_${seq}_$action',
      action: action,
      media: media,
      fromUserId: normalizedFromUserId,
      toUserId: normalizedToUserId,
      fromUid: fromUid,
      toUid: toUid,
      deviceId: deviceId,
      seq: seq,
      timestamp: timestamp,
      content: normalizedContent,
      raw: root,
    );
    return signal.isValid ||
            (signal.callId.isNotEmpty && signal.action.isNotEmpty)
        ? signal
        : null;
  }

  static String normalizeAction(dynamic value) {
    var raw = _text(value).trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw == 'call') return '';
    if (raw.startsWith('call_')) raw = raw.substring(5);
    if (raw == 'end') return 'hangup';
    if (raw == 'finish') return 'hangup';
    if (raw == 'refuse') return 'reject';
    if (raw == 'occupied') return 'busy';
    if (raw == 'line_busy') return 'busy';
    if (allowedActions.contains(raw)) return raw;
    return raw;
  }

  static Map<String, dynamic>? _decodeMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      final text = value.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>)
          return Map<String, dynamic>.from(decoded);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      try {
        var padded = text
            .replaceAll(RegExp(r'\s+'), '')
            .replaceAll('-', '+')
            .replaceAll('_', '/');
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

  static String _text(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text == 'null') return '';
    return text;
  }

  static int _int(dynamic value) => int.tryParse(_text(value)) ?? 0;

  static int _userIdFromUid(String uid) {
    if (uid.contains('_')) return int.tryParse(uid.split('_').last) ?? 0;
    return int.tryParse(uid) ?? 0;
  }

  static int _timestamp(dynamic value) {
    final text = _text(value);
    final raw = int.tryParse(text);
    if (raw != null && raw > 0) return raw > 9999999999 ? raw : raw * 1000;
    final dt = DateTime.tryParse(text);
    return (dt ?? DateTime.now()).millisecondsSinceEpoch;
  }
}

enum CallFlowState {
  idle,
  outgoingCalling,
  offerSent,
  incomingRinging,
  offerReceived,
  answerSent,
  connectingMedia,
  connected,
  ending,
  ended,
  rejected,
  failed,
}

class CallStateMachine {
  CallFlowState state;
  CallStateMachine(this.state);

  bool get ended =>
      state == CallFlowState.ended ||
      state == CallFlowState.rejected ||
      state == CallFlowState.failed;

  bool canSend(String action) {
    action = CallSignal.normalizeAction(action);
    if (action == 'ack') return true;
    if (ended) return false;
    switch (state) {
      case CallFlowState.idle:
        return action == 'invite' ||
            action == 'offer' ||
            action == 'ice' ||
            action == 'cancel' ||
            action == 'busy' ||
            action == 'reject';
      case CallFlowState.outgoingCalling:
        return action == 'offer' ||
            action == 'hangup' ||
            action == 'cancel' ||
            action == 'ice';
      case CallFlowState.offerSent:
        return action == 'ice' || action == 'hangup' || action == 'cancel' || action == 'busy';
      case CallFlowState.incomingRinging:
      case CallFlowState.offerReceived:
        return action == 'accept' ||
            action == 'answer' ||
            action == 'reject' ||
            action == 'ice';
      case CallFlowState.answerSent:
        return action == 'answer' || action == 'ice' || action == 'hangup';
      case CallFlowState.connectingMedia:
      case CallFlowState.connected:
        return action == 'ice' || action == 'hangup';
      case CallFlowState.ending:
        return false;
      case CallFlowState.ended:
      case CallFlowState.rejected:
      case CallFlowState.failed:
        return false;
    }
  }

  bool canReceive(String action) {
    action = CallSignal.normalizeAction(action);
    if (action == 'ack') return true;
    if (ended) return false;
    switch (state) {
      case CallFlowState.idle:
        return action == 'invite' || action == 'offer';
      case CallFlowState.outgoingCalling:
      case CallFlowState.offerSent:
        return action == 'accept' ||
            action == 'answer' ||
            action == 'ice' ||
            action == 'reject' ||
            action == 'busy' ||
            action == 'hangup';
      case CallFlowState.incomingRinging:
        return action == 'offer' ||
            action == 'ice' ||
            action == 'hangup' ||
            action == 'cancel';
      case CallFlowState.offerReceived:
      case CallFlowState.answerSent:
      case CallFlowState.connectingMedia:
      case CallFlowState.connected:
        return action == 'ice' ||
            action == 'hangup' ||
            action == 'reject' ||
            action == 'busy' ||
            action == 'cancel';
      case CallFlowState.ending:
        return action == 'ack';
      case CallFlowState.ended:
      case CallFlowState.rejected:
      case CallFlowState.failed:
        return false;
    }
  }

  void markSent(String action) {
    action = CallSignal.normalizeAction(action);
    switch (action) {
      case 'invite':
        if (state == CallFlowState.idle) state = CallFlowState.outgoingCalling;
        break;
      case 'offer':
        if (state == CallFlowState.outgoingCalling ||
            state == CallFlowState.idle) {
          state = CallFlowState.offerSent;
        }
        break;
      case 'accept':
      case 'answer':
        if (state == CallFlowState.incomingRinging ||
            state == CallFlowState.offerReceived) {
          state = CallFlowState.answerSent;
        }
        break;
      case 'hangup':
      case 'cancel':
        state = CallFlowState.ending;
        break;
      case 'reject':
      case 'busy':
        state = CallFlowState.rejected;
        break;
    }
  }

  void markReceived(String action) {
    action = CallSignal.normalizeAction(action);
    switch (action) {
      case 'invite':
        if (state == CallFlowState.idle) state = CallFlowState.incomingRinging;
        break;
      case 'offer':
        if (state == CallFlowState.idle ||
            state == CallFlowState.incomingRinging) {
          state = CallFlowState.offerReceived;
        }
        break;
      case 'accept':
      case 'answer':
        if (state == CallFlowState.outgoingCalling ||
            state == CallFlowState.offerSent) {
          state = CallFlowState.connectingMedia;
        }
        break;
      case 'hangup':
      case 'cancel':
        state = CallFlowState.ended;
        break;
      case 'reject':
      case 'busy':
        state = CallFlowState.rejected;
        break;
    }
  }

  void markConnected() => state = CallFlowState.connected;
  void markEnded() => state = CallFlowState.ended;
  void markFailed() => state = CallFlowState.failed;
}

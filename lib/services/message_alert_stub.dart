import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import '../models/im_models.dart';

class MessageAlertService {
  static const _channel = MethodChannel('blinlin.com/message_alerts');

  Future<void> prepare() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('prepare');
    } catch (_) {}
  }

  Future<void> startKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startKeepAlive');
    } catch (_) {}
  }

  Future<void> stopKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopKeepAlive');
    } catch (_) {}
  }

  Future<void> notifyMessage(UnifiedMessage message) async {
    if (message.isMe) return;
    final title = _senderName(message);
    final body = _safePreview(message.preview);
    final payload = _messagePayload(message);
    await notifyPlain(
      id: message.messageId == 0
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : message.messageId,
      title: title,
      body: body.isEmpty ? '收到一条新消息' : body,
      payload: payload,
    );
  }

  Future<void> notifyPlain({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('notifyMessage', {
        'id': id,
        'title': title,
        'body': body,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });
    } catch (_) {}
  }

  Future<void> notifyCall({
    required String title,
    required String body,
    int? id,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('notifyCall', {
        'id': id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'title': title,
        'body': body,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });
    } catch (_) {}
  }

  Future<String?> getLaunchPayload() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchPayload');
    } catch (_) {
      return null;
    }
  }

  String _senderName(UnifiedMessage message) {
    final groupName =
        message.raw['group_name'] ??
        message.raw['groupName'] ??
        message.raw['group_no'] ??
        message.raw['group_id'];
    final groupText = '$groupName'.trim();
    if (groupText.isNotEmpty && groupText != 'null' && groupText != '0') {
      return '群聊 $groupText';
    }
    final name =
        message.raw['from_name'] ??
        message.raw['nickname'] ??
        message.raw['fromUser']?['nickname'] ??
        message.raw['legacy']?['fromUser']?['nickname'];
    final text = '$name'.trim();
    if (text.isNotEmpty && text != 'null') return text;
    return '搭个话消息';
  }

  String _messagePayload(UnifiedMessage message) {
    final groupId = _intValue(
      message.raw['group_id'] ?? message.content['group_id'],
    );
    final groupNo = _textValue(
      message.raw['group_no'] ??
          message.raw['groupNo'] ??
          message.content['group_no'],
    );
    final peerId = groupId > 0
        ? 0
        : (message.fromUserId > 0 ? message.fromUserId : message.toUserId);
    final data = <String, dynamic>{
      'type': 'message',
      'conversation': groupId > 0 ? 'group' : 'peer',
      'message_id': message.messageId,
      if (peerId > 0) 'peer_id': peerId,
      if (peerId > 0) 'peer_name': _peerName(message),
      if (peerId > 0) 'peer_avatar': _peerAvatar(message),
      if (groupId > 0) 'group_id': groupId,
      if (groupNo.isNotEmpty) 'group_no': groupNo,
      if (groupId > 0) 'group_name': _groupName(message),
      'payload': message.raw,
    };
    try {
      return jsonEncode(data);
    } catch (_) {
      data.remove('payload');
      return jsonEncode(data);
    }
  }

  String _peerName(UnifiedMessage message) {
    final name =
        message.raw['from_name'] ??
        message.raw['nickname'] ??
        message.content['nickname'] ??
        message.raw['fromUser']?['nickname'] ??
        message.raw['legacy']?['fromUser']?['nickname'];
    final text = '$name'.trim();
    return text.isNotEmpty && text != 'null' ? text : '用户${message.fromUserId}';
  }

  String _peerAvatar(UnifiedMessage message) {
    final avatar =
        message.raw['from_avatar'] ??
        message.raw['avatar'] ??
        message.content['avatar'] ??
        message.raw['fromUser']?['avatar'] ??
        message.raw['fromUser']?['usertx'] ??
        message.raw['legacy']?['fromUser']?['avatar'];
    final text = '$avatar'.trim();
    return text == 'null' ? '' : text;
  }

  String _groupName(UnifiedMessage message) {
    final name =
        message.raw['group_name'] ??
        message.raw['groupName'] ??
        message.content['group_name'] ??
        message.content['groupName'];
    final text = '$name'.trim();
    if (text.isNotEmpty && text != 'null' && text != '0') return text;
    final groupNo = _textValue(
      message.raw['group_no'] ??
          message.raw['groupNo'] ??
          message.content['group_no'],
    );
    return groupNo.isNotEmpty ? groupNo : '群聊';
  }

  int _intValue(Object? value) => int.tryParse('${value ?? ''}') ?? 0;

  String _textValue(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text == 'null' ? '' : text;
  }

  String _safePreview(String text) {
    final value = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.length <= 80) return value;
    return '${value.substring(0, 80)}...';
  }
}

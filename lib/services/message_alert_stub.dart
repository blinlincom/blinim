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
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('notifyMessage', {
        'id': message.messageId == 0
            ? DateTime.now().millisecondsSinceEpoch ~/ 1000
            : message.messageId,
        'title': title,
        'body': body.isEmpty ? '收到一条新消息' : body,
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
      await _channel.invokeMethod('notifyMessage', {
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

  String _safePreview(String text) {
    final value = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.length <= 80) return value;
    return '${value.substring(0, 80)}...';
  }
}

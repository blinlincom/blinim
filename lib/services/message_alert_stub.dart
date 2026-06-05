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

  String _senderName(UnifiedMessage message) {
    final name = message.raw['from_name'] ??
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

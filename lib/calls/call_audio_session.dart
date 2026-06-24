import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_logger.dart';

class CallAudioSession {
  CallAudioSession._();

  static const MethodChannel _channel = MethodChannel('blinlin.com/call_audio');

  static Future<void> release() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('release');
    } on MissingPluginException {
      return;
    } catch (e) {
      AppLogger.warn('CALL', '音频会话释放失败', data: e);
    }
  }
}

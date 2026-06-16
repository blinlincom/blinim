import 'dart:async';
import 'package:flutter/services.dart';

class ScreenshotMonitor {
  static const MethodChannel _channel = MethodChannel(
    'blinlin.com/screenshot_monitor',
  );

  static final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  static bool _prepared = false;

  static Stream<DateTime> get events => _controller.stream;

  static void addLocalEvent() {
    if (!_controller.isClosed) {
      _controller.add(DateTime.now());
    }
  }

  static Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        _controller.add(DateTime.now());
      }
    });
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      // Some platforms cannot expose screenshot events. Keep the stream silent.
    }
  }
}

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 全局轻量日志。
///
/// 设计目标：
/// - 不依赖第三方库，不影响主流程。
/// - 控制台、内存、可选文件三路输出。
/// - 重点服务通话/IM/后端排障：用户反馈异常时可以直接复制日志。
class AppLogger {
  AppLogger._();

  static const int _maxLines = 1000;
  static const MethodChannel _diagnosticsChannel = MethodChannel('blinlin.com/diagnostics');
  static final Queue<String> _lines = Queue<String>();
  static final StreamController<String> _controller = StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static List<String> recent({int limit = 300}) {
    if (limit <= 0) return const <String>[];
    final list = _lines.toList(growable: false);
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }

  static String dump({int limit = 500}) => recent(limit: limit).join('\n');

  static void info(String tag, String message, {Object? data}) {
    _write('I', tag, message, data: data);
  }

  static void warn(String tag, String message, {Object? data}) {
    _write('W', tag, message, data: data);
  }

  static void error(String tag, String message, {Object? error, StackTrace? stack, Object? data}) {
    _write('E', tag, message, data: data ?? error);
    if (stack != null) _write('E', tag, stack.toString());
  }

  static void call(String message, {Object? data}) => info('CALL', message, data: data);
  static void im(String message, {Object? data}) => info('IM', message, data: data);
  static void api(String message, {Object? data}) => info('API', message, data: data);

  static void _write(String level, String tag, String message, {Object? data}) {
    final ts = DateTime.now().toIso8601String();
    final suffix = data == null ? '' : ' | $data';
    final line = '$ts [$level][$tag] $message$suffix';
    _lines.add(line);
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    if (!_controller.isClosed) _controller.add(line);
    debugPrint(line);
    _appendToFile(line);
  }

  static void _appendToFile(String line) {
    if (kIsWeb) return;
    unawaited(
      _diagnosticsChannel
          .invokeMethod<bool>('appendLog', {'line': line})
          .then<void>((_) {})
          .catchError((_) {}),
    );
  }
}

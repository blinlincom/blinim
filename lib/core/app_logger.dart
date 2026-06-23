import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局轻量日志。
///
/// 设计目标：
/// - 不依赖第三方库，不影响主流程。
/// - 控制台、内存、可选文件三路输出。
/// - 重点服务通话/IM/后端排障：用户反馈异常时可以直接复制日志。
class AppLogger {
  AppLogger._();

  static const int _maxLines = 1000;
  static const MethodChannel _diagnosticsChannel = MethodChannel(
    'blinlin.com/diagnostics',
  );
  static final Queue<String> _lines = Queue<String>();
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();
  static const String _storedLinesKey = 'blinlin_global_error_log_lines';
  static const int _maxStoredLines = 500;
  static bool _initialized = false;
  static String? _logPath;
  static SharedPreferences? _prefs;
  static List<String> _storedLines = <String>[];

  static Stream<String> get stream => _controller.stream;
  static String? get logPath => _logPath;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _storedLines = _prefs?.getStringList(_storedLinesKey) ?? <String>[];
      for (final line in _storedLines.take(_maxLines)) {
        _lines.add(line);
      }
    } catch (_) {
      _prefs = null;
      _storedLines = <String>[];
    }
    await _readLogPath();
    info(
      'APP',
      '日志系统已启动',
      data: kIsWeb ? 'web memory log' : (_logPath ?? 'native log path pending'),
    );
  }

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

  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Object? data,
  }) {
    _write('E', tag, message, data: _mergeErrorData(error, data));
    if (stack != null) _write('E', tag, stack.toString());
  }

  static void exception(
    String tag,
    Object error,
    StackTrace stack, {
    String context = '',
  }) {
    final prefix = context.trim().isEmpty ? '未捕获异常' : context.trim();
    AppLogger.error(tag, prefix, error: error, stack: stack);
  }

  static void call(String message, {Object? data}) =>
      info('CALL', message, data: data);
  static void im(String message, {Object? data}) =>
      info('IM', message, data: data);
  static void api(String message, {Object? data}) =>
      info('API', message, data: data);

  static Object? _mergeErrorData(Object? error, Object? data) {
    if (error == null) return data;
    if (data == null) return error;
    return {'error': '$error', 'data': data};
  }

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
    _appendToLocalStore(line);
  }

  static Future<String?> refreshLogPath() => _readLogPath();

  static Future<String?> _readLogPath() async {
    if (kIsWeb) {
      _logPath = null;
      return null;
    }
    try {
      final path = await _diagnosticsChannel.invokeMethod<String>('getLogPath');
      if (path != null && path.trim().isNotEmpty) {
        _logPath = path.trim();
      }
      return _logPath;
    } catch (_) {
      return _logPath;
    }
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

  static void _appendToLocalStore(String line) {
    final prefs = _prefs;
    if (prefs == null) return;
    _storedLines.add(line);
    if (_storedLines.length > _maxStoredLines) {
      _storedLines = _storedLines.sublist(
        _storedLines.length - _maxStoredLines,
      );
    }
    unawaited(prefs.setStringList(_storedLinesKey, _storedLines));
  }
}

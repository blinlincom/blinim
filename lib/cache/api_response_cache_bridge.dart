import 'dart:async';

typedef ApiResponseCacheReader =
    Future<Map<String, dynamic>?> Function({
      required String namespace,
      required String cacheKey,
    });

typedef ApiResponseCacheWriter =
    Future<void> Function({
      required String namespace,
      required String cacheKey,
      required String path,
      required Map<String, dynamic> response,
      Duration? ttl,
    });

class ApiResponseCacheBridge {
  ApiResponseCacheBridge._();

  static ApiResponseCacheReader? _reader;
  static ApiResponseCacheWriter? _writer;

  static void configure({
    required ApiResponseCacheReader reader,
    required ApiResponseCacheWriter writer,
  }) {
    _reader = reader;
    _writer = writer;
  }

  static void reset() {
    _reader = null;
    _writer = null;
  }

  static Future<Map<String, dynamic>?> read({
    required String namespace,
    required String cacheKey,
  }) {
    final reader = _reader;
    if (reader == null) return Future<Map<String, dynamic>?>.value();
    return reader(namespace: namespace, cacheKey: cacheKey);
  }

  static Future<void> write({
    required String namespace,
    required String cacheKey,
    required String path,
    required Map<String, dynamic> response,
    Duration? ttl,
  }) {
    final writer = _writer;
    if (writer == null) return Future<void>.value();
    return writer(
      namespace: namespace,
      cacheKey: cacheKey,
      path: path,
      response: response,
      ttl: ttl,
    );
  }
}

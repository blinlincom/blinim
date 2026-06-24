import 'dart:async';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class AuthExpiredException extends ApiException {
  AuthExpiredException(super.message);
}

class RuntimeKeyDecodeException extends ApiException {
  RuntimeKeyDecodeException(super.message);
}

class AuthSessionEvents {
  static final _controller = StreamController<void>.broadcast();
  static bool _notified = false;

  static Stream<void> get expired => _controller.stream;

  static void notifyExpired() {
    if (_notified) return;
    _notified = true;
    if (!_controller.isClosed) _controller.add(null);
  }

  static void reset() {
    _notified = false;
  }
}

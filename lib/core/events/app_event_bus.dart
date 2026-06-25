import 'package:rxdart/rxdart.dart';

abstract class AppEvent {
  final String source;
  final DateTime time;

  AppEvent({required this.source, DateTime? time})
    : time = time ?? DateTime.now();
}

class ApiCacheUpdatedEvent extends AppEvent {
  final String path;
  final String requestKey;

  ApiCacheUpdatedEvent({
    required this.path,
    required this.requestKey,
    super.source = 'api',
  });
}

class EntityCacheUpdatedEvent extends AppEvent {
  final String scope;
  final String key;

  EntityCacheUpdatedEvent({
    required this.scope,
    required this.key,
    super.source = 'cache',
  });
}

class ImMessageCachedEvent extends AppEvent {
  final String conversationKey;
  final String messageKey;

  ImMessageCachedEvent({
    required this.conversationKey,
    required this.messageKey,
    super.source = 'im',
  });
}

class ImConnectionChangedEvent extends AppEvent {
  final bool connected;
  final bool connecting;
  final String error;

  ImConnectionChangedEvent({
    required this.connected,
    required this.connecting,
    this.error = '',
    super.source = 'im',
  });
}

class AppEventBus {
  AppEventBus._();

  static final PublishSubject<AppEvent> _events = PublishSubject<AppEvent>();

  static Stream<AppEvent> get stream => _events.stream;

  static void emit(AppEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Future<void> dispose() async {
    await _events.close();
  }
}

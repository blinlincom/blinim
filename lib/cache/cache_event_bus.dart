import 'package:rxdart/rxdart.dart';

sealed class CacheEvent {
  final DateTime time;
  const CacheEvent({required this.time});
}

class CacheReadyEvent extends CacheEvent {
  const CacheReadyEvent({required super.time});
}

class CacheFailureEvent extends CacheEvent {
  final Object error;
  final StackTrace stackTrace;
  const CacheFailureEvent({
    required super.time,
    required this.error,
    required this.stackTrace,
  });
}

class ConversationCacheChangedEvent extends CacheEvent {
  final int ownerId;
  const ConversationCacheChangedEvent({
    required super.time,
    required this.ownerId,
  });
}

class MessageCacheChangedEvent extends CacheEvent {
  final int ownerId;
  final String conversationKey;
  const MessageCacheChangedEvent({
    required super.time,
    required this.ownerId,
    required this.conversationKey,
  });
}

class ProfileCacheChangedEvent extends CacheEvent {
  final int ownerId;
  const ProfileCacheChangedEvent({required super.time, required this.ownerId});
}

class GroupCacheChangedEvent extends CacheEvent {
  final int ownerId;
  const GroupCacheChangedEvent({required super.time, required this.ownerId});
}

class UserCacheClearedEvent extends CacheEvent {
  final int ownerId;
  const UserCacheClearedEvent({required super.time, required this.ownerId});
}

class CacheEventBus {
  final _subject = PublishSubject<CacheEvent>();

  Stream<CacheEvent> get stream => _subject.stream;

  Stream<T> on<T extends CacheEvent>() => _subject.whereType<T>();

  void emit(CacheEvent event) {
    if (!_subject.isClosed) _subject.add(event);
  }

  void emitFailure(Object error, StackTrace stackTrace) {
    emit(
      CacheFailureEvent(
        time: DateTime.now(),
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<void> close() => _subject.close();
}

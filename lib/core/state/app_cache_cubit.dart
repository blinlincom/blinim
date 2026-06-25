import 'dart:async';

import 'package:bloc/bloc.dart';

import '../cache/app_cache_store.dart';
import '../events/app_event_bus.dart';

class AppCacheState {
  final bool initialized;
  final int apiWrites;
  final int entityWrites;
  final int imMessageWrites;
  final bool imConnected;
  final bool imConnecting;
  final String imError;
  final AppEvent? lastEvent;

  const AppCacheState({
    required this.initialized,
    this.apiWrites = 0,
    this.entityWrites = 0,
    this.imMessageWrites = 0,
    this.imConnected = false,
    this.imConnecting = false,
    this.imError = '',
    this.lastEvent,
  });

  const AppCacheState.initial() : this(initialized: false);

  AppCacheState copyWith({
    bool? initialized,
    int? apiWrites,
    int? entityWrites,
    int? imMessageWrites,
    bool? imConnected,
    bool? imConnecting,
    String? imError,
    AppEvent? lastEvent,
  }) => AppCacheState(
    initialized: initialized ?? this.initialized,
    apiWrites: apiWrites ?? this.apiWrites,
    entityWrites: entityWrites ?? this.entityWrites,
    imMessageWrites: imMessageWrites ?? this.imMessageWrites,
    imConnected: imConnected ?? this.imConnected,
    imConnecting: imConnecting ?? this.imConnecting,
    imError: imError ?? this.imError,
    lastEvent: lastEvent ?? this.lastEvent,
  );
}

class AppCacheCubit extends Cubit<AppCacheState> {
  final AppCacheStore store;
  StreamSubscription<AppEvent>? _eventsSub;

  AppCacheCubit(this.store) : super(const AppCacheState.initial());

  Future<void> start() async {
    await store.initialize();
    if (isClosed) return;
    emit(state.copyWith(initialized: true));
    _eventsSub ??= AppEventBus.stream.listen(_handleEvent);
  }

  void _handleEvent(AppEvent event) {
    if (event is ApiCacheUpdatedEvent) {
      emit(state.copyWith(apiWrites: state.apiWrites + 1, lastEvent: event));
      return;
    }
    if (event is EntityCacheUpdatedEvent) {
      emit(
        state.copyWith(entityWrites: state.entityWrites + 1, lastEvent: event),
      );
      return;
    }
    if (event is ImMessageCachedEvent) {
      emit(
        state.copyWith(
          imMessageWrites: state.imMessageWrites + 1,
          lastEvent: event,
        ),
      );
      return;
    }
    if (event is ImConnectionChangedEvent) {
      emit(
        state.copyWith(
          imConnected: event.connected,
          imConnecting: event.connecting,
          imError: event.error,
          lastEvent: event,
        ),
      );
      return;
    }
    emit(state.copyWith(lastEvent: event));
  }

  @override
  Future<void> close() async {
    await _eventsSub?.cancel();
    return super.close();
  }
}

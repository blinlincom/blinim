import 'dart:async';

import 'package:bloc/bloc.dart';

import 'cache_event_bus.dart';
import 'cache_repository.dart';

enum CacheStatus { idle, opening, ready, failure }

sealed class CacheBlocEvent {
  const CacheBlocEvent();
}

class CacheStarted extends CacheBlocEvent {
  const CacheStarted();
}

class CacheSessionChanged extends CacheBlocEvent {
  final int? ownerId;
  const CacheSessionChanged(this.ownerId);
}

class CacheUserClearRequested extends CacheBlocEvent {
  final int ownerId;
  const CacheUserClearRequested(this.ownerId);
}

class CacheMemoryClearRequested extends CacheBlocEvent {
  const CacheMemoryClearRequested();
}

class _CacheBusEventReceived extends CacheBlocEvent {
  final CacheEvent event;
  const _CacheBusEventReceived(this.event);
}

class CacheState {
  final CacheStatus status;
  final int? ownerId;
  final String? error;
  final DateTime? lastEventAt;

  const CacheState({
    required this.status,
    this.ownerId,
    this.error,
    this.lastEventAt,
  });

  const CacheState.idle() : this(status: CacheStatus.idle);

  CacheState copyWith({
    CacheStatus? status,
    int? ownerId,
    bool clearOwnerId = false,
    String? error,
    bool clearError = false,
    DateTime? lastEventAt,
  }) {
    return CacheState(
      status: status ?? this.status,
      ownerId: clearOwnerId ? null : ownerId ?? this.ownerId,
      error: clearError ? null : error ?? this.error,
      lastEventAt: lastEventAt ?? this.lastEventAt,
    );
  }
}

class CacheBloc extends Bloc<CacheBlocEvent, CacheState> {
  final CacheRepository repository;
  late final StreamSubscription<CacheEvent> _eventsSub;

  CacheBloc({required this.repository}) : super(const CacheState.idle()) {
    on<CacheStarted>(_onStarted);
    on<CacheSessionChanged>(_onSessionChanged);
    on<CacheUserClearRequested>(_onClearUser);
    on<CacheMemoryClearRequested>(_onClearMemory);
    on<_CacheBusEventReceived>(_onBusEvent);
    _eventsSub = repository.eventBus.stream.listen(
      (event) => add(_CacheBusEventReceived(event)),
    );
  }

  Future<void> _onStarted(CacheStarted event, Emitter<CacheState> emit) async {
    emit(state.copyWith(status: CacheStatus.opening, clearError: true));
    try {
      await repository.initialize();
      emit(state.copyWith(status: CacheStatus.ready, clearError: true));
    } catch (error) {
      emit(
        state.copyWith(
          status: CacheStatus.failure,
          error: '$error',
          lastEventAt: DateTime.now(),
        ),
      );
    }
  }

  void _onSessionChanged(CacheSessionChanged event, Emitter<CacheState> emit) {
    emit(
      state.copyWith(
        ownerId: event.ownerId,
        clearOwnerId: event.ownerId == null,
        clearError: true,
      ),
    );
  }

  Future<void> _onClearUser(
    CacheUserClearRequested event,
    Emitter<CacheState> emit,
  ) async {
    await repository.clearUser(event.ownerId);
    emit(state.copyWith(lastEventAt: DateTime.now(), clearError: true));
  }

  void _onClearMemory(
    CacheMemoryClearRequested event,
    Emitter<CacheState> emit,
  ) {
    repository.clearMemory();
    emit(state.copyWith(lastEventAt: DateTime.now(), clearError: true));
  }

  void _onBusEvent(_CacheBusEventReceived event, Emitter<CacheState> emit) {
    final cacheEvent = event.event;
    if (cacheEvent is CacheFailureEvent) {
      emit(
        state.copyWith(
          status: CacheStatus.failure,
          error: '${cacheEvent.error}',
          lastEventAt: cacheEvent.time,
        ),
      );
      return;
    }
    if (cacheEvent is CacheReadyEvent) {
      emit(
        state.copyWith(
          status: CacheStatus.ready,
          lastEventAt: cacheEvent.time,
          clearError: true,
        ),
      );
      return;
    }
    emit(state.copyWith(lastEventAt: cacheEvent.time, clearError: true));
  }

  @override
  Future<void> close() async {
    await _eventsSub.cancel();
    return super.close();
  }
}

import 'cache_bloc.dart';
import 'cache_database.dart';
import 'cache_event_bus.dart';
import 'cache_repository.dart';
import 'api_response_cache_bridge.dart';

class AppCache {
  AppCache._();

  static final AppCache instance = AppCache._();

  late final CacheDatabase database;
  late final CacheEventBus eventBus;
  late final CacheRepository repository;
  late final CacheBloc bloc;
  bool _created = false;

  void create() {
    if (_created) return;
    database = CacheDatabase();
    eventBus = CacheEventBus();
    repository = CacheRepository(database: database, eventBus: eventBus);
    ApiResponseCacheBridge.configure(
      reader: repository.loadApiResponse,
      writer: repository.cacheApiResponse,
    );
    bloc = CacheBloc(repository: repository)..add(const CacheStarted());
    _created = true;
  }

  Future<void> close() async {
    if (!_created) return;
    ApiResponseCacheBridge.reset();
    await bloc.close();
    await eventBus.close();
    await database.close();
    _created = false;
  }
}

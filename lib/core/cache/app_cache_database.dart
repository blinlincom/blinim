import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

class AppCacheDatabase implements QueryExecutorUser {
  final QueryExecutor _executor;
  bool _opened = false;

  AppCacheDatabase()
    : _executor = driftDatabase(
        name: 'blinlin_app_cache',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
        native: const DriftNativeOptions(shareAcrossIsolates: true),
      );

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {
    await executor.runCustom('''
CREATE TABLE IF NOT EXISTS cache_entries (
  scope TEXT NOT NULL,
  cache_key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(scope, cache_key)
)
''');
    await executor.runCustom('''
CREATE TABLE IF NOT EXISTS api_responses (
  path TEXT NOT NULL,
  request_key TEXT NOT NULL,
  response_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(path, request_key)
)
''');
    await executor.runCustom('''
CREATE TABLE IF NOT EXISTS im_messages (
  conversation_key TEXT NOT NULL,
  message_key TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  msg_type TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(conversation_key, message_key)
)
''');
    await executor.runCustom('''
CREATE TABLE IF NOT EXISTS cache_meta (
  meta_key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await executor.runCustom(
      'CREATE INDEX IF NOT EXISTS idx_cache_entries_scope_updated ON cache_entries(scope, updated_at DESC)',
    );
    await executor.runCustom(
      'CREATE INDEX IF NOT EXISTS idx_api_responses_updated ON api_responses(updated_at DESC)',
    );
    await executor.runCustom(
      'CREATE INDEX IF NOT EXISTS idx_im_messages_conversation_created ON im_messages(conversation_key, created_at ASC)',
    );
  }

  Future<void> open() async {
    if (_opened) return;
    await _executor.ensureOpen(this);
    _opened = true;
  }

  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    await open();
    return _executor.runSelect(sql, args);
  }

  Future<int> insert(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    await open();
    return _executor.runInsert(sql, args);
  }

  Future<int> update(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    await open();
    return _executor.runUpdate(sql, args);
  }

  Future<int> delete(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    await open();
    return _executor.runDelete(sql, args);
  }

  Future<void> custom(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    await open();
    await _executor.runCustom(sql, args);
  }

  Future<void> close() async {
    await _executor.close();
    _opened = false;
  }
}

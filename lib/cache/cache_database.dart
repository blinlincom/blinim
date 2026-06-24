import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'cache_database.g.dart';

class CachedConversations extends Table {
  IntColumn get ownerId => integer()();
  TextColumn get conversationKey => text()();
  TextColumn get kind => text()();
  IntColumn get targetId => integer()();
  TextColumn get title => text()();
  TextColumn get avatar => text()();
  TextColumn get preview => text()();
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  IntColumn get unread => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();
  TextColumn get rawJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, conversationKey};
}

class CachedMessages extends Table {
  IntColumn get ownerId => integer()();
  TextColumn get conversationKey => text()();
  TextColumn get messageKey => text()();
  IntColumn get messageId => integer().withDefault(const Constant(0))();
  TextColumn get clientMsgNo => text().withDefault(const Constant(''))();
  IntColumn get fromUserId => integer().withDefault(const Constant(0))();
  IntColumn get toUserId => integer().withDefault(const Constant(0))();
  TextColumn get fromUid => text().withDefault(const Constant(''))();
  TextColumn get toUid => text().withDefault(const Constant(''))();
  TextColumn get msgType => text()();
  TextColumn get contentJson => text()();
  TextColumn get rawJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isMe => boolean().withDefault(const Constant(false))();
  BoolColumn get read => boolean().withDefault(const Constant(false))();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, conversationKey, messageKey};
}

class CachedProfiles extends Table {
  IntColumn get ownerId => integer()();
  IntColumn get userId => integer()();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get nickname => text()();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get titleColor => text().withDefault(const Constant(''))();
  TextColumn get rawJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, userId};
}

class CachedGroups extends Table {
  IntColumn get ownerId => integer()();
  IntColumn get groupId => integer()();
  TextColumn get groupNo => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  IntColumn get memberCount => integer().withDefault(const Constant(0))();
  TextColumn get rawJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, groupId};
}

class CachedApiResponses extends Table {
  TextColumn get namespace => text()();
  TextColumn get cacheKey => text()();
  TextColumn get path => text()();
  TextColumn get responseJson => text()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {namespace, cacheKey};
}

@DriftDatabase(
  tables: [
    CachedConversations,
    CachedMessages,
    CachedProfiles,
    CachedGroups,
    CachedApiResponses,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(cachedApiResponses);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> assertReady() async {
    await customSelect('SELECT 1 AS ok').getSingle();
  }

  Future<void> upsertConversation(CachedConversationsCompanion entry) {
    return into(cachedConversations).insertOnConflictUpdate(entry);
  }

  Future<void> upsertConversations(
    Iterable<CachedConversationsCompanion> entries,
  ) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedConversations, entries.toList());
    });
  }

  Future<List<CachedConversation>> loadConversations(int ownerId) {
    final query = select(cachedConversations)
      ..where((table) => table.ownerId.equals(ownerId))
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.pinned, mode: OrderingMode.desc),
        (table) => OrderingTerm(
          expression: table.lastMessageAt,
          mode: OrderingMode.desc,
        ),
        (table) =>
            OrderingTerm(expression: table.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.get();
  }

  Future<void> upsertMessages(Iterable<CachedMessagesCompanion> entries) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedMessages, entries.toList());
    });
  }

  Future<List<CachedMessage>> loadMessages({
    required int ownerId,
    required String conversationKey,
    int limit = 80,
  }) async {
    final query = select(cachedMessages)
      ..where(
        (table) =>
            table.ownerId.equals(ownerId) &
            table.conversationKey.equals(conversationKey),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.reversed.toList(growable: false);
  }

  Future<void> deleteConversationMessages({
    required int ownerId,
    required String conversationKey,
  }) {
    return (delete(cachedMessages)..where(
          (table) =>
              table.ownerId.equals(ownerId) &
              table.conversationKey.equals(conversationKey),
        ))
        .go();
  }

  Future<void> deleteMessages({
    required int ownerId,
    required String conversationKey,
    required Iterable<String> messageKeys,
  }) {
    final keys = messageKeys.toSet();
    if (keys.isEmpty) return Future<void>.value();
    return (delete(cachedMessages)..where(
          (table) =>
              table.ownerId.equals(ownerId) &
              table.conversationKey.equals(conversationKey) &
              table.messageKey.isIn(keys),
        ))
        .go();
  }

  Future<void> upsertProfiles(Iterable<CachedProfilesCompanion> entries) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedProfiles, entries.toList());
    });
  }

  Future<void> upsertGroups(Iterable<CachedGroupsCompanion> entries) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedGroups, entries.toList());
    });
  }

  Future<List<CachedGroup>> loadGroups(int ownerId) {
    final query = select(cachedGroups)
      ..where((table) => table.ownerId.equals(ownerId))
      ..orderBy([(table) => OrderingTerm(expression: table.name)]);
    return query.get();
  }

  Future<void> upsertApiResponse(CachedApiResponsesCompanion entry) {
    return into(cachedApiResponses).insertOnConflictUpdate(entry);
  }

  Future<CachedApiResponse?> loadApiResponse({
    required String namespace,
    required String cacheKey,
  }) {
    final query = select(cachedApiResponses)
      ..where(
        (table) =>
            table.namespace.equals(namespace) & table.cacheKey.equals(cacheKey),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> deleteExpiredApiResponses(DateTime now) {
    return (delete(cachedApiResponses)..where(
          (table) =>
              table.expiresAt.isNotNull() &
              table.expiresAt.isSmallerThanValue(now),
        ))
        .go();
  }

  Future<void> clearUser(int ownerId) async {
    await transaction(() async {
      await (delete(
        cachedMessages,
      )..where((table) => table.ownerId.equals(ownerId))).go();
      await (delete(
        cachedConversations,
      )..where((table) => table.ownerId.equals(ownerId))).go();
      await (delete(
        cachedProfiles,
      )..where((table) => table.ownerId.equals(ownerId))).go();
      await (delete(
        cachedGroups,
      )..where((table) => table.ownerId.equals(ownerId))).go();
    });
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'blinlin_cache',
    native: const DriftNativeOptions(shareAcrossIsolates: true),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.dart.js'),
    ),
  );
}

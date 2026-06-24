// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $CachedConversationsTable extends CachedConversations
    with TableInfo<$CachedConversationsTable, CachedConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<int> ownerId = GeneratedColumn<int>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationKeyMeta = const VerificationMeta(
    'conversationKey',
  );
  @override
  late final GeneratedColumn<String> conversationKey = GeneratedColumn<String>(
    'conversation_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt =
      GeneratedColumn<DateTime>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unreadMeta = const VerificationMeta('unread');
  @override
  late final GeneratedColumn<int> unread = GeneratedColumn<int>(
    'unread',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _mutedMeta = const VerificationMeta('muted');
  @override
  late final GeneratedColumn<bool> muted = GeneratedColumn<bool>(
    'muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    conversationKey,
    kind,
    targetId,
    title,
    avatar,
    preview,
    lastMessageAt,
    unread,
    pinned,
    muted,
    rawJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('conversation_key')) {
      context.handle(
        _conversationKeyMeta,
        conversationKey.isAcceptableOrUnknown(
          data['conversation_key']!,
          _conversationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    } else if (isInserting) {
      context.missing(_avatarMeta);
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    } else if (isInserting) {
      context.missing(_previewMeta);
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('unread')) {
      context.handle(
        _unreadMeta,
        unread.isAcceptableOrUnknown(data['unread']!, _unreadMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('muted')) {
      context.handle(
        _mutedMeta,
        muted.isAcceptableOrUnknown(data['muted']!, _mutedMeta),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_rawJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, conversationKey};
  @override
  CachedConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedConversation(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_id'],
      )!,
      conversationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      )!,
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      unread: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      muted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}muted'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedConversationsTable createAlias(String alias) {
    return $CachedConversationsTable(attachedDatabase, alias);
  }
}

class CachedConversation extends DataClass
    implements Insertable<CachedConversation> {
  final int ownerId;
  final String conversationKey;
  final String kind;
  final int targetId;
  final String title;
  final String avatar;
  final String preview;
  final DateTime? lastMessageAt;
  final int unread;
  final bool pinned;
  final bool muted;
  final String rawJson;
  final DateTime updatedAt;
  const CachedConversation({
    required this.ownerId,
    required this.conversationKey,
    required this.kind,
    required this.targetId,
    required this.title,
    required this.avatar,
    required this.preview,
    this.lastMessageAt,
    required this.unread,
    required this.pinned,
    required this.muted,
    required this.rawJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<int>(ownerId);
    map['conversation_key'] = Variable<String>(conversationKey);
    map['kind'] = Variable<String>(kind);
    map['target_id'] = Variable<int>(targetId);
    map['title'] = Variable<String>(title);
    map['avatar'] = Variable<String>(avatar);
    map['preview'] = Variable<String>(preview);
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['unread'] = Variable<int>(unread);
    map['pinned'] = Variable<bool>(pinned);
    map['muted'] = Variable<bool>(muted);
    map['raw_json'] = Variable<String>(rawJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedConversationsCompanion toCompanion(bool nullToAbsent) {
    return CachedConversationsCompanion(
      ownerId: Value(ownerId),
      conversationKey: Value(conversationKey),
      kind: Value(kind),
      targetId: Value(targetId),
      title: Value(title),
      avatar: Value(avatar),
      preview: Value(preview),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      unread: Value(unread),
      pinned: Value(pinned),
      muted: Value(muted),
      rawJson: Value(rawJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedConversation(
      ownerId: serializer.fromJson<int>(json['ownerId']),
      conversationKey: serializer.fromJson<String>(json['conversationKey']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<int>(json['targetId']),
      title: serializer.fromJson<String>(json['title']),
      avatar: serializer.fromJson<String>(json['avatar']),
      preview: serializer.fromJson<String>(json['preview']),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      unread: serializer.fromJson<int>(json['unread']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      muted: serializer.fromJson<bool>(json['muted']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<int>(ownerId),
      'conversationKey': serializer.toJson<String>(conversationKey),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<int>(targetId),
      'title': serializer.toJson<String>(title),
      'avatar': serializer.toJson<String>(avatar),
      'preview': serializer.toJson<String>(preview),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'unread': serializer.toJson<int>(unread),
      'pinned': serializer.toJson<bool>(pinned),
      'muted': serializer.toJson<bool>(muted),
      'rawJson': serializer.toJson<String>(rawJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedConversation copyWith({
    int? ownerId,
    String? conversationKey,
    String? kind,
    int? targetId,
    String? title,
    String? avatar,
    String? preview,
    Value<DateTime?> lastMessageAt = const Value.absent(),
    int? unread,
    bool? pinned,
    bool? muted,
    String? rawJson,
    DateTime? updatedAt,
  }) => CachedConversation(
    ownerId: ownerId ?? this.ownerId,
    conversationKey: conversationKey ?? this.conversationKey,
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    title: title ?? this.title,
    avatar: avatar ?? this.avatar,
    preview: preview ?? this.preview,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    unread: unread ?? this.unread,
    pinned: pinned ?? this.pinned,
    muted: muted ?? this.muted,
    rawJson: rawJson ?? this.rawJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedConversation copyWithCompanion(CachedConversationsCompanion data) {
    return CachedConversation(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      conversationKey: data.conversationKey.present
          ? data.conversationKey.value
          : this.conversationKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      title: data.title.present ? data.title.value : this.title,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      preview: data.preview.present ? data.preview.value : this.preview,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      unread: data.unread.present ? data.unread.value : this.unread,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      muted: data.muted.present ? data.muted.value : this.muted,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedConversation(')
          ..write('ownerId: $ownerId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('preview: $preview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unread: $unread, ')
          ..write('pinned: $pinned, ')
          ..write('muted: $muted, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    conversationKey,
    kind,
    targetId,
    title,
    avatar,
    preview,
    lastMessageAt,
    unread,
    pinned,
    muted,
    rawJson,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedConversation &&
          other.ownerId == this.ownerId &&
          other.conversationKey == this.conversationKey &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.title == this.title &&
          other.avatar == this.avatar &&
          other.preview == this.preview &&
          other.lastMessageAt == this.lastMessageAt &&
          other.unread == this.unread &&
          other.pinned == this.pinned &&
          other.muted == this.muted &&
          other.rawJson == this.rawJson &&
          other.updatedAt == this.updatedAt);
}

class CachedConversationsCompanion extends UpdateCompanion<CachedConversation> {
  final Value<int> ownerId;
  final Value<String> conversationKey;
  final Value<String> kind;
  final Value<int> targetId;
  final Value<String> title;
  final Value<String> avatar;
  final Value<String> preview;
  final Value<DateTime?> lastMessageAt;
  final Value<int> unread;
  final Value<bool> pinned;
  final Value<bool> muted;
  final Value<String> rawJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedConversationsCompanion({
    this.ownerId = const Value.absent(),
    this.conversationKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.preview = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.unread = const Value.absent(),
    this.pinned = const Value.absent(),
    this.muted = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedConversationsCompanion.insert({
    required int ownerId,
    required String conversationKey,
    required String kind,
    required int targetId,
    required String title,
    required String avatar,
    required String preview,
    this.lastMessageAt = const Value.absent(),
    this.unread = const Value.absent(),
    this.pinned = const Value.absent(),
    this.muted = const Value.absent(),
    required String rawJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       conversationKey = Value(conversationKey),
       kind = Value(kind),
       targetId = Value(targetId),
       title = Value(title),
       avatar = Value(avatar),
       preview = Value(preview),
       rawJson = Value(rawJson),
       updatedAt = Value(updatedAt);
  static Insertable<CachedConversation> custom({
    Expression<int>? ownerId,
    Expression<String>? conversationKey,
    Expression<String>? kind,
    Expression<int>? targetId,
    Expression<String>? title,
    Expression<String>? avatar,
    Expression<String>? preview,
    Expression<DateTime>? lastMessageAt,
    Expression<int>? unread,
    Expression<bool>? pinned,
    Expression<bool>? muted,
    Expression<String>? rawJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (conversationKey != null) 'conversation_key': conversationKey,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (title != null) 'title': title,
      if (avatar != null) 'avatar': avatar,
      if (preview != null) 'preview': preview,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (unread != null) 'unread': unread,
      if (pinned != null) 'pinned': pinned,
      if (muted != null) 'muted': muted,
      if (rawJson != null) 'raw_json': rawJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedConversationsCompanion copyWith({
    Value<int>? ownerId,
    Value<String>? conversationKey,
    Value<String>? kind,
    Value<int>? targetId,
    Value<String>? title,
    Value<String>? avatar,
    Value<String>? preview,
    Value<DateTime?>? lastMessageAt,
    Value<int>? unread,
    Value<bool>? pinned,
    Value<bool>? muted,
    Value<String>? rawJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedConversationsCompanion(
      ownerId: ownerId ?? this.ownerId,
      conversationKey: conversationKey ?? this.conversationKey,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      title: title ?? this.title,
      avatar: avatar ?? this.avatar,
      preview: preview ?? this.preview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unread: unread ?? this.unread,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      rawJson: rawJson ?? this.rawJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<int>(ownerId.value);
    }
    if (conversationKey.present) {
      map['conversation_key'] = Variable<String>(conversationKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (unread.present) {
      map['unread'] = Variable<int>(unread.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (muted.present) {
      map['muted'] = Variable<bool>(muted.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedConversationsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('preview: $preview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unread: $unread, ')
          ..write('pinned: $pinned, ')
          ..write('muted: $muted, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMessagesTable extends CachedMessages
    with TableInfo<$CachedMessagesTable, CachedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<int> ownerId = GeneratedColumn<int>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationKeyMeta = const VerificationMeta(
    'conversationKey',
  );
  @override
  late final GeneratedColumn<String> conversationKey = GeneratedColumn<String>(
    'conversation_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageKeyMeta = const VerificationMeta(
    'messageKey',
  );
  @override
  late final GeneratedColumn<String> messageKey = GeneratedColumn<String>(
    'message_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _clientMsgNoMeta = const VerificationMeta(
    'clientMsgNo',
  );
  @override
  late final GeneratedColumn<String> clientMsgNo = GeneratedColumn<String>(
    'client_msg_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _fromUserIdMeta = const VerificationMeta(
    'fromUserId',
  );
  @override
  late final GeneratedColumn<int> fromUserId = GeneratedColumn<int>(
    'from_user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _toUserIdMeta = const VerificationMeta(
    'toUserId',
  );
  @override
  late final GeneratedColumn<int> toUserId = GeneratedColumn<int>(
    'to_user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fromUidMeta = const VerificationMeta(
    'fromUid',
  );
  @override
  late final GeneratedColumn<String> fromUid = GeneratedColumn<String>(
    'from_uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _toUidMeta = const VerificationMeta('toUid');
  @override
  late final GeneratedColumn<String> toUid = GeneratedColumn<String>(
    'to_uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _msgTypeMeta = const VerificationMeta(
    'msgType',
  );
  @override
  late final GeneratedColumn<String> msgType = GeneratedColumn<String>(
    'msg_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentJsonMeta = const VerificationMeta(
    'contentJson',
  );
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
    'content_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isMeMeta = const VerificationMeta('isMe');
  @override
  late final GeneratedColumn<bool> isMe = GeneratedColumn<bool>(
    'is_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_me" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    conversationKey,
    messageKey,
    messageId,
    clientMsgNo,
    fromUserId,
    toUserId,
    fromUid,
    toUid,
    msgType,
    contentJson,
    rawJson,
    createdAt,
    isMe,
    read,
    readAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('conversation_key')) {
      context.handle(
        _conversationKeyMeta,
        conversationKey.isAcceptableOrUnknown(
          data['conversation_key']!,
          _conversationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationKeyMeta);
    }
    if (data.containsKey('message_key')) {
      context.handle(
        _messageKeyMeta,
        messageKey.isAcceptableOrUnknown(data['message_key']!, _messageKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_messageKeyMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('client_msg_no')) {
      context.handle(
        _clientMsgNoMeta,
        clientMsgNo.isAcceptableOrUnknown(
          data['client_msg_no']!,
          _clientMsgNoMeta,
        ),
      );
    }
    if (data.containsKey('from_user_id')) {
      context.handle(
        _fromUserIdMeta,
        fromUserId.isAcceptableOrUnknown(
          data['from_user_id']!,
          _fromUserIdMeta,
        ),
      );
    }
    if (data.containsKey('to_user_id')) {
      context.handle(
        _toUserIdMeta,
        toUserId.isAcceptableOrUnknown(data['to_user_id']!, _toUserIdMeta),
      );
    }
    if (data.containsKey('from_uid')) {
      context.handle(
        _fromUidMeta,
        fromUid.isAcceptableOrUnknown(data['from_uid']!, _fromUidMeta),
      );
    }
    if (data.containsKey('to_uid')) {
      context.handle(
        _toUidMeta,
        toUid.isAcceptableOrUnknown(data['to_uid']!, _toUidMeta),
      );
    }
    if (data.containsKey('msg_type')) {
      context.handle(
        _msgTypeMeta,
        msgType.isAcceptableOrUnknown(data['msg_type']!, _msgTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_msgTypeMeta);
    }
    if (data.containsKey('content_json')) {
      context.handle(
        _contentJsonMeta,
        contentJson.isAcceptableOrUnknown(
          data['content_json']!,
          _contentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentJsonMeta);
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_rawJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_me')) {
      context.handle(
        _isMeMeta,
        isMe.isAcceptableOrUnknown(data['is_me']!, _isMeMeta),
      );
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    ownerId,
    conversationKey,
    messageKey,
  };
  @override
  CachedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMessage(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_id'],
      )!,
      conversationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_key'],
      )!,
      messageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_key'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      clientMsgNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_msg_no'],
      )!,
      fromUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_user_id'],
      )!,
      toUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_user_id'],
      )!,
      fromUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_uid'],
      )!,
      toUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_uid'],
      )!,
      msgType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}msg_type'],
      )!,
      contentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_json'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      isMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_me'],
      )!,
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedMessagesTable createAlias(String alias) {
    return $CachedMessagesTable(attachedDatabase, alias);
  }
}

class CachedMessage extends DataClass implements Insertable<CachedMessage> {
  final int ownerId;
  final String conversationKey;
  final String messageKey;
  final int messageId;
  final String clientMsgNo;
  final int fromUserId;
  final int toUserId;
  final String fromUid;
  final String toUid;
  final String msgType;
  final String contentJson;
  final String rawJson;
  final DateTime createdAt;
  final bool isMe;
  final bool read;
  final DateTime? readAt;
  final DateTime updatedAt;
  const CachedMessage({
    required this.ownerId,
    required this.conversationKey,
    required this.messageKey,
    required this.messageId,
    required this.clientMsgNo,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUid,
    required this.toUid,
    required this.msgType,
    required this.contentJson,
    required this.rawJson,
    required this.createdAt,
    required this.isMe,
    required this.read,
    this.readAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<int>(ownerId);
    map['conversation_key'] = Variable<String>(conversationKey);
    map['message_key'] = Variable<String>(messageKey);
    map['message_id'] = Variable<int>(messageId);
    map['client_msg_no'] = Variable<String>(clientMsgNo);
    map['from_user_id'] = Variable<int>(fromUserId);
    map['to_user_id'] = Variable<int>(toUserId);
    map['from_uid'] = Variable<String>(fromUid);
    map['to_uid'] = Variable<String>(toUid);
    map['msg_type'] = Variable<String>(msgType);
    map['content_json'] = Variable<String>(contentJson);
    map['raw_json'] = Variable<String>(rawJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_me'] = Variable<bool>(isMe);
    map['read'] = Variable<bool>(read);
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedMessagesCompanion toCompanion(bool nullToAbsent) {
    return CachedMessagesCompanion(
      ownerId: Value(ownerId),
      conversationKey: Value(conversationKey),
      messageKey: Value(messageKey),
      messageId: Value(messageId),
      clientMsgNo: Value(clientMsgNo),
      fromUserId: Value(fromUserId),
      toUserId: Value(toUserId),
      fromUid: Value(fromUid),
      toUid: Value(toUid),
      msgType: Value(msgType),
      contentJson: Value(contentJson),
      rawJson: Value(rawJson),
      createdAt: Value(createdAt),
      isMe: Value(isMe),
      read: Value(read),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMessage(
      ownerId: serializer.fromJson<int>(json['ownerId']),
      conversationKey: serializer.fromJson<String>(json['conversationKey']),
      messageKey: serializer.fromJson<String>(json['messageKey']),
      messageId: serializer.fromJson<int>(json['messageId']),
      clientMsgNo: serializer.fromJson<String>(json['clientMsgNo']),
      fromUserId: serializer.fromJson<int>(json['fromUserId']),
      toUserId: serializer.fromJson<int>(json['toUserId']),
      fromUid: serializer.fromJson<String>(json['fromUid']),
      toUid: serializer.fromJson<String>(json['toUid']),
      msgType: serializer.fromJson<String>(json['msgType']),
      contentJson: serializer.fromJson<String>(json['contentJson']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isMe: serializer.fromJson<bool>(json['isMe']),
      read: serializer.fromJson<bool>(json['read']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<int>(ownerId),
      'conversationKey': serializer.toJson<String>(conversationKey),
      'messageKey': serializer.toJson<String>(messageKey),
      'messageId': serializer.toJson<int>(messageId),
      'clientMsgNo': serializer.toJson<String>(clientMsgNo),
      'fromUserId': serializer.toJson<int>(fromUserId),
      'toUserId': serializer.toJson<int>(toUserId),
      'fromUid': serializer.toJson<String>(fromUid),
      'toUid': serializer.toJson<String>(toUid),
      'msgType': serializer.toJson<String>(msgType),
      'contentJson': serializer.toJson<String>(contentJson),
      'rawJson': serializer.toJson<String>(rawJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isMe': serializer.toJson<bool>(isMe),
      'read': serializer.toJson<bool>(read),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedMessage copyWith({
    int? ownerId,
    String? conversationKey,
    String? messageKey,
    int? messageId,
    String? clientMsgNo,
    int? fromUserId,
    int? toUserId,
    String? fromUid,
    String? toUid,
    String? msgType,
    String? contentJson,
    String? rawJson,
    DateTime? createdAt,
    bool? isMe,
    bool? read,
    Value<DateTime?> readAt = const Value.absent(),
    DateTime? updatedAt,
  }) => CachedMessage(
    ownerId: ownerId ?? this.ownerId,
    conversationKey: conversationKey ?? this.conversationKey,
    messageKey: messageKey ?? this.messageKey,
    messageId: messageId ?? this.messageId,
    clientMsgNo: clientMsgNo ?? this.clientMsgNo,
    fromUserId: fromUserId ?? this.fromUserId,
    toUserId: toUserId ?? this.toUserId,
    fromUid: fromUid ?? this.fromUid,
    toUid: toUid ?? this.toUid,
    msgType: msgType ?? this.msgType,
    contentJson: contentJson ?? this.contentJson,
    rawJson: rawJson ?? this.rawJson,
    createdAt: createdAt ?? this.createdAt,
    isMe: isMe ?? this.isMe,
    read: read ?? this.read,
    readAt: readAt.present ? readAt.value : this.readAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedMessage copyWithCompanion(CachedMessagesCompanion data) {
    return CachedMessage(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      conversationKey: data.conversationKey.present
          ? data.conversationKey.value
          : this.conversationKey,
      messageKey: data.messageKey.present
          ? data.messageKey.value
          : this.messageKey,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      clientMsgNo: data.clientMsgNo.present
          ? data.clientMsgNo.value
          : this.clientMsgNo,
      fromUserId: data.fromUserId.present
          ? data.fromUserId.value
          : this.fromUserId,
      toUserId: data.toUserId.present ? data.toUserId.value : this.toUserId,
      fromUid: data.fromUid.present ? data.fromUid.value : this.fromUid,
      toUid: data.toUid.present ? data.toUid.value : this.toUid,
      msgType: data.msgType.present ? data.msgType.value : this.msgType,
      contentJson: data.contentJson.present
          ? data.contentJson.value
          : this.contentJson,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isMe: data.isMe.present ? data.isMe.value : this.isMe,
      read: data.read.present ? data.read.value : this.read,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessage(')
          ..write('ownerId: $ownerId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('messageKey: $messageKey, ')
          ..write('messageId: $messageId, ')
          ..write('clientMsgNo: $clientMsgNo, ')
          ..write('fromUserId: $fromUserId, ')
          ..write('toUserId: $toUserId, ')
          ..write('fromUid: $fromUid, ')
          ..write('toUid: $toUid, ')
          ..write('msgType: $msgType, ')
          ..write('contentJson: $contentJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('isMe: $isMe, ')
          ..write('read: $read, ')
          ..write('readAt: $readAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    conversationKey,
    messageKey,
    messageId,
    clientMsgNo,
    fromUserId,
    toUserId,
    fromUid,
    toUid,
    msgType,
    contentJson,
    rawJson,
    createdAt,
    isMe,
    read,
    readAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMessage &&
          other.ownerId == this.ownerId &&
          other.conversationKey == this.conversationKey &&
          other.messageKey == this.messageKey &&
          other.messageId == this.messageId &&
          other.clientMsgNo == this.clientMsgNo &&
          other.fromUserId == this.fromUserId &&
          other.toUserId == this.toUserId &&
          other.fromUid == this.fromUid &&
          other.toUid == this.toUid &&
          other.msgType == this.msgType &&
          other.contentJson == this.contentJson &&
          other.rawJson == this.rawJson &&
          other.createdAt == this.createdAt &&
          other.isMe == this.isMe &&
          other.read == this.read &&
          other.readAt == this.readAt &&
          other.updatedAt == this.updatedAt);
}

class CachedMessagesCompanion extends UpdateCompanion<CachedMessage> {
  final Value<int> ownerId;
  final Value<String> conversationKey;
  final Value<String> messageKey;
  final Value<int> messageId;
  final Value<String> clientMsgNo;
  final Value<int> fromUserId;
  final Value<int> toUserId;
  final Value<String> fromUid;
  final Value<String> toUid;
  final Value<String> msgType;
  final Value<String> contentJson;
  final Value<String> rawJson;
  final Value<DateTime> createdAt;
  final Value<bool> isMe;
  final Value<bool> read;
  final Value<DateTime?> readAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedMessagesCompanion({
    this.ownerId = const Value.absent(),
    this.conversationKey = const Value.absent(),
    this.messageKey = const Value.absent(),
    this.messageId = const Value.absent(),
    this.clientMsgNo = const Value.absent(),
    this.fromUserId = const Value.absent(),
    this.toUserId = const Value.absent(),
    this.fromUid = const Value.absent(),
    this.toUid = const Value.absent(),
    this.msgType = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isMe = const Value.absent(),
    this.read = const Value.absent(),
    this.readAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMessagesCompanion.insert({
    required int ownerId,
    required String conversationKey,
    required String messageKey,
    this.messageId = const Value.absent(),
    this.clientMsgNo = const Value.absent(),
    this.fromUserId = const Value.absent(),
    this.toUserId = const Value.absent(),
    this.fromUid = const Value.absent(),
    this.toUid = const Value.absent(),
    required String msgType,
    required String contentJson,
    required String rawJson,
    required DateTime createdAt,
    this.isMe = const Value.absent(),
    this.read = const Value.absent(),
    this.readAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       conversationKey = Value(conversationKey),
       messageKey = Value(messageKey),
       msgType = Value(msgType),
       contentJson = Value(contentJson),
       rawJson = Value(rawJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedMessage> custom({
    Expression<int>? ownerId,
    Expression<String>? conversationKey,
    Expression<String>? messageKey,
    Expression<int>? messageId,
    Expression<String>? clientMsgNo,
    Expression<int>? fromUserId,
    Expression<int>? toUserId,
    Expression<String>? fromUid,
    Expression<String>? toUid,
    Expression<String>? msgType,
    Expression<String>? contentJson,
    Expression<String>? rawJson,
    Expression<DateTime>? createdAt,
    Expression<bool>? isMe,
    Expression<bool>? read,
    Expression<DateTime>? readAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (conversationKey != null) 'conversation_key': conversationKey,
      if (messageKey != null) 'message_key': messageKey,
      if (messageId != null) 'message_id': messageId,
      if (clientMsgNo != null) 'client_msg_no': clientMsgNo,
      if (fromUserId != null) 'from_user_id': fromUserId,
      if (toUserId != null) 'to_user_id': toUserId,
      if (fromUid != null) 'from_uid': fromUid,
      if (toUid != null) 'to_uid': toUid,
      if (msgType != null) 'msg_type': msgType,
      if (contentJson != null) 'content_json': contentJson,
      if (rawJson != null) 'raw_json': rawJson,
      if (createdAt != null) 'created_at': createdAt,
      if (isMe != null) 'is_me': isMe,
      if (read != null) 'read': read,
      if (readAt != null) 'read_at': readAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMessagesCompanion copyWith({
    Value<int>? ownerId,
    Value<String>? conversationKey,
    Value<String>? messageKey,
    Value<int>? messageId,
    Value<String>? clientMsgNo,
    Value<int>? fromUserId,
    Value<int>? toUserId,
    Value<String>? fromUid,
    Value<String>? toUid,
    Value<String>? msgType,
    Value<String>? contentJson,
    Value<String>? rawJson,
    Value<DateTime>? createdAt,
    Value<bool>? isMe,
    Value<bool>? read,
    Value<DateTime?>? readAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedMessagesCompanion(
      ownerId: ownerId ?? this.ownerId,
      conversationKey: conversationKey ?? this.conversationKey,
      messageKey: messageKey ?? this.messageKey,
      messageId: messageId ?? this.messageId,
      clientMsgNo: clientMsgNo ?? this.clientMsgNo,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      fromUid: fromUid ?? this.fromUid,
      toUid: toUid ?? this.toUid,
      msgType: msgType ?? this.msgType,
      contentJson: contentJson ?? this.contentJson,
      rawJson: rawJson ?? this.rawJson,
      createdAt: createdAt ?? this.createdAt,
      isMe: isMe ?? this.isMe,
      read: read ?? this.read,
      readAt: readAt ?? this.readAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<int>(ownerId.value);
    }
    if (conversationKey.present) {
      map['conversation_key'] = Variable<String>(conversationKey.value);
    }
    if (messageKey.present) {
      map['message_key'] = Variable<String>(messageKey.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (clientMsgNo.present) {
      map['client_msg_no'] = Variable<String>(clientMsgNo.value);
    }
    if (fromUserId.present) {
      map['from_user_id'] = Variable<int>(fromUserId.value);
    }
    if (toUserId.present) {
      map['to_user_id'] = Variable<int>(toUserId.value);
    }
    if (fromUid.present) {
      map['from_uid'] = Variable<String>(fromUid.value);
    }
    if (toUid.present) {
      map['to_uid'] = Variable<String>(toUid.value);
    }
    if (msgType.present) {
      map['msg_type'] = Variable<String>(msgType.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isMe.present) {
      map['is_me'] = Variable<bool>(isMe.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessagesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('conversationKey: $conversationKey, ')
          ..write('messageKey: $messageKey, ')
          ..write('messageId: $messageId, ')
          ..write('clientMsgNo: $clientMsgNo, ')
          ..write('fromUserId: $fromUserId, ')
          ..write('toUserId: $toUserId, ')
          ..write('fromUid: $fromUid, ')
          ..write('toUid: $toUid, ')
          ..write('msgType: $msgType, ')
          ..write('contentJson: $contentJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('isMe: $isMe, ')
          ..write('read: $read, ')
          ..write('readAt: $readAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedProfilesTable extends CachedProfiles
    with TableInfo<$CachedProfilesTable, CachedProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<int> ownerId = GeneratedColumn<int>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleColorMeta = const VerificationMeta(
    'titleColor',
  );
  @override
  late final GeneratedColumn<String> titleColor = GeneratedColumn<String>(
    'title_color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    userId,
    username,
    nickname,
    avatar,
    title,
    titleColor,
    rawJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    } else if (isInserting) {
      context.missing(_nicknameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('title_color')) {
      context.handle(
        _titleColorMeta,
        titleColor.isAcceptableOrUnknown(data['title_color']!, _titleColorMeta),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_rawJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, userId};
  @override
  CachedProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfile(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_color'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedProfilesTable createAlias(String alias) {
    return $CachedProfilesTable(attachedDatabase, alias);
  }
}

class CachedProfile extends DataClass implements Insertable<CachedProfile> {
  final int ownerId;
  final int userId;
  final String username;
  final String nickname;
  final String avatar;
  final String title;
  final String titleColor;
  final String rawJson;
  final DateTime updatedAt;
  const CachedProfile({
    required this.ownerId,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.title,
    required this.titleColor,
    required this.rawJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<int>(ownerId);
    map['user_id'] = Variable<int>(userId);
    map['username'] = Variable<String>(username);
    map['nickname'] = Variable<String>(nickname);
    map['avatar'] = Variable<String>(avatar);
    map['title'] = Variable<String>(title);
    map['title_color'] = Variable<String>(titleColor);
    map['raw_json'] = Variable<String>(rawJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilesCompanion(
      ownerId: Value(ownerId),
      userId: Value(userId),
      username: Value(username),
      nickname: Value(nickname),
      avatar: Value(avatar),
      title: Value(title),
      titleColor: Value(titleColor),
      rawJson: Value(rawJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfile(
      ownerId: serializer.fromJson<int>(json['ownerId']),
      userId: serializer.fromJson<int>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      nickname: serializer.fromJson<String>(json['nickname']),
      avatar: serializer.fromJson<String>(json['avatar']),
      title: serializer.fromJson<String>(json['title']),
      titleColor: serializer.fromJson<String>(json['titleColor']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<int>(ownerId),
      'userId': serializer.toJson<int>(userId),
      'username': serializer.toJson<String>(username),
      'nickname': serializer.toJson<String>(nickname),
      'avatar': serializer.toJson<String>(avatar),
      'title': serializer.toJson<String>(title),
      'titleColor': serializer.toJson<String>(titleColor),
      'rawJson': serializer.toJson<String>(rawJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedProfile copyWith({
    int? ownerId,
    int? userId,
    String? username,
    String? nickname,
    String? avatar,
    String? title,
    String? titleColor,
    String? rawJson,
    DateTime? updatedAt,
  }) => CachedProfile(
    ownerId: ownerId ?? this.ownerId,
    userId: userId ?? this.userId,
    username: username ?? this.username,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
    title: title ?? this.title,
    titleColor: titleColor ?? this.titleColor,
    rawJson: rawJson ?? this.rawJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedProfile copyWithCompanion(CachedProfilesCompanion data) {
    return CachedProfile(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      title: data.title.present ? data.title.value : this.title,
      titleColor: data.titleColor.present
          ? data.titleColor.value
          : this.titleColor,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfile(')
          ..write('ownerId: $ownerId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('title: $title, ')
          ..write('titleColor: $titleColor, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    userId,
    username,
    nickname,
    avatar,
    title,
    titleColor,
    rawJson,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfile &&
          other.ownerId == this.ownerId &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.nickname == this.nickname &&
          other.avatar == this.avatar &&
          other.title == this.title &&
          other.titleColor == this.titleColor &&
          other.rawJson == this.rawJson &&
          other.updatedAt == this.updatedAt);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfile> {
  final Value<int> ownerId;
  final Value<int> userId;
  final Value<String> username;
  final Value<String> nickname;
  final Value<String> avatar;
  final Value<String> title;
  final Value<String> titleColor;
  final Value<String> rawJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.ownerId = const Value.absent(),
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.nickname = const Value.absent(),
    this.avatar = const Value.absent(),
    this.title = const Value.absent(),
    this.titleColor = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required int ownerId,
    required int userId,
    this.username = const Value.absent(),
    required String nickname,
    this.avatar = const Value.absent(),
    this.title = const Value.absent(),
    this.titleColor = const Value.absent(),
    required String rawJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       userId = Value(userId),
       nickname = Value(nickname),
       rawJson = Value(rawJson),
       updatedAt = Value(updatedAt);
  static Insertable<CachedProfile> custom({
    Expression<int>? ownerId,
    Expression<int>? userId,
    Expression<String>? username,
    Expression<String>? nickname,
    Expression<String>? avatar,
    Expression<String>? title,
    Expression<String>? titleColor,
    Expression<String>? rawJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (title != null) 'title': title,
      if (titleColor != null) 'title_color': titleColor,
      if (rawJson != null) 'raw_json': rawJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<int>? ownerId,
    Value<int>? userId,
    Value<String>? username,
    Value<String>? nickname,
    Value<String>? avatar,
    Value<String>? title,
    Value<String>? titleColor,
    Value<String>? rawJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      ownerId: ownerId ?? this.ownerId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      title: title ?? this.title,
      titleColor: titleColor ?? this.titleColor,
      rawJson: rawJson ?? this.rawJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<int>(ownerId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleColor.present) {
      map['title_color'] = Variable<String>(titleColor.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('title: $title, ')
          ..write('titleColor: $titleColor, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedGroupsTable extends CachedGroups
    with TableInfo<$CachedGroupsTable, CachedGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<int> ownerId = GeneratedColumn<int>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNoMeta = const VerificationMeta(
    'groupNo',
  );
  @override
  late final GeneratedColumn<String> groupNo = GeneratedColumn<String>(
    'group_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _memberCountMeta = const VerificationMeta(
    'memberCount',
  );
  @override
  late final GeneratedColumn<int> memberCount = GeneratedColumn<int>(
    'member_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    groupId,
    groupNo,
    name,
    avatar,
    memberCount,
    rawJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('group_no')) {
      context.handle(
        _groupNoMeta,
        groupNo.isAcceptableOrUnknown(data['group_no']!, _groupNoMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('member_count')) {
      context.handle(
        _memberCountMeta,
        memberCount.isAcceptableOrUnknown(
          data['member_count']!,
          _memberCountMeta,
        ),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_rawJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, groupId};
  @override
  CachedGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedGroup(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}owner_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      )!,
      groupNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_no'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      memberCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_count'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedGroupsTable createAlias(String alias) {
    return $CachedGroupsTable(attachedDatabase, alias);
  }
}

class CachedGroup extends DataClass implements Insertable<CachedGroup> {
  final int ownerId;
  final int groupId;
  final String groupNo;
  final String name;
  final String avatar;
  final int memberCount;
  final String rawJson;
  final DateTime updatedAt;
  const CachedGroup({
    required this.ownerId,
    required this.groupId,
    required this.groupNo,
    required this.name,
    required this.avatar,
    required this.memberCount,
    required this.rawJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<int>(ownerId);
    map['group_id'] = Variable<int>(groupId);
    map['group_no'] = Variable<String>(groupNo);
    map['name'] = Variable<String>(name);
    map['avatar'] = Variable<String>(avatar);
    map['member_count'] = Variable<int>(memberCount);
    map['raw_json'] = Variable<String>(rawJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedGroupsCompanion toCompanion(bool nullToAbsent) {
    return CachedGroupsCompanion(
      ownerId: Value(ownerId),
      groupId: Value(groupId),
      groupNo: Value(groupNo),
      name: Value(name),
      avatar: Value(avatar),
      memberCount: Value(memberCount),
      rawJson: Value(rawJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedGroup(
      ownerId: serializer.fromJson<int>(json['ownerId']),
      groupId: serializer.fromJson<int>(json['groupId']),
      groupNo: serializer.fromJson<String>(json['groupNo']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String>(json['avatar']),
      memberCount: serializer.fromJson<int>(json['memberCount']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<int>(ownerId),
      'groupId': serializer.toJson<int>(groupId),
      'groupNo': serializer.toJson<String>(groupNo),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String>(avatar),
      'memberCount': serializer.toJson<int>(memberCount),
      'rawJson': serializer.toJson<String>(rawJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedGroup copyWith({
    int? ownerId,
    int? groupId,
    String? groupNo,
    String? name,
    String? avatar,
    int? memberCount,
    String? rawJson,
    DateTime? updatedAt,
  }) => CachedGroup(
    ownerId: ownerId ?? this.ownerId,
    groupId: groupId ?? this.groupId,
    groupNo: groupNo ?? this.groupNo,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    memberCount: memberCount ?? this.memberCount,
    rawJson: rawJson ?? this.rawJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedGroup copyWithCompanion(CachedGroupsCompanion data) {
    return CachedGroup(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      groupNo: data.groupNo.present ? data.groupNo.value : this.groupNo,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      memberCount: data.memberCount.present
          ? data.memberCount.value
          : this.memberCount,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedGroup(')
          ..write('ownerId: $ownerId, ')
          ..write('groupId: $groupId, ')
          ..write('groupNo: $groupNo, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('memberCount: $memberCount, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    groupId,
    groupNo,
    name,
    avatar,
    memberCount,
    rawJson,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedGroup &&
          other.ownerId == this.ownerId &&
          other.groupId == this.groupId &&
          other.groupNo == this.groupNo &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.memberCount == this.memberCount &&
          other.rawJson == this.rawJson &&
          other.updatedAt == this.updatedAt);
}

class CachedGroupsCompanion extends UpdateCompanion<CachedGroup> {
  final Value<int> ownerId;
  final Value<int> groupId;
  final Value<String> groupNo;
  final Value<String> name;
  final Value<String> avatar;
  final Value<int> memberCount;
  final Value<String> rawJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedGroupsCompanion({
    this.ownerId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.groupNo = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedGroupsCompanion.insert({
    required int ownerId,
    required int groupId,
    this.groupNo = const Value.absent(),
    required String name,
    this.avatar = const Value.absent(),
    this.memberCount = const Value.absent(),
    required String rawJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       groupId = Value(groupId),
       name = Value(name),
       rawJson = Value(rawJson),
       updatedAt = Value(updatedAt);
  static Insertable<CachedGroup> custom({
    Expression<int>? ownerId,
    Expression<int>? groupId,
    Expression<String>? groupNo,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<int>? memberCount,
    Expression<String>? rawJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (groupId != null) 'group_id': groupId,
      if (groupNo != null) 'group_no': groupNo,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (memberCount != null) 'member_count': memberCount,
      if (rawJson != null) 'raw_json': rawJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedGroupsCompanion copyWith({
    Value<int>? ownerId,
    Value<int>? groupId,
    Value<String>? groupNo,
    Value<String>? name,
    Value<String>? avatar,
    Value<int>? memberCount,
    Value<String>? rawJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedGroupsCompanion(
      ownerId: ownerId ?? this.ownerId,
      groupId: groupId ?? this.groupId,
      groupNo: groupNo ?? this.groupNo,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      memberCount: memberCount ?? this.memberCount,
      rawJson: rawJson ?? this.rawJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<int>(ownerId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (groupNo.present) {
      map['group_no'] = Variable<String>(groupNo.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (memberCount.present) {
      map['member_count'] = Variable<int>(memberCount.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedGroupsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('groupId: $groupId, ')
          ..write('groupNo: $groupNo, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('memberCount: $memberCount, ')
          ..write('rawJson: $rawJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedApiResponsesTable extends CachedApiResponses
    with TableInfo<$CachedApiResponsesTable, CachedApiResponse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedApiResponsesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _namespaceMeta = const VerificationMeta(
    'namespace',
  );
  @override
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
    'namespace',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responseJsonMeta = const VerificationMeta(
    'responseJson',
  );
  @override
  late final GeneratedColumn<String> responseJson = GeneratedColumn<String>(
    'response_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    namespace,
    cacheKey,
    path,
    responseJson,
    updatedAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_api_responses';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedApiResponse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('namespace')) {
      context.handle(
        _namespaceMeta,
        namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta),
      );
    } else if (isInserting) {
      context.missing(_namespaceMeta);
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('response_json')) {
      context.handle(
        _responseJsonMeta,
        responseJson.isAcceptableOrUnknown(
          data['response_json']!,
          _responseJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_responseJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {namespace, cacheKey};
  @override
  CachedApiResponse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedApiResponse(
      namespace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}namespace'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      responseJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
    );
  }

  @override
  $CachedApiResponsesTable createAlias(String alias) {
    return $CachedApiResponsesTable(attachedDatabase, alias);
  }
}

class CachedApiResponse extends DataClass
    implements Insertable<CachedApiResponse> {
  final String namespace;
  final String cacheKey;
  final String path;
  final String responseJson;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  const CachedApiResponse({
    required this.namespace,
    required this.cacheKey,
    required this.path,
    required this.responseJson,
    required this.updatedAt,
    this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['namespace'] = Variable<String>(namespace);
    map['cache_key'] = Variable<String>(cacheKey);
    map['path'] = Variable<String>(path);
    map['response_json'] = Variable<String>(responseJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    return map;
  }

  CachedApiResponsesCompanion toCompanion(bool nullToAbsent) {
    return CachedApiResponsesCompanion(
      namespace: Value(namespace),
      cacheKey: Value(cacheKey),
      path: Value(path),
      responseJson: Value(responseJson),
      updatedAt: Value(updatedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory CachedApiResponse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedApiResponse(
      namespace: serializer.fromJson<String>(json['namespace']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      path: serializer.fromJson<String>(json['path']),
      responseJson: serializer.fromJson<String>(json['responseJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'namespace': serializer.toJson<String>(namespace),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'path': serializer.toJson<String>(path),
      'responseJson': serializer.toJson<String>(responseJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
    };
  }

  CachedApiResponse copyWith({
    String? namespace,
    String? cacheKey,
    String? path,
    String? responseJson,
    DateTime? updatedAt,
    Value<DateTime?> expiresAt = const Value.absent(),
  }) => CachedApiResponse(
    namespace: namespace ?? this.namespace,
    cacheKey: cacheKey ?? this.cacheKey,
    path: path ?? this.path,
    responseJson: responseJson ?? this.responseJson,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
  );
  CachedApiResponse copyWithCompanion(CachedApiResponsesCompanion data) {
    return CachedApiResponse(
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      path: data.path.present ? data.path.value : this.path,
      responseJson: data.responseJson.present
          ? data.responseJson.value
          : this.responseJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedApiResponse(')
          ..write('namespace: $namespace, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('path: $path, ')
          ..write('responseJson: $responseJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    namespace,
    cacheKey,
    path,
    responseJson,
    updatedAt,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedApiResponse &&
          other.namespace == this.namespace &&
          other.cacheKey == this.cacheKey &&
          other.path == this.path &&
          other.responseJson == this.responseJson &&
          other.updatedAt == this.updatedAt &&
          other.expiresAt == this.expiresAt);
}

class CachedApiResponsesCompanion extends UpdateCompanion<CachedApiResponse> {
  final Value<String> namespace;
  final Value<String> cacheKey;
  final Value<String> path;
  final Value<String> responseJson;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> expiresAt;
  final Value<int> rowid;
  const CachedApiResponsesCompanion({
    this.namespace = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.path = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedApiResponsesCompanion.insert({
    required String namespace,
    required String cacheKey,
    required String path,
    required String responseJson,
    required DateTime updatedAt,
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : namespace = Value(namespace),
       cacheKey = Value(cacheKey),
       path = Value(path),
       responseJson = Value(responseJson),
       updatedAt = Value(updatedAt);
  static Insertable<CachedApiResponse> custom({
    Expression<String>? namespace,
    Expression<String>? cacheKey,
    Expression<String>? path,
    Expression<String>? responseJson,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (namespace != null) 'namespace': namespace,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (path != null) 'path': path,
      if (responseJson != null) 'response_json': responseJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedApiResponsesCompanion copyWith({
    Value<String>? namespace,
    Value<String>? cacheKey,
    Value<String>? path,
    Value<String>? responseJson,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? expiresAt,
    Value<int>? rowid,
  }) {
    return CachedApiResponsesCompanion(
      namespace: namespace ?? this.namespace,
      cacheKey: cacheKey ?? this.cacheKey,
      path: path ?? this.path,
      responseJson: responseJson ?? this.responseJson,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (responseJson.present) {
      map['response_json'] = Variable<String>(responseJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedApiResponsesCompanion(')
          ..write('namespace: $namespace, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('path: $path, ')
          ..write('responseJson: $responseJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $CachedConversationsTable cachedConversations =
      $CachedConversationsTable(this);
  late final $CachedMessagesTable cachedMessages = $CachedMessagesTable(this);
  late final $CachedProfilesTable cachedProfiles = $CachedProfilesTable(this);
  late final $CachedGroupsTable cachedGroups = $CachedGroupsTable(this);
  late final $CachedApiResponsesTable cachedApiResponses =
      $CachedApiResponsesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedConversations,
    cachedMessages,
    cachedProfiles,
    cachedGroups,
    cachedApiResponses,
  ];
}

typedef $$CachedConversationsTableCreateCompanionBuilder =
    CachedConversationsCompanion Function({
      required int ownerId,
      required String conversationKey,
      required String kind,
      required int targetId,
      required String title,
      required String avatar,
      required String preview,
      Value<DateTime?> lastMessageAt,
      Value<int> unread,
      Value<bool> pinned,
      Value<bool> muted,
      required String rawJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedConversationsTableUpdateCompanionBuilder =
    CachedConversationsCompanion Function({
      Value<int> ownerId,
      Value<String> conversationKey,
      Value<String> kind,
      Value<int> targetId,
      Value<String> title,
      Value<String> avatar,
      Value<String> preview,
      Value<DateTime?> lastMessageAt,
      Value<int> unread,
      Value<bool> pinned,
      Value<bool> muted,
      Value<String> rawJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedConversationsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedConversationsTable> {
  $$CachedConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedConversationsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedConversationsTable> {
  $$CachedConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedConversationsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedConversationsTable> {
  $$CachedConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unread =>
      $composableBuilder(column: $table.unread, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get muted =>
      $composableBuilder(column: $table.muted, builder: (column) => column);

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedConversationsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedConversationsTable,
          CachedConversation,
          $$CachedConversationsTableFilterComposer,
          $$CachedConversationsTableOrderingComposer,
          $$CachedConversationsTableAnnotationComposer,
          $$CachedConversationsTableCreateCompanionBuilder,
          $$CachedConversationsTableUpdateCompanionBuilder,
          (
            CachedConversation,
            BaseReferences<
              _$CacheDatabase,
              $CachedConversationsTable,
              CachedConversation
            >,
          ),
          CachedConversation,
          PrefetchHooks Function()
        > {
  $$CachedConversationsTableTableManager(
    _$CacheDatabase db,
    $CachedConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedConversationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedConversationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> ownerId = const Value.absent(),
                Value<String> conversationKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> targetId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> preview = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<int> unread = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedConversationsCompanion(
                ownerId: ownerId,
                conversationKey: conversationKey,
                kind: kind,
                targetId: targetId,
                title: title,
                avatar: avatar,
                preview: preview,
                lastMessageAt: lastMessageAt,
                unread: unread,
                pinned: pinned,
                muted: muted,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int ownerId,
                required String conversationKey,
                required String kind,
                required int targetId,
                required String title,
                required String avatar,
                required String preview,
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<int> unread = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                required String rawJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedConversationsCompanion.insert(
                ownerId: ownerId,
                conversationKey: conversationKey,
                kind: kind,
                targetId: targetId,
                title: title,
                avatar: avatar,
                preview: preview,
                lastMessageAt: lastMessageAt,
                unread: unread,
                pinned: pinned,
                muted: muted,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedConversationsTable,
      CachedConversation,
      $$CachedConversationsTableFilterComposer,
      $$CachedConversationsTableOrderingComposer,
      $$CachedConversationsTableAnnotationComposer,
      $$CachedConversationsTableCreateCompanionBuilder,
      $$CachedConversationsTableUpdateCompanionBuilder,
      (
        CachedConversation,
        BaseReferences<
          _$CacheDatabase,
          $CachedConversationsTable,
          CachedConversation
        >,
      ),
      CachedConversation,
      PrefetchHooks Function()
    >;
typedef $$CachedMessagesTableCreateCompanionBuilder =
    CachedMessagesCompanion Function({
      required int ownerId,
      required String conversationKey,
      required String messageKey,
      Value<int> messageId,
      Value<String> clientMsgNo,
      Value<int> fromUserId,
      Value<int> toUserId,
      Value<String> fromUid,
      Value<String> toUid,
      required String msgType,
      required String contentJson,
      required String rawJson,
      required DateTime createdAt,
      Value<bool> isMe,
      Value<bool> read,
      Value<DateTime?> readAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedMessagesTableUpdateCompanionBuilder =
    CachedMessagesCompanion Function({
      Value<int> ownerId,
      Value<String> conversationKey,
      Value<String> messageKey,
      Value<int> messageId,
      Value<String> clientMsgNo,
      Value<int> fromUserId,
      Value<int> toUserId,
      Value<String> fromUid,
      Value<String> toUid,
      Value<String> msgType,
      Value<String> contentJson,
      Value<String> rawJson,
      Value<DateTime> createdAt,
      Value<bool> isMe,
      Value<bool> read,
      Value<DateTime?> readAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedMessagesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageKey => $composableBuilder(
    column: $table.messageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientMsgNo => $composableBuilder(
    column: $table.clientMsgNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toUserId => $composableBuilder(
    column: $table.toUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromUid => $composableBuilder(
    column: $table.fromUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toUid => $composableBuilder(
    column: $table.toUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get msgType => $composableBuilder(
    column: $table.msgType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMe => $composableBuilder(
    column: $table.isMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMessagesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageKey => $composableBuilder(
    column: $table.messageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientMsgNo => $composableBuilder(
    column: $table.clientMsgNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toUserId => $composableBuilder(
    column: $table.toUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromUid => $composableBuilder(
    column: $table.fromUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toUid => $composableBuilder(
    column: $table.toUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get msgType => $composableBuilder(
    column: $table.msgType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMe => $composableBuilder(
    column: $table.isMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMessagesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get conversationKey => $composableBuilder(
    column: $table.conversationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageKey => $composableBuilder(
    column: $table.messageKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get clientMsgNo => $composableBuilder(
    column: $table.clientMsgNo,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fromUserId => $composableBuilder(
    column: $table.fromUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get toUserId =>
      $composableBuilder(column: $table.toUserId, builder: (column) => column);

  GeneratedColumn<String> get fromUid =>
      $composableBuilder(column: $table.fromUid, builder: (column) => column);

  GeneratedColumn<String> get toUid =>
      $composableBuilder(column: $table.toUid, builder: (column) => column);

  GeneratedColumn<String> get msgType =>
      $composableBuilder(column: $table.msgType, builder: (column) => column);

  GeneratedColumn<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isMe =>
      $composableBuilder(column: $table.isMe, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedMessagesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedMessagesTable,
          CachedMessage,
          $$CachedMessagesTableFilterComposer,
          $$CachedMessagesTableOrderingComposer,
          $$CachedMessagesTableAnnotationComposer,
          $$CachedMessagesTableCreateCompanionBuilder,
          $$CachedMessagesTableUpdateCompanionBuilder,
          (
            CachedMessage,
            BaseReferences<
              _$CacheDatabase,
              $CachedMessagesTable,
              CachedMessage
            >,
          ),
          CachedMessage,
          PrefetchHooks Function()
        > {
  $$CachedMessagesTableTableManager(
    _$CacheDatabase db,
    $CachedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> ownerId = const Value.absent(),
                Value<String> conversationKey = const Value.absent(),
                Value<String> messageKey = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<String> clientMsgNo = const Value.absent(),
                Value<int> fromUserId = const Value.absent(),
                Value<int> toUserId = const Value.absent(),
                Value<String> fromUid = const Value.absent(),
                Value<String> toUid = const Value.absent(),
                Value<String> msgType = const Value.absent(),
                Value<String> contentJson = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> isMe = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion(
                ownerId: ownerId,
                conversationKey: conversationKey,
                messageKey: messageKey,
                messageId: messageId,
                clientMsgNo: clientMsgNo,
                fromUserId: fromUserId,
                toUserId: toUserId,
                fromUid: fromUid,
                toUid: toUid,
                msgType: msgType,
                contentJson: contentJson,
                rawJson: rawJson,
                createdAt: createdAt,
                isMe: isMe,
                read: read,
                readAt: readAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int ownerId,
                required String conversationKey,
                required String messageKey,
                Value<int> messageId = const Value.absent(),
                Value<String> clientMsgNo = const Value.absent(),
                Value<int> fromUserId = const Value.absent(),
                Value<int> toUserId = const Value.absent(),
                Value<String> fromUid = const Value.absent(),
                Value<String> toUid = const Value.absent(),
                required String msgType,
                required String contentJson,
                required String rawJson,
                required DateTime createdAt,
                Value<bool> isMe = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion.insert(
                ownerId: ownerId,
                conversationKey: conversationKey,
                messageKey: messageKey,
                messageId: messageId,
                clientMsgNo: clientMsgNo,
                fromUserId: fromUserId,
                toUserId: toUserId,
                fromUid: fromUid,
                toUid: toUid,
                msgType: msgType,
                contentJson: contentJson,
                rawJson: rawJson,
                createdAt: createdAt,
                isMe: isMe,
                read: read,
                readAt: readAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedMessagesTable,
      CachedMessage,
      $$CachedMessagesTableFilterComposer,
      $$CachedMessagesTableOrderingComposer,
      $$CachedMessagesTableAnnotationComposer,
      $$CachedMessagesTableCreateCompanionBuilder,
      $$CachedMessagesTableUpdateCompanionBuilder,
      (
        CachedMessage,
        BaseReferences<_$CacheDatabase, $CachedMessagesTable, CachedMessage>,
      ),
      CachedMessage,
      PrefetchHooks Function()
    >;
typedef $$CachedProfilesTableCreateCompanionBuilder =
    CachedProfilesCompanion Function({
      required int ownerId,
      required int userId,
      Value<String> username,
      required String nickname,
      Value<String> avatar,
      Value<String> title,
      Value<String> titleColor,
      required String rawJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<int> ownerId,
      Value<int> userId,
      Value<String> username,
      Value<String> nickname,
      Value<String> avatar,
      Value<String> title,
      Value<String> titleColor,
      Value<String> rawJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedProfilesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleColor => $composableBuilder(
    column: $table.titleColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleColor => $composableBuilder(
    column: $table.titleColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleColor => $composableBuilder(
    column: $table.titleColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedProfilesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedProfilesTable,
          CachedProfile,
          $$CachedProfilesTableFilterComposer,
          $$CachedProfilesTableOrderingComposer,
          $$CachedProfilesTableAnnotationComposer,
          $$CachedProfilesTableCreateCompanionBuilder,
          $$CachedProfilesTableUpdateCompanionBuilder,
          (
            CachedProfile,
            BaseReferences<
              _$CacheDatabase,
              $CachedProfilesTable,
              CachedProfile
            >,
          ),
          CachedProfile,
          PrefetchHooks Function()
        > {
  $$CachedProfilesTableTableManager(
    _$CacheDatabase db,
    $CachedProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> ownerId = const Value.absent(),
                Value<int> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> nickname = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleColor = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                ownerId: ownerId,
                userId: userId,
                username: username,
                nickname: nickname,
                avatar: avatar,
                title: title,
                titleColor: titleColor,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int ownerId,
                required int userId,
                Value<String> username = const Value.absent(),
                required String nickname,
                Value<String> avatar = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleColor = const Value.absent(),
                required String rawJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                ownerId: ownerId,
                userId: userId,
                username: username,
                nickname: nickname,
                avatar: avatar,
                title: title,
                titleColor: titleColor,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedProfilesTable,
      CachedProfile,
      $$CachedProfilesTableFilterComposer,
      $$CachedProfilesTableOrderingComposer,
      $$CachedProfilesTableAnnotationComposer,
      $$CachedProfilesTableCreateCompanionBuilder,
      $$CachedProfilesTableUpdateCompanionBuilder,
      (
        CachedProfile,
        BaseReferences<_$CacheDatabase, $CachedProfilesTable, CachedProfile>,
      ),
      CachedProfile,
      PrefetchHooks Function()
    >;
typedef $$CachedGroupsTableCreateCompanionBuilder =
    CachedGroupsCompanion Function({
      required int ownerId,
      required int groupId,
      Value<String> groupNo,
      required String name,
      Value<String> avatar,
      Value<int> memberCount,
      required String rawJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedGroupsTableUpdateCompanionBuilder =
    CachedGroupsCompanion Function({
      Value<int> ownerId,
      Value<int> groupId,
      Value<String> groupNo,
      Value<String> name,
      Value<String> avatar,
      Value<int> memberCount,
      Value<String> rawJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedGroupsTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedGroupsTable> {
  $$CachedGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupNo => $composableBuilder(
    column: $table.groupNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedGroupsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedGroupsTable> {
  $$CachedGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupNo => $composableBuilder(
    column: $table.groupNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedGroupsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedGroupsTable> {
  $$CachedGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get groupNo =>
      $composableBuilder(column: $table.groupNo, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedGroupsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedGroupsTable,
          CachedGroup,
          $$CachedGroupsTableFilterComposer,
          $$CachedGroupsTableOrderingComposer,
          $$CachedGroupsTableAnnotationComposer,
          $$CachedGroupsTableCreateCompanionBuilder,
          $$CachedGroupsTableUpdateCompanionBuilder,
          (
            CachedGroup,
            BaseReferences<_$CacheDatabase, $CachedGroupsTable, CachedGroup>,
          ),
          CachedGroup,
          PrefetchHooks Function()
        > {
  $$CachedGroupsTableTableManager(_$CacheDatabase db, $CachedGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> ownerId = const Value.absent(),
                Value<int> groupId = const Value.absent(),
                Value<String> groupNo = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedGroupsCompanion(
                ownerId: ownerId,
                groupId: groupId,
                groupNo: groupNo,
                name: name,
                avatar: avatar,
                memberCount: memberCount,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int ownerId,
                required int groupId,
                Value<String> groupNo = const Value.absent(),
                required String name,
                Value<String> avatar = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                required String rawJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedGroupsCompanion.insert(
                ownerId: ownerId,
                groupId: groupId,
                groupNo: groupNo,
                name: name,
                avatar: avatar,
                memberCount: memberCount,
                rawJson: rawJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedGroupsTable,
      CachedGroup,
      $$CachedGroupsTableFilterComposer,
      $$CachedGroupsTableOrderingComposer,
      $$CachedGroupsTableAnnotationComposer,
      $$CachedGroupsTableCreateCompanionBuilder,
      $$CachedGroupsTableUpdateCompanionBuilder,
      (
        CachedGroup,
        BaseReferences<_$CacheDatabase, $CachedGroupsTable, CachedGroup>,
      ),
      CachedGroup,
      PrefetchHooks Function()
    >;
typedef $$CachedApiResponsesTableCreateCompanionBuilder =
    CachedApiResponsesCompanion Function({
      required String namespace,
      required String cacheKey,
      required String path,
      required String responseJson,
      required DateTime updatedAt,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });
typedef $$CachedApiResponsesTableUpdateCompanionBuilder =
    CachedApiResponsesCompanion Function({
      Value<String> namespace,
      Value<String> cacheKey,
      Value<String> path,
      Value<String> responseJson,
      Value<DateTime> updatedAt,
      Value<DateTime?> expiresAt,
      Value<int> rowid,
    });

class $$CachedApiResponsesTableFilterComposer
    extends Composer<_$CacheDatabase, $CachedApiResponsesTable> {
  $$CachedApiResponsesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedApiResponsesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CachedApiResponsesTable> {
  $$CachedApiResponsesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedApiResponsesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CachedApiResponsesTable> {
  $$CachedApiResponsesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get namespace =>
      $composableBuilder(column: $table.namespace, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get responseJson => $composableBuilder(
    column: $table.responseJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$CachedApiResponsesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CachedApiResponsesTable,
          CachedApiResponse,
          $$CachedApiResponsesTableFilterComposer,
          $$CachedApiResponsesTableOrderingComposer,
          $$CachedApiResponsesTableAnnotationComposer,
          $$CachedApiResponsesTableCreateCompanionBuilder,
          $$CachedApiResponsesTableUpdateCompanionBuilder,
          (
            CachedApiResponse,
            BaseReferences<
              _$CacheDatabase,
              $CachedApiResponsesTable,
              CachedApiResponse
            >,
          ),
          CachedApiResponse,
          PrefetchHooks Function()
        > {
  $$CachedApiResponsesTableTableManager(
    _$CacheDatabase db,
    $CachedApiResponsesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedApiResponsesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedApiResponsesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedApiResponsesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> namespace = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> responseJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedApiResponsesCompanion(
                namespace: namespace,
                cacheKey: cacheKey,
                path: path,
                responseJson: responseJson,
                updatedAt: updatedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String namespace,
                required String cacheKey,
                required String path,
                required String responseJson,
                required DateTime updatedAt,
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedApiResponsesCompanion.insert(
                namespace: namespace,
                cacheKey: cacheKey,
                path: path,
                responseJson: responseJson,
                updatedAt: updatedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedApiResponsesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CachedApiResponsesTable,
      CachedApiResponse,
      $$CachedApiResponsesTableFilterComposer,
      $$CachedApiResponsesTableOrderingComposer,
      $$CachedApiResponsesTableAnnotationComposer,
      $$CachedApiResponsesTableCreateCompanionBuilder,
      $$CachedApiResponsesTableUpdateCompanionBuilder,
      (
        CachedApiResponse,
        BaseReferences<
          _$CacheDatabase,
          $CachedApiResponsesTable,
          CachedApiResponse
        >,
      ),
      CachedApiResponse,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$CachedConversationsTableTableManager get cachedConversations =>
      $$CachedConversationsTableTableManager(_db, _db.cachedConversations);
  $$CachedMessagesTableTableManager get cachedMessages =>
      $$CachedMessagesTableTableManager(_db, _db.cachedMessages);
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
  $$CachedGroupsTableTableManager get cachedGroups =>
      $$CachedGroupsTableTableManager(_db, _db.cachedGroups);
  $$CachedApiResponsesTableTableManager get cachedApiResponses =>
      $$CachedApiResponsesTableTableManager(_db, _db.cachedApiResponses);
}

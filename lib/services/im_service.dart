import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:wukongimfluttersdk/common/options.dart';
import 'package:wukongimfluttersdk/entity/channel.dart';
import 'package:wukongimfluttersdk/entity/cmd.dart';
import 'package:wukongimfluttersdk/entity/msg.dart';
import 'package:wukongimfluttersdk/model/wk_message_content.dart';
import 'package:wukongimfluttersdk/model/wk_text_content.dart';
import 'package:wukongimfluttersdk/type/const.dart';
import 'package:wukongimfluttersdk/wkim.dart';

import '../core/app_config.dart';
import '../core/cache/app_cache_store.dart';
import '../core/events/app_event_bus.dart';
import '../core/app_logger.dart';
import '../models/im_models.dart';
import '../models/call_signal.dart';
import 'client_device_context.dart';

Map<String, dynamic> normalizeFriendEventContent(Map<String, dynamic> payload) {
  final content = <String, dynamic>{};

  void absorb(Object? value) {
    if (value is Map<String, dynamic>) {
      content.addAll(value);
      return;
    }
    if (value is Map) {
      content.addAll(Map<String, dynamic>.from(value));
      return;
    }
    if (value is String) {
      final decoded = _friendJsonMap(value);
      if (decoded != null) content.addAll(decoded);
    }
  }

  absorb(payload['content']);
  final text = content['text'];
  if (text is String) absorb(text);
  for (final key in const [
    'action',
    'event',
    'user_id',
    'from_user_id',
    'to_user_id',
    'nickname',
    'avatar',
    'message',
    'group_id',
    'group_no',
    'group_name',
    'groupName',
    'group_avatar',
    'groupAvatar',
    'member_count',
    'notification_id',
    'notification_type',
    'title',
    'postid',
    'wallet_event',
    'wallet_locked',
    'wallet_locked_reason',
    'profile_event',
    'changed_keys',
    'username',
    'moment_id',
    'comment_id',
    'actor_id',
    'moment_event',
    'audit_status',
  ]) {
    final value = payload[key];
    if (value != null && '$value'.trim().isNotEmpty) {
      content.putIfAbsent(key, () => value);
    }
  }
  return content;
}

Map<String, dynamic>? _friendJsonMap(String text) {
  try {
    final decoded = jsonDecode(text.trim());
    if (decoded is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded);
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

class PresenceStatus {
  final int userId;
  final String uid;
  final bool online;
  final String device;
  final DateTime time;
  final Map<String, dynamic> raw;

  const PresenceStatus({
    required this.userId,
    required this.uid,
    required this.online,
    required this.device,
    required this.time,
    required this.raw,
  });

  factory PresenceStatus.fromPayload(Map<String, dynamic> p) {
    final uid = '${p['uid'] ?? p['from_uid'] ?? ''}';
    return PresenceStatus(
      userId:
          int.tryParse('${p['user_id'] ?? p['from_user_id'] ?? 0}') ??
          _userIdFromUidStatic(uid),
      uid: uid,
      online:
          p['online'] == true ||
          '${p['online']}'.toLowerCase() == 'true' ||
          '${p['event']}' == 'online',
      device:
          '${p['device'] ?? p['platform'] ?? p['terminal'] ?? p['client'] ?? p['device_flag'] ?? ''}',
      time: DateTime.tryParse('${p['time'] ?? ''}') ?? DateTime.now(),
      raw: p,
    );
  }

  static int _userIdFromUidStatic(String uid) {
    if (uid.contains('_')) return int.tryParse(uid.split('_').last) ?? 0;
    return int.tryParse(uid) ?? 0;
  }
}

class _PendingConnectionWaiter {
  final Completer<void> completer;
  Timer? timer;

  _PendingConnectionWaiter(this.completer);
}

class TypingEvent {
  final int fromUserId;
  final int toUserId;
  final bool active;
  final DateTime time;
  final Map<String, dynamic> raw;

  const TypingEvent({
    required this.fromUserId,
    required this.toUserId,
    required this.active,
    required this.time,
    required this.raw,
  });

  factory TypingEvent.fromPayload(Map<String, dynamic> payload) {
    final content = payload['content'] is Map
        ? Map<String, dynamic>.from(payload['content'])
        : const <String, dynamic>{};
    final event = '${content['event'] ?? payload['event'] ?? ''}'
        .trim()
        .toLowerCase();
    final activeValue = content['active'] ?? payload['active'];
    return TypingEvent(
      fromUserId:
          int.tryParse(
            '${payload['from_user_id'] ?? content['from_user_id'] ?? 0}',
          ) ??
          0,
      toUserId:
          int.tryParse(
            '${payload['to_user_id'] ?? content['to_user_id'] ?? 0}',
          ) ??
          0,
      active:
          event == 'typing' ||
          event == 'start' ||
          activeValue == true ||
          '$activeValue'.toLowerCase() == 'true',
      time:
          DateTime.tryParse(
            '${payload['create_time'] ?? content['time'] ?? ''}',
          ) ??
          DateTime.now(),
      raw: payload,
    );
  }
}

class ReadReceipt {
  final int fromUserId;
  final int toUserId;
  final DateTime? readAt;
  final Set<int> messageIds;
  final Set<String> messageKeys;
  final Map<String, dynamic> raw;

  const ReadReceipt({
    required this.fromUserId,
    required this.toUserId,
    required this.readAt,
    required this.messageIds,
    required this.messageKeys,
    required this.raw,
  });

  factory ReadReceipt.fromPayload(Map<String, dynamic> payload) {
    final content = payload['content'] is Map
        ? Map<String, dynamic>.from(payload['content'])
        : const <String, dynamic>{};
    return ReadReceipt(
      fromUserId:
          int.tryParse(
            '${payload['from_user_id'] ?? content['reader_user_id'] ?? 0}',
          ) ??
          0,
      toUserId:
          int.tryParse(
            '${payload['to_user_id'] ?? content['to_user_id'] ?? 0}',
          ) ??
          0,
      readAt: DateTime.tryParse(
        '${content['last_read_at'] ?? content['read_at'] ?? payload['create_time'] ?? ''}',
      ),
      messageIds: _intSet(content['message_ids'] ?? content['message_id']),
      messageKeys: _stringSet(
        content['message_keys'] ?? content['message_key'],
      ),
      raw: payload,
    );
  }

  static Set<int> _intSet(Object? value) {
    if (value is Iterable) {
      return value
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toSet();
    }
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return <int>{};
    return text
        .split(',')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toSet();
  }

  static Set<String> _stringSet(Object? value) {
    if (value is Iterable) {
      return value
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty && e != 'null')
          .toSet();
    }
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return <String>{};
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }
}

class ImService {
  final _messageController = StreamController<UnifiedMessage>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _friendController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<PresenceStatus>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _readReceiptController = StreamController<ReadReceipt>.broadcast();
  final _connectionController = StreamController<void>.broadcast();
  final List<_PendingConnectionWaiter> _connectionWaiters = [];
  Future<void>? _connectFuture;
  final _recentMessageKeys = HashSet<String>();
  final _recentMessageQueue = Queue<String>();
  final _recentSemanticAt = <String, int>{};
  final _recentSemanticQueue = Queue<String>();
  bool _customMessageTypesRegistered = false;
  bool connected = false;
  bool connecting = false;
  bool _listenersRegistered = false;
  String? connectionError;
  String? _lastTcpAddr;
  String? _lastToken;
  String? _lastUid;
  String? _currentDeviceId;
  String? _lastConnectionLogKey;
  DateTime? _lastConnectionLogAt;
  Timer? _transientReconnectTimer;
  bool _sdkConnectStarting = false;
  int _myId = 0;

  static String uidForUser(int userId) => '${AppConfig.appId}_$userId';

  bool get isSocketConnected => connected;
  bool get isReconnecting => connected && connecting;
  bool isConnectedForUser(int userId) =>
      connected && _lastUid == uidForUser(userId);
  String? get currentDeviceId => _currentDeviceId;
  String get connectionSnapshot =>
      'uid=${_lastUid ?? '-'} myId=$_myId connected=$connected connecting=$connecting '
      'starting=$_sdkConnectStarting tcp=${_safeAddr(_lastTcpAddr)} '
      'device=${_currentDeviceId ?? '-'} error=${connectionError ?? '-'}';

  Stream<UnifiedMessage> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get calls => _callController.stream;
  Stream<Map<String, dynamic>> get friendEvents => _friendController.stream;
  Stream<PresenceStatus> get presences => _presenceController.stream;
  Stream<TypingEvent> get typingEvents => _typingController.stream;
  Stream<ReadReceipt> get readReceipts => _readReceiptController.stream;
  Stream<void> get connectionChanges => _connectionController.stream;

  void _notifyConnection() {
    if (!_connectionController.isClosed) _connectionController.add(null);
    AppEventBus.emit(
      ImConnectionChangedEvent(
        connected: connected,
        connecting: connecting,
        error: connectionError ?? '',
      ),
    );
  }

  void _setConnection({bool? connected, bool? connecting, String? error}) {
    if (connected != null) this.connected = connected;
    if (connecting != null) this.connecting = connecting;
    connectionError = error;
    if (this.connected && !this.connecting) {
      _flushConnectionWaiters();
    } else if (error != null && error.isNotEmpty && this.connected == false) {
      _failConnectionWaiters(error);
    }
    _notifyConnection();
  }

  void _flushConnectionWaiters() {
    if (_connectionWaiters.isEmpty) return;
    final waiters = List<_PendingConnectionWaiter>.from(_connectionWaiters);
    _connectionWaiters.clear();
    for (final waiter in waiters) {
      waiter.timer?.cancel();
      if (!waiter.completer.isCompleted) waiter.completer.complete();
    }
  }

  void _failConnectionWaiters(String error) {
    if (_connectionWaiters.isEmpty) return;
    final waiters = List<_PendingConnectionWaiter>.from(_connectionWaiters);
    _connectionWaiters.clear();
    for (final waiter in waiters) {
      waiter.timer?.cancel();
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(StateError(error));
      }
    }
  }

  Future<void> connect({
    required ImConnectInfo info,
    required int myId,
    bool waitUntilReady = false,
    Duration readyTimeout = const Duration(seconds: 12),
  }) async {
    if (connected && _lastUid == info.uid && !connecting) {
      _lastTcpAddr = info.tcpAddr;
      _lastToken = info.token;
      AppLogger.im('复用已连接IM会话 uid=${info.uid} tcp=${_safeAddr(info.tcpAddr)}');
      return;
    }
    if (connected && _lastUid == info.uid && connecting) {
      _lastTcpAddr = info.tcpAddr;
      _lastToken = info.token;
      AppLogger.im('等待已有IM连接恢复 uid=${info.uid} tcp=${_safeAddr(info.tcpAddr)}');
      await waitForConnected(timeout: readyTimeout, requireStable: true);
      return;
    }
    if (_connectFuture != null) {
      AppLogger.im('等待正在进行的IM连接 $connectionSnapshot');
      await _connectFuture!;
    } else {
      _setConnection(connected: false, connecting: true, error: null);
      AppLogger.im(
        '开始IM连接 uid=${info.uid} myId=$myId tcp=${_safeAddr(info.tcpAddr)}',
      );
      _connectFuture = _connectInternal(info: info, myId: myId).whenComplete(
        () {
          _connectFuture = null;
        },
      );
      await _connectFuture!;
    }
    if (waitUntilReady && !connected) {
      await waitForConnected(timeout: readyTimeout);
    }
  }

  Future<void> _connectInternal({
    required ImConnectInfo info,
    required int myId,
  }) async {
    _myId = myId;
    _lastTcpAddr = info.tcpAddr;
    _lastToken = info.token;
    _lastUid = info.uid;
    _setConnection(connected: false, connecting: true, error: null);
    final device = ClientDeviceContext.current();
    final deviceId = await device.persistentDeviceId();
    _currentDeviceId = deviceId;

    if (info.tcpAddr.trim().isEmpty) {
      AppLogger.error('IM', 'IM连接地址为空', data: {'uid': info.uid, 'myId': myId});
      _setConnection(connected: false, connecting: false, error: 'IM TCP地址为空');
      throw StateError('IM TCP地址为空');
    }
    final options = Options.newDefault(info.uid, info.token);
    final addr = info.tcpAddr.trim();
    options.addr = addr;
    options.getAddr = (complete) async => complete(addr);
    options.deviceFlag = device.deviceFlag;
    options.debug = true;
    await WKIM.shared.setup(options);
    _registerCustomMessageTypes();
    _registerListenersOnce();
    _sdkConnectStarting = true;
    WKIM.shared.connectionManager.connect();
    scheduleMicrotask(() {
      _sdkConnectStarting = false;
    });
  }

  void _registerCustomMessageTypes() {
    if (_customMessageTypesRegistered) return;
    _customMessageTypesRegistered = true;
    WKIM.shared.messageManager.registerMsgContent(
      WkMessageContentType.gif,
      (data) => _BlinGifMessageContent().decodeJson(data),
    );
    for (final type in const [
      120,
      121,
      122,
      123,
      124,
      1001,
      1002,
      1003,
      1004,
      1005,
    ]) {
      WKIM.shared.messageManager.registerMsgContent(
        type,
        (data) => _BlinJsonMessageContent(type).decodeJson(data),
      );
    }
  }

  void _registerListenersOnce() {
    if (_listenersRegistered) return;
    _listenersRegistered = true;
    WKIM.shared.connectionManager.addOnConnectionStatus('imblinlin', (
      status,
      reason,
      connInfo,
    ) {
      _logConnectionStatus(status, reason, connInfo?.nodeId);
      if (_sdkConnectStarting && status == WKConnectStatus.fail) {
        _setConnection(connected: false, connecting: true, error: null);
        AppLogger.im('忽略SDK connect()启动阶段的内部断开状态');
        return;
      }
      if (status == WKConnectStatus.success ||
          status == WKConnectStatus.syncCompleted) {
        _sdkConnectStarting = false;
        _transientReconnectTimer?.cancel();
        _transientReconnectTimer = null;
        _setConnection(connected: true, connecting: false, error: null);
        return;
      }
      if (status == WKConnectStatus.syncMsg) {
        _sdkConnectStarting = false;
        _transientReconnectTimer?.cancel();
        _transientReconnectTimer = null;
        _setConnection(connected: true, connecting: false, error: null);
        return;
      }
      if (status == WKConnectStatus.connecting) {
        _setConnection(connected: connected, connecting: true, error: null);
        return;
      }
      if (status == WKConnectStatus.fail &&
          (_sdkConnectStarting || connected || connecting)) {
        _sdkConnectStarting = false;
        _setConnection(connected: connected, connecting: true, error: null);
        _scheduleTransientReconnectTimeout();
        AppLogger.im('SDK连接短暂失败，保持会话并等待自动恢复 $connectionSnapshot');
        return;
      }
      _transientReconnectTimer?.cancel();
      _transientReconnectTimer = null;
      final message = switch (status) {
        WKConnectStatus.noNetwork => 'IM网络不可用',
        WKConnectStatus.kicked => '当前账号已在其他同端设备登录',
        WKConnectStatus.fail => 'IM连接失败',
        _ => 'IM已断开',
      };
      _sdkConnectStarting = false;
      _setConnection(connected: false, connecting: false, error: message);
    });
    WKIM.shared.messageManager.addOnNewMsgListener('imblinlin_new', (msgs) {
      for (final message in msgs) {
        _handleWkMsg(message, source: 'new');
      }
    });
    WKIM.shared.messageManager.addOnMsgInsertedListener((message) {
      _handleWkMsg(message, source: 'insert');
    });
    WKIM.shared.messageManager.addOnRefreshMsgListener('imblinlin_refresh', (
      message,
    ) {
      _handleWkMsg(message, source: 'refresh');
    });
    WKIM.shared.cmdManager.addOnCmdListener('imblinlin_cmd', _handleCmd);
  }

  void _handleCmd(WKCMD cmd) {
    final param = cmd.param;
    final payload = param is Map
        ? Map<String, dynamic>.from(param)
        : _payloadStringToMap('${param ?? ''}');
    final cmdName = '${payload['cmd'] ?? payload['cmd_type'] ?? cmd.cmd}'
        .trim();
    payload.putIfAbsent('cmd', () => cmdName);
    if (cmdName.startsWith('call_') || cmdName == 'call') {
      payload.putIfAbsent('msg_type', () => 'call');
      payload.putIfAbsent('type', () => cmdName);
    } else {
      payload.putIfAbsent('msg_type', () => cmdName);
    }
    _dispatchPayload(payload, source: 'cmd');
  }

  void _handleWkMsg(WKMsg message, {required String source}) {
    if (source == 'refresh') return;
    final payload = _normalizePayload(message);
    _dispatchPayload(payload, source: source);
  }

  void _dispatchPayload(
    Map<String, dynamic> payload, {
    required String source,
  }) {
    if (_isDuplicatePayload(payload)) {
      AppLogger.im('重复payload已过滤 source=$source');
      return;
    }
    final msgType = '${payload['msg_type'] ?? payload['type'] ?? ''}'
        .trim()
        .toLowerCase();
    if (msgType == 'call' ||
        msgType == 'call_signal' ||
        '${payload['signal_type'] ?? ''}' == 'call_signal') {
      final signal = CallSignal.tryParse(payload);
      if (signal == null) {
        AppLogger.warn('IM', '通话payload解析失败 source=$source', data: payload);
        return;
      }
      final normalized = signal.toPayload();
      final contentMap = normalized['content'] is Map
          ? normalized['content'] as Map
          : const <dynamic, dynamic>{};
      final fromDeviceId =
          '${contentMap['from_device_id'] ?? normalized['from_device_id'] ?? ''}';
      final fromMe = '${normalized['from_user_id'] ?? 0}' == '$_myId';
      final sameDevice =
          fromDeviceId.isNotEmpty && fromDeviceId == _currentDeviceId;
      AppLogger.im(
        '通话信令 source=$source action=${signal.action} call=${signal.callId} from=${signal.fromUserId} to=${signal.toUserId} fromMe=$fromMe sameDevice=$sameDevice',
      );
      if (!fromMe || !sameDevice) _callController.add(normalized);
      return;
    }
    if (msgType == 'presence') {
      _presenceController.add(PresenceStatus.fromPayload(payload));
      return;
    }
    if (msgType == 'friend') {
      _friendController.add(payload);
      return;
    }
    if (msgType == 'typing') {
      _typingController.add(TypingEvent.fromPayload(payload));
      return;
    }
    if (msgType == 'read_receipt') {
      _readReceiptController.add(ReadReceipt.fromPayload(payload));
      return;
    }
    if (msgType == 'recall') {
      final message = UnifiedMessage.fromPayload(payload, _myId);
      _cacheIncomingMessage(message, payload);
      _messageController.add(message);
      return;
    }
    final message = UnifiedMessage.fromPayload(payload, _myId);
    _cacheIncomingMessage(message, payload);
    if ('${payload['from_user_id'] ?? 0}' == '$_myId') return;
    _messageController.add(message);
  }

  void _cacheIncomingMessage(
    UnifiedMessage message,
    Map<String, dynamic> payload,
  ) {
    final key = _conversationCacheKey(message, payload);
    if (key.isEmpty) return;
    unawaited(() async {
      try {
        await AppCacheStore.instance.cacheMessage(
          conversationKey: key,
          message: message,
        );
      } catch (e, stack) {
        AppLogger.exception('CACHE', e, stack, context: '缓存IM实时消息');
      }
    }());
  }

  String _conversationCacheKey(
    UnifiedMessage message,
    Map<String, dynamic> payload,
  ) {
    final content = payload['content'] is Map
        ? Map<String, dynamic>.from(payload['content'] as Map)
        : const <String, dynamic>{};
    final groupId =
        int.tryParse(
          '${payload['group_id'] ?? content['group_id'] ?? payload['channel_id'] ?? 0}',
        ) ??
        0;
    final groupNo = '${payload['group_no'] ?? content['group_no'] ?? ''}'
        .trim();
    if (groupId > 0) return 'group:$_myId:$groupId';
    if (groupNo.isNotEmpty) return 'group:$_myId:$groupNo';
    final peerId = message.fromUserId == _myId
        ? message.toUserId
        : message.fromUserId;
    if (peerId <= 0) return '';
    return 'peer:$_myId:$peerId';
  }

  bool _isDuplicatePayload(Map<String, dynamic> payload) {
    final content = payload['content'];
    final contentMap = content is Map ? content : const <String, dynamic>{};
    final msgType = '${payload['msg_type'] ?? payload['type'] ?? ''}'
        .trim()
        .toLowerCase();
    final keys = <String>{};
    if (msgType == 'call' || msgType == 'call_signal') {
      final callId = '${contentMap['call_id'] ?? payload['call_id'] ?? ''}'
          .trim();
      final action =
          '${contentMap['action'] ?? contentMap['type'] ?? payload['cmd'] ?? ''}'
              .trim();
      if (callId.isNotEmpty &&
          (action == 'invite' || action.contains('call_invite'))) {
        keys.add(
          'call_once_${payload['from_user_id'] ?? payload['from_uid']}_${payload['to_user_id'] ?? payload['to_uid']}_${callId}_invite',
        );
      }
    }
    final direct =
        '${payload['client_msg_no'] ?? payload['client_no'] ?? payload['message_id'] ?? contentMap['signal_id'] ?? ''}'
            .trim();
    if (direct.isNotEmpty && direct != '0') keys.add(direct);
    final semantic = _semanticPayloadKey(payload, contentMap);
    if (semantic.isNotEmpty && _isRecentSemanticDuplicate(semantic)) {
      return true;
    }
    final time = DateTime.tryParse('${payload['create_time'] ?? ''}');
    final timeBucket = time == null
        ? ''
        : '${time.millisecondsSinceEpoch ~/ 1000}';
    keys.add(
      '${payload['from_user_id'] ?? payload['from_uid']}_${payload['to_user_id'] ?? payload['to_uid']}_${payload['msg_type'] ?? payload['type']}_${timeBucket}_${jsonEncode(contentMap)}',
    );
    if (keys.any(_recentMessageKeys.contains)) return true;
    _recentMessageKeys.addAll(keys);
    _recentMessageQueue.addAll(keys);
    while (_recentMessageQueue.length > 500) {
      _recentMessageKeys.remove(_recentMessageQueue.removeFirst());
    }
    if (semantic.isNotEmpty) _rememberSemantic(semantic);
    return false;
  }

  String _semanticPayloadKey(
    Map<String, dynamic> payload,
    Map<dynamic, dynamic> contentMap,
  ) {
    final msgType = '${payload['msg_type'] ?? payload['type'] ?? ''}'
        .trim()
        .toLowerCase();
    if (msgType == 'call' ||
        msgType == 'presence' ||
        msgType == 'friend' ||
        msgType == 'typing' ||
        msgType == 'read_receipt') {
      return '';
    }
    final from = '${payload['from_user_id'] ?? payload['from_uid'] ?? ''}'
        .trim();
    final to =
        '${payload['to_user_id'] ?? payload['to_uid'] ?? payload['group_no'] ?? ''}'
            .trim();
    if (from.isEmpty || to.isEmpty) return '';
    final normalizedContent = Map<String, dynamic>.from(contentMap)
      ..remove('client_msg_no')
      ..remove('message_id')
      ..remove('id')
      ..remove('create_time');
    return '$from|$to|$msgType|${jsonEncode(normalizedContent)}';
  }

  bool _isRecentSemanticDuplicate(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _trimRecentSemantic(now);
    final last = _recentSemanticAt[key];
    return last != null && now - last <= 4000;
  }

  void _rememberSemantic(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _recentSemanticAt[key] = now;
    _recentSemanticQueue.add(key);
    _trimRecentSemantic(now);
  }

  void _trimRecentSemantic(int now) {
    while (_recentSemanticQueue.isNotEmpty) {
      final first = _recentSemanticQueue.first;
      final at = _recentSemanticAt[first];
      if (at != null &&
          now - at <= 4000 &&
          _recentSemanticQueue.length <= 500) {
        break;
      }
      _recentSemanticQueue.removeFirst();
      if (at == null || now - at > 4000) _recentSemanticAt.remove(first);
    }
  }

  Map<String, dynamic> _normalizePayload(WKMsg message) {
    final parsed = _payloadStringToMap(message.content);
    final parsedContent = parsed['content'];
    final parsedInner = parsedContent is String
        ? _payloadStringToMap(parsedContent)
        : <String, dynamic>{};
    final text = message.messageContent?.displayText();
    final textParsed = _payloadStringToMap(text ?? '');
    final parsedIsBusinessPayload =
        parsed.isNotEmpty &&
        ('${parsed['msg_type'] ?? parsed['type_name'] ?? ''}'
            .trim()
            .isNotEmpty);
    final fromUid = message.fromUID;
    final channelId = message.channelID;
    final isGroup = message.channelType == WKChannelType.group;
    final map = parsedInner.isNotEmpty
        ? parsedInner
        : parsedIsBusinessPayload
        ? parsed
        : parsed.isNotEmpty &&
              '${parsed['type'] ?? ''}' != '${WkMessageContentType.text}'
        ? parsed
        : textParsed.isNotEmpty
        ? textParsed
        : {
            'msg_type': 'text',
            'content': {'text': text ?? message.content},
          };
    map.putIfAbsent('from_uid', () => fromUid);
    map.putIfAbsent('to_uid', () => channelId);
    map.putIfAbsent('from_user_id', () => _userIdFromUid(fromUid));
    if (!isGroup) {
      map.putIfAbsent(
        'to_user_id',
        () =>
            _userIdFromUid(channelId) == 0 ? _myId : _userIdFromUid(channelId),
      );
    }
    final sdkType = _sdkMsgType(map);
    map.putIfAbsent('channel_type', () => message.channelType);
    map.putIfAbsent('group_no', () => isGroup ? channelId : '');
    map.putIfAbsent('client_msg_no', () => message.clientMsgNO);
    map.putIfAbsent('message_id', () => message.messageID);
    map.putIfAbsent('create_time', () => DateTime.now().toIso8601String());
    if (sdkType == 'gif') {
      map['msg_type'] = 'gif';
      map['content'] = _gifContentFromPayload(map);
    } else {
      map.putIfAbsent('msg_type', () => sdkType);
    }
    final content = map['content'];
    if (content is! Map) map['content'] = {'text': '${content ?? ''}'};
    return map;
  }

  Map<String, dynamic> _gifContentFromPayload(Map<String, dynamic> payload) {
    final current = payload['content'];
    final content = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = '${content[key] ?? payload[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    final url = pick(['url', 'file_url', 'image_path', 'file_path', 'src']);
    final width = content['width'] ?? payload['width'] ?? 0;
    final height = content['height'] ?? payload['height'] ?? 0;
    final name = pick(['name', 'file_name']);
    return {
      ...content,
      'url': url,
      'file_url': url,
      'image_path': url,
      'file_path': url,
      if (name.isNotEmpty) 'name': name,
      if (name.isNotEmpty) 'file_name': name,
      'width': width,
      'height': height,
      'media_format': 'gif',
      'format': 'gif',
      'animated': true,
      'is_gif': true,
    };
  }

  String _sdkMsgType(Map<String, dynamic> payload) {
    final raw = payload['type'];
    final type = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (type == 2) return 'image';
    if (type == 3) return 'gif';
    if (type == 4) return 'voice';
    if (type == 5) return 'video';
    if (type == 8) return 'file';
    if (type == 120) return 'transfer';
    if (type == 121) return 'red_packet';
    if (type == 122) return 'call_record';
    if (type == 123) return 'group_call_invite';
    if (type == 124) return 'group_call_record';
    if (type == 1001) return 'screenshot';
    if (type == 1002) return 'recall';
    if (type == 1003) return 'transfer_receipt';
    if (type == 1004) return 'red_packet_receipt';
    if (type == 1005) return 'system';
    return 'text';
  }

  Map<String, dynamic> _payloadStringToMap(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return <String, dynamic>{};
    final direct = _tryJsonMap(text);
    if (direct != null) return direct;
    try {
      final normalized = base64.normalize(text.replaceAll(RegExp(r'\s+'), ''));
      final decoded = utf8.decode(
        base64.decode(normalized),
        allowMalformed: true,
      );
      final decodedMap = _tryJsonMap(decoded.trim());
      if (decodedMap != null) return decodedMap;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _tryJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  int _userIdFromUid(String uid) {
    if (uid.contains('_')) return int.tryParse(uid.split('_').last) ?? 0;
    return int.tryParse(uid) ?? 0;
  }

  Future<void> waitForConnected({
    Duration timeout = const Duration(seconds: 10),
    bool requireStable = false,
  }) async {
    if (connected && (!connecting || !requireStable)) return;
    if (connected && connecting) {
      await _waitForReconnectSettled(
        timeout: requireStable
            ? timeout
            : timeout < const Duration(seconds: 2)
            ? timeout
            : const Duration(seconds: 2),
      );
      if (connected && (!connecting || !requireStable)) return;
      if (requireStable && connected && connecting) {
        throw TimeoutException('IM连接恢复超时', timeout);
      }
    }
    final tcpAddr = _lastTcpAddr;
    final uid = _lastUid;
    final token = _lastToken;
    if (tcpAddr == null || uid == null || token == null) {
      AppLogger.error('IM', '等待连接失败：连接信息缺失', data: connectionSnapshot);
      throw StateError('IM连接信息缺失，请重新登录');
    }

    final completer = Completer<void>();
    final waiter = _PendingConnectionWaiter(completer);
    _connectionWaiters.add(waiter);
    waiter.timer = Timer(timeout, () {
      _connectionWaiters.remove(waiter);
      if (!completer.isCompleted) {
        AppLogger.error('IM', '等待连接超时', data: connectionSnapshot);
        completer.completeError(TimeoutException('IM连接超时', timeout));
      }
    });

    if (_connectFuture == null && !connecting && !connected) {
      AppLogger.im('等待连接时触发重连 $connectionSnapshot');
      unawaited(
        connect(
          info: ImConnectInfo(uid: uid, token: token, tcpAddr: tcpAddr),
          myId: _myId,
          waitUntilReady: true,
          readyTimeout: timeout,
        ),
      );
    }

    if (connected) {
      _connectionWaiters.remove(waiter);
      waiter.timer?.cancel();
      if (!completer.isCompleted) completer.complete();
    }
    return completer.future;
  }

  Future<void> ensureConnected() => waitForConnected();

  void _scheduleTransientReconnectTimeout() {
    _transientReconnectTimer?.cancel();
    _transientReconnectTimer = Timer(const Duration(seconds: 8), () {
      if (!connected || !connecting) return;
      AppLogger.warn('IM', 'SDK连接恢复超时，进入重连', data: connectionSnapshot);
      _setConnection(connected: false, connecting: false, error: 'IM连接失败');
    });
  }

  Future<void> _waitForReconnectSettled({required Duration timeout}) async {
    if (!connecting || !connected) return;
    final completer = Completer<void>();
    late StreamSubscription<void> sub;
    Timer? timer;
    void finish() {
      timer?.cancel();
      unawaited(sub.cancel());
      if (!completer.isCompleted) completer.complete();
    }

    sub = connectionChanges.listen((_) {
      if (!connecting || !connected) finish();
    });
    timer = Timer(timeout, finish);
    await completer.future;
  }

  Future<void> sendDirect({
    required String channelId,
    required Map<String, dynamic> payload,
  }) => _send(
    channelId: channelId,
    channelType: WKChannelType.personal,
    payload: payload,
  );

  Future<void> sendGroup({
    required String channelId,
    required Map<String, dynamic> payload,
  }) => _send(
    channelId: channelId,
    channelType: WKChannelType.group,
    payload: payload,
  );

  Future<void> _send({
    required String channelId,
    required int channelType,
    required Map<String, dynamic> payload,
  }) async {
    final payloadType = '${payload['msg_type'] ?? payload['type'] ?? ''}'
        .trim();
    final waitTimeout = payloadType == 'call'
        ? const Duration(seconds: 8)
        : const Duration(seconds: 10);
    await waitForConnected(
      timeout: waitTimeout,
      requireStable: payloadType == 'call',
    );
    final content = payloadType == 'gif'
        ? _BlinGifMessageContent.fromPayload(payload)
        : WKTextContent(jsonEncode(payload));
    final header = _sdkHeaderForPayload(payloadType);
    if (header == null) {
      await WKIM.shared.messageManager.sendMessage(
        content,
        WKChannel(channelId, channelType),
      );
      return;
    }
    final options = WKSendOptions()..header = header;
    await WKIM.shared.messageManager.sendWithOption(
      content,
      WKChannel(channelId, channelType),
      options,
    );
  }

  MessageHeader? _sdkHeaderForPayload(String payloadType) {
    if (const {
      'typing',
      'read_receipt',
      'presence',
      'call',
      'call_signal',
    }.contains(payloadType)) {
      return MessageHeader()
        ..noPersist = true
        ..redDot = false
        ..syncOnce = true;
    }
    return null;
  }

  Future<void> disconnect({bool logout = false}) async {
    _sdkConnectStarting = false;
    _transientReconnectTimer?.cancel();
    _transientReconnectTimer = null;
    AppLogger.im('主动断开IM logout=$logout $connectionSnapshot');
    _failConnectionWaiters(logout ? 'IM已退出登录' : 'IM已断开');
    _setConnection(connected: false, connecting: false, error: null);
    WKIM.shared.connectionManager.disconnect(logout);
  }

  void dispose() {
    _sdkConnectStarting = false;
    _transientReconnectTimer?.cancel();
    _transientReconnectTimer = null;
    _failConnectionWaiters('IM服务已释放');
    WKIM.shared.messageManager.removeNewMsgListener('imblinlin_new');
    WKIM.shared.messageManager.removeOnRefreshMsgListener('imblinlin_refresh');
    WKIM.shared.cmdManager.removeCmdListener('imblinlin_cmd');
    WKIM.shared.connectionManager.removeOnConnectionStatus('imblinlin');
    _messageController.close();
    _callController.close();
    _friendController.close();
    _presenceController.close();
    _typingController.close();
    _readReceiptController.close();
    _connectionController.close();
    WKIM.shared.connectionManager.disconnect(true);
  }

  void _logConnectionStatus(int status, dynamic reason, dynamic nodeId) {
    final key =
        '$status|${reason ?? '-'}|${nodeId ?? '-'}|$connected|$connecting|$_sdkConnectStarting|${connectionError ?? '-'}';
    final now = DateTime.now();
    final shouldLog =
        key != _lastConnectionLogKey ||
        _lastConnectionLogAt == null ||
        now.difference(_lastConnectionLogAt!) > const Duration(seconds: 15);
    if (!shouldLog) return;
    _lastConnectionLogKey = key;
    _lastConnectionLogAt = now;
    AppLogger.im(
      'SDK连接状态 status=$status reason=${reason ?? '-'} node=${nodeId ?? '-'} $connectionSnapshot',
    );
  }

  String _safeAddr(String? addr) {
    final text = (addr ?? '').trim();
    if (text.isEmpty) return '-';
    final parts = text.split(':');
    if (parts.length < 2) return text;
    final host = parts.first;
    final port = parts.sublist(1).join(':');
    final hostParts = host.split('.');
    if (hostParts.length == 4) {
      return '${hostParts.take(2).join('.')}.*.*:$port';
    }
    return '$host:$port';
  }
}

class _BlinJsonMessageContent extends WKMessageContent {
  _BlinJsonMessageContent(int type) {
    contentType = type;
  }

  @override
  WKMessageContent decodeJson(Map<String, dynamic> json) {
    content = jsonEncode(json);
    return this;
  }

  @override
  Map<String, dynamic> encodeJson() {
    final decoded = _tryDecode(content);
    return decoded ?? <String, dynamic>{'content': content};
  }

  @override
  String displayText() => content;

  @override
  String searchableWord() => content;

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}

class _BlinGifMessageContent extends WKMessageContent {
  String url = '';
  int width = 0;
  int height = 0;

  _BlinGifMessageContent() {
    contentType = WkMessageContentType.gif;
  }

  factory _BlinGifMessageContent.fromPayload(Map<String, dynamic> payload) {
    final content = payload['content'];
    final contentMap = content is Map
        ? Map<String, dynamic>.from(content)
        : <String, dynamic>{};

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = '${contentMap[key] ?? payload[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    int pickInt(List<String> keys) {
      for (final key in keys) {
        final value = contentMap[key] ?? payload[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse('${value ?? ''}');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    return _BlinGifMessageContent()
      ..url = pick(['url', 'file_url', 'image_path', 'file_path', 'src'])
      ..width = pickInt(['width', 'image_width'])
      ..height = pickInt(['height', 'image_height'])
      ..content = jsonEncode(payload);
  }

  @override
  WKMessageContent decodeJson(Map<String, dynamic> json) {
    url = readString(json, 'url');
    width = readInt(json, 'width');
    height = readInt(json, 'height');
    content = jsonEncode(json);
    return this;
  }

  @override
  Map<String, dynamic> encodeJson() => {
    'url': url,
    'width': width,
    'height': height,
  };

  @override
  String displayText() => '[GIF]';

  @override
  String searchableWord() => '[GIF]';
}

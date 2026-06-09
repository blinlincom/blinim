import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:wukongimfluttersdk/common/options.dart';
import 'package:wukongimfluttersdk/entity/channel.dart';
import 'package:wukongimfluttersdk/entity/cmd.dart';
import 'package:wukongimfluttersdk/entity/msg.dart';
import 'package:wukongimfluttersdk/model/wk_text_content.dart';
import 'package:wukongimfluttersdk/type/const.dart';
import 'package:wukongimfluttersdk/wkim.dart';

import '../core/app_config.dart';
import '../models/im_models.dart';
import 'client_device_context.dart';

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

class ImService {
  final _messageController = StreamController<UnifiedMessage>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _friendController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<PresenceStatus>.broadcast();
  final _connectionController = StreamController<void>.broadcast();
  final List<_PendingConnectionWaiter> _connectionWaiters = [];
  Future<void>? _connectFuture;
  final _recentMessageKeys = HashSet<String>();
  final _recentMessageQueue = Queue<String>();
  bool connected = false;
  bool connecting = false;
  bool _listenersRegistered = false;
  String? connectionError;
  String? _lastTcpAddr;
  String? _lastToken;
  String? _lastUid;
  String? _currentDeviceId;
  int _myId = 0;

  static String uidForUser(int userId) => '${AppConfig.appId}_$userId';

  bool get isSocketConnected => connected;
  String? get currentDeviceId => _currentDeviceId;

  Stream<UnifiedMessage> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get calls => _callController.stream;
  Stream<Map<String, dynamic>> get friendEvents => _friendController.stream;
  Stream<PresenceStatus> get presences => _presenceController.stream;
  Stream<void> get connectionChanges => _connectionController.stream;

  void _notifyConnection() {
    if (!_connectionController.isClosed) _connectionController.add(null);
  }

  void _setConnection({bool? connected, bool? connecting, String? error}) {
    if (connected != null) this.connected = connected;
    if (connecting != null) this.connecting = connecting;
    connectionError = error;
    if (this.connected) {
      _flushConnectionWaiters();
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

  Future<void> connect({required ImConnectInfo info, required int myId}) {
    if (connected && _lastUid == info.uid && _lastToken == info.token) return Future.value();
    if (_connectFuture != null && connecting) return _connectFuture!;
    _connectFuture = _connectInternal(info: info, myId: myId).whenComplete(() {
      _connectFuture = null;
    });
    return _connectFuture!;
  }

  Future<void> _connectInternal({required ImConnectInfo info, required int myId}) async {
    _myId = myId;
    _lastTcpAddr = info.tcpAddr;
    _lastToken = info.token;
    _lastUid = info.uid;
    _setConnection(connected: false, connecting: true, error: null);
    final device = ClientDeviceContext.current();
    final deviceId = await device.persistentDeviceId();
    _currentDeviceId = deviceId;

    if (info.tcpAddr.trim().isEmpty) {
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
    _registerListenersOnce();
    WKIM.shared.connectionManager.connect();
  }

  void _registerListenersOnce() {
    if (_listenersRegistered) return;
    _listenersRegistered = true;
    WKIM.shared.connectionManager.addOnConnectionStatus(
      'imblinlin',
      (status, reason, connInfo) {
        if (status == WKConnectStatus.success ||
            status == WKConnectStatus.syncCompleted) {
          _setConnection(connected: true, connecting: false, error: null);
          return;
        }
        if (status == WKConnectStatus.connecting ||
            status == WKConnectStatus.syncMsg) {
          _setConnection(connected: connected, connecting: true, error: null);
          return;
        }
        _setConnection(
          connected: false,
          connecting: false,
          error: status == WKConnectStatus.noNetwork ? 'IM网络不可用' : 'IM已断开',
        );
      },
    );
    WKIM.shared.messageManager.addOnNewMsgListener('imblinlin_new', (msgs) {
      for (final message in msgs) {
        _handleWkMsg(message, source: 'new');
      }
    });
    WKIM.shared.messageManager.addOnMsgInsertedListener((message) {
      _handleWkMsg(message, source: 'insert');
    });
    WKIM.shared.messageManager.addOnRefreshMsgListener('imblinlin_refresh', (message) {
      _handleWkMsg(message, source: 'refresh');
    });
    WKIM.shared.cmdManager.addOnCmdListener('imblinlin_cmd', _handleCmd);
  }

  void _handleCmd(WKCMD cmd) {
    final param = cmd.param;
    final payload = param is Map
        ? Map<String, dynamic>.from(param)
        : _payloadStringToMap('${param ?? ''}');
    final cmdName = '${payload['cmd'] ?? payload['cmd_type'] ?? cmd.cmd}'.trim();
    payload.putIfAbsent('cmd', () => cmdName);
    if (cmdName.startsWith('call_') || cmdName == 'call') {
      final contentRaw = payload['content'];
      final content = contentRaw is Map
          ? Map<String, dynamic>.from(contentRaw)
          : <String, dynamic>{};
      final rawAction = '${content['action'] ?? content['type'] ?? cmdName}'.trim();
      final action = switch (rawAction) {
        'call_invite' => 'invite',
        'call_offer' => 'offer',
        'call_accept' => 'accept',
        'call_answer' => 'answer',
        'call_ice' => 'ice',
        'call_hangup' => 'hangup',
        'call_reject' => 'reject',
        'call_ack' => 'ack',
        _ => rawAction.startsWith('call_') ? rawAction.substring(5) : rawAction,
      };
      payload['msg_type'] = 'call';
      payload.putIfAbsent('from_user_id', () => _userIdFromUid('${payload['from_uid'] ?? payload['fromUID'] ?? ''}'));
      payload.putIfAbsent('to_user_id', () => _userIdFromUid('${payload['to_uid'] ?? payload['toUID'] ?? payload['channel_id'] ?? ''}'));
      payload['content'] = {
        ...content,
        if ('${content['call_id'] ?? payload['call_id'] ?? ''}'.trim().isNotEmpty)
          'call_id': '${content['call_id'] ?? payload['call_id']}',
        'from_user_id': payload['from_user_id'],
        'to_user_id': payload['to_user_id'],
        'action': action,
        'type': cmdName.startsWith('call_') ? cmdName : 'call_$action',
      };
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

  void _dispatchPayload(Map<String, dynamic> payload, {required String source}) {
    if (_isDuplicatePayload(payload)) return;
    final msgType = '${payload['msg_type'] ?? payload['type'] ?? ''}'.trim().toLowerCase();
    if (msgType == 'call') {
      final content = payload['content'];
      final contentMap = content is Map ? content : const <String, dynamic>{};
      final fromDeviceId =
          '${contentMap['from_device_id'] ?? payload['from_device_id'] ?? ''}';
      final fromMe = '${payload['from_user_id'] ?? 0}' == '$_myId';
      final sameDevice =
          fromDeviceId.isNotEmpty && fromDeviceId == _currentDeviceId;
      if (!fromMe || !sameDevice) _callController.add(payload);
      return;
    }
    if ('${payload['from_user_id'] ?? 0}' == '$_myId') return;
    if ('${payload['msg_type'] ?? ''}' == 'presence') {
      _presenceController.add(PresenceStatus.fromPayload(payload));
      return;
    }
    if ('${payload['msg_type'] ?? ''}' == 'friend') {
      _friendController.add(payload);
      return;
    }
    _messageController.add(UnifiedMessage.fromPayload(payload, _myId));
  }

  bool _isDuplicatePayload(Map<String, dynamic> payload) {
    final content = payload['content'];
    final contentMap = content is Map ? content : const <String, dynamic>{};
    final msgType = '${payload['msg_type'] ?? payload['type'] ?? ''}'.trim().toLowerCase();
    final keys = <String>{};
    if (msgType == 'call') {
      final callId = '${contentMap['call_id'] ?? payload['call_id'] ?? ''}'.trim();
      final action = '${contentMap['action'] ?? contentMap['type'] ?? payload['cmd'] ?? ''}'.trim();
      if (callId.isNotEmpty && (action == 'invite' || action.contains('call_invite'))) {
        keys.add('call_once_${payload['from_user_id'] ?? payload['from_uid']}_${payload['to_user_id'] ?? payload['to_uid']}_${callId}_invite');
      }
    }
    final direct =
        '${payload['client_msg_no'] ?? payload['client_no'] ?? payload['message_id'] ?? contentMap['signal_id'] ?? ''}'.trim();
    if (direct.isNotEmpty && direct != '0') keys.add(direct);
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
    return false;
  }

  Map<String, dynamic> _normalizePayload(WKMsg message) {
    final parsed = _payloadStringToMap(message.content);
    final parsedContent = parsed['content'];
    final parsedInner = parsedContent is String
        ? _payloadStringToMap(parsedContent)
        : <String, dynamic>{};
    final text = message.messageContent?.displayText();
    final textParsed = _payloadStringToMap(text ?? '');
    final fromUid = message.fromUID;
    final channelId = message.channelID;
    final isGroup = message.channelType == WKChannelType.group;
    final map = parsedInner.isNotEmpty
        ? parsedInner
        : parsed.isNotEmpty && '${parsed['type'] ?? ''}' != '${WkMessageContentType.text}'
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
        () => _userIdFromUid(channelId) == 0 ? _myId : _userIdFromUid(channelId),
      );
    }
    map.putIfAbsent('channel_type', () => message.channelType);
    map.putIfAbsent('group_no', () => isGroup ? channelId : '');
    map.putIfAbsent('client_msg_no', () => message.clientMsgNO);
    map.putIfAbsent('message_id', () => message.messageID);
    map.putIfAbsent('create_time', () => DateTime.now().toIso8601String());
    map.putIfAbsent('msg_type', () => 'text');
    final content = map['content'];
    if (content is! Map) map['content'] = {'text': '${content ?? ''}'};
    return map;
  }

  Map<String, dynamic> _payloadStringToMap(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return <String, dynamic>{};
    final direct = _tryJsonMap(text);
    if (direct != null) return direct;
    try {
      final normalized = base64.normalize(text.replaceAll(RegExp(r'\s+'), ''));
      final decoded = utf8.decode(base64.decode(normalized), allowMalformed: true);
      final decodedMap = _tryJsonMap(decoded.trim());
      if (decodedMap != null) return decodedMap;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _tryJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
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
  }) async {
    if (connected) return;
    final tcpAddr = _lastTcpAddr;
    final uid = _lastUid;
    final token = _lastToken;
    if (tcpAddr == null || uid == null || token == null) {
      throw StateError('IM连接信息缺失，请重新登录');
    }

    final completer = Completer<void>();
    final waiter = _PendingConnectionWaiter(completer);
    _connectionWaiters.add(waiter);
    waiter.timer = Timer(timeout, () {
      _connectionWaiters.remove(waiter);
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('IM连接超时', timeout));
      }
    });

    if (!connecting && !connected) {
      unawaited(
        connect(info: ImConnectInfo(uid: uid, token: token, tcpAddr: tcpAddr), myId: _myId),
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

  Future<void> sendDirect({
    required String channelId,
    required Map<String, dynamic> payload,
  }) => _send(channelId: channelId, channelType: WKChannelType.personal, payload: payload);

  Future<void> sendGroup({
    required String channelId,
    required Map<String, dynamic> payload,
  }) => _send(channelId: channelId, channelType: WKChannelType.group, payload: payload);

  Future<void> _send({
    required String channelId,
    required int channelType,
    required Map<String, dynamic> payload,
  }) async {
    final payloadType = '${payload['msg_type'] ?? payload['type'] ?? ''}'.trim();
    final waitTimeout = payloadType == 'call'
        ? const Duration(seconds: 8)
        : const Duration(seconds: 10);
    await waitForConnected(timeout: waitTimeout);
    final content = WKTextContent(jsonEncode(payload));
    await WKIM.shared.messageManager.sendMessage(
      content,
      WKChannel(channelId, channelType),
    );
  }

  Future<void> disconnect({bool logout = false}) async {
    _failConnectionWaiters(logout ? 'IM已退出登录' : 'IM已断开');
    _setConnection(connected: false, connecting: false, error: null);
    WKIM.shared.connectionManager.disconnect(logout);
  }

  void dispose() {
    _failConnectionWaiters('IM服务已释放');
    WKIM.shared.messageManager.removeNewMsgListener('imblinlin_new');
    WKIM.shared.messageManager.removeOnRefreshMsgListener('imblinlin_refresh');
    WKIM.shared.cmdManager.removeCmdListener('imblinlin_cmd');
    WKIM.shared.connectionManager.removeOnConnectionStatus('imblinlin');
    _messageController.close();
    _callController.close();
    _friendController.close();
    _presenceController.close();
    _connectionController.close();
    WKIM.shared.connectionManager.disconnect(true);
  }
}

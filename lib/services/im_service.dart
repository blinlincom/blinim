import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';
import 'package:wukong_easy_sdk/wukong_easy_sdk.dart';
import 'client_device_context.dart';
import '../core/app_config.dart';
import '../models/im_models.dart';

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
    final uid = '${p['uid'] ?? ''}';
    return PresenceStatus(
      userId: int.tryParse('${p['user_id'] ?? 0}') ?? _userIdFromUidStatic(uid),
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

class ImService {
  final WuKongEasySDK _sdk = WuKongEasySDK.getInstance();
  final _messageController = StreamController<UnifiedMessage>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _friendController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<PresenceStatus>.broadcast();
  final _connectionController = StreamController<void>.broadcast();
  final _recentMessageKeys = HashSet<String>();
  final _recentMessageQueue = Queue<String>();
  bool connected = false;
  bool connecting = false;
  bool _listenersRegistered = false;
  String? connectionError;
  String? _lastServerUrl;
  String? _lastToken;
  String? _lastUid;
  int _myId = 0;

  static String uidForUser(int userId) => '${AppConfig.appId}_$userId';

  bool get isSocketConnected => _sdk.isConnected;

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
    _notifyConnection();
  }

  Future<void> connect({required ImConnectInfo info, required int myId}) async {
    _myId = myId;
    _lastServerUrl = info.wsAddr;
    _lastToken = info.token;
    _lastUid = info.uid;
    _setConnection(connected: false, connecting: true, error: null);
    final device = ClientDeviceContext.current();
    final config = WuKongConfig(
      serverUrl: info.wsAddr,
      uid: info.uid,
      token: info.token,
      deviceId: await device.persistentDeviceId(),
      deviceFlag: WuKongDeviceFlag.fromValue(device.deviceFlag),
    );
    await _sdk.init(config);
    _registerListenersOnce();
    try {
      await _sdk.connect();
      if (_sdk.isConnected) {
        _setConnection(connected: true, connecting: false, error: null);
      }
    } catch (e) {
      _setConnection(connected: false, connecting: false, error: 'IM 连接失败：$e');
      rethrow;
    }
  }

  void _registerListenersOnce() {
    if (_listenersRegistered) return;
    _listenersRegistered = true;
    _sdk.addEventListener(WuKongEvent.connect, (ConnectResult result) {
      _setConnection(connected: true, connecting: false, error: null);
    });
    _sdk.addEventListener(WuKongEvent.disconnect, (DisconnectInfo info) {
      _setConnection(connected: false, connecting: false, error: 'IM 已断开');
    });
    _sdk.addEventListener(WuKongEvent.error, (dynamic error) {
      _setConnection(
        connected: false,
        connecting: false,
        error: 'IM 连接失败：$error',
      );
    });
    _sdk.addEventListener(WuKongEvent.message, (Message message) {
      final payload = _normalizePayload(message.payload, message: message);
      if ('${payload['msg_type'] ?? ''}' != 'call' &&
          _isDuplicatePayload(payload)) {
        return;
      }
      if ('${payload['from_user_id'] ?? 0}' == '$_myId') {
        return;
      }
      if ('${payload['msg_type'] ?? ''}' == 'presence') {
        _presenceController.add(PresenceStatus.fromPayload(payload));
        return;
      }
      if ('${payload['msg_type'] ?? ''}' == 'call') {
        _callController.add(payload);
        return;
      }
      if ('${payload['msg_type'] ?? ''}' == 'friend') {
        _friendController.add(payload);
        return;
      }
      _messageController.add(UnifiedMessage.fromPayload(payload, _myId));
    });
  }

  bool _isDuplicatePayload(Map<String, dynamic> payload) {
    final content = payload['content'];
    final contentMap = content is Map ? content : const <String, dynamic>{};
    final key =
        '${payload['client_msg_no'] ?? payload['client_no'] ?? payload['message_id'] ?? contentMap['signal_id'] ?? ''}';
    if (key.trim().isEmpty || key == '0') return false;
    if (_recentMessageKeys.contains(key)) return true;
    _recentMessageKeys.add(key);
    _recentMessageQueue.addLast(key);
    while (_recentMessageQueue.length > 300) {
      _recentMessageKeys.remove(_recentMessageQueue.removeFirst());
    }
    return false;
  }

  Map<String, dynamic> _normalizePayload(dynamic payload, {Message? message}) {
    Map<String, dynamic> map;
    if (payload is Map<String, dynamic>) {
      map = Map<String, dynamic>.from(payload);
    } else if (payload is Map) {
      map = Map<String, dynamic>.from(payload);
    } else if (payload is Uint8List) {
      map = _payloadStringToMap(utf8.decode(payload, allowMalformed: true));
    } else if (payload is List<int>) {
      map = _payloadStringToMap(utf8.decode(payload, allowMalformed: true));
    } else if (payload is String) {
      map = _payloadStringToMap(payload);
    } else {
      map = {
        'msg_type': 'text',
        'content': {'text': '$payload'},
      };
    }

    // 兼容旧网页测试端/SDK 直接消息：payload 内缺少 from_user_id/to_user_id 时，从 WuKongIM envelope 兜底解析。
    final fromUid = '${map['from_uid'] ?? message?.fromUid ?? ''}';
    final channelId =
        '${map['to_uid'] ?? map['channel_id'] ?? message?.channelId ?? ''}';
    map.putIfAbsent('from_uid', () => fromUid);
    map.putIfAbsent('to_uid', () => channelId);
    map.putIfAbsent('from_user_id', () => _userIdFromUid(fromUid));
    map.putIfAbsent(
      'to_user_id',
      () => _userIdFromUid(channelId) == 0 ? _myId : _userIdFromUid(channelId),
    );
    map.putIfAbsent('msg_type', () => _legacyType(map));
    final c = map['content'];
    if (c is! Map)
      map['content'] = {'text': '${c ?? map['legacy']?['content'] ?? ''}'};
    return map;
  }

  Map<String, dynamic> _payloadStringToMap(String raw) {
    final text = raw.trim();

    // 1) 正常 JSON 字符串
    final direct = _tryJsonMap(text);
    if (direct != null) return direct;

    // 2) WuKongIM / 后端有时会把 payload 作为 base64 字符串传给 SDK。
    //    典型形态：eyJ2ZXJzaW9uIjoiMS4wIiwi...
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (_looksLikeBase64(compact)) {
      final decodedText = _tryBase64Utf8(compact);
      if (decodedText != null) {
        final decodedMap = _tryJsonMap(decodedText.trim());
        if (decodedMap != null) return decodedMap;
      }
    }

    // 3) 兜底：作为普通文本展示，避免把 base64 原文当业务消息内容长期污染。
    return {
      'msg_type': 'text',
      'content': {'text': text},
    };
  }

  Map<String, dynamic>? _tryJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>)
        return Map<String, dynamic>.from(decoded);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String? _tryBase64Utf8(String text) {
    try {
      final normalized = base64.normalize(text);
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      try {
        var padded = text.replaceAll('-', '+').replaceAll('_', '/');
        while (padded.length % 4 != 0) {
          padded += '=';
        }
        return utf8.decode(base64.decode(padded), allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  bool _looksLikeBase64(String text) {
    if (text.length < 16) return false;
    if (!RegExp(r'^[A-Za-z0-9_\-+/=]+$').hasMatch(text)) return false;
    return text.startsWith('eyJ') ||
        text.startsWith('e1') ||
        text.length % 4 == 0;
  }

  int _userIdFromUid(String uid) {
    if (uid.contains('_')) return int.tryParse(uid.split('_').last) ?? 0;
    return int.tryParse(uid) ?? 0;
  }

  String _legacyType(Map<String, dynamic> map) {
    final t =
        int.tryParse(
          '${map['message_type'] ?? map['type'] ?? map['legacy']?['type'] ?? 0}',
        ) ??
        0;
    if (t == 1) return 'image';
    if (t == 2) return 'transfer';
    if (t == 3) return 'file';
    if (t == 4) return 'video';
    return 'text';
  }

  Future<void> ensureConnected() async {
    if (_sdk.isConnected) {
      _setConnection(connected: true, connecting: false, error: null);
      return;
    }
    for (var i = 0; i < 25 && connecting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_sdk.isConnected) {
        _setConnection(connected: true, connecting: false, error: null);
        return;
      }
    }
    final serverUrl = _lastServerUrl;
    final uid = _lastUid;
    final token = _lastToken;
    if (serverUrl == null || uid == null || token == null) {
      throw StateError('IM连接信息缺失，请重新登录');
    }
    await connect(
      info: ImConnectInfo(uid: uid, token: token, wsAddr: serverUrl),
      myId: _myId,
    );
    if (!_sdk.isConnected) throw StateError('IM未连接');
  }

  Future<void> sendDirect({
    required String channelId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await ensureConnected();
      await _sdk.send(
        channelId: channelId,
        channelType: WuKongChannelType.person,
        payload: payload,
      );
    } catch (e) {
      _setConnection(connected: false, connecting: false, error: 'IM发送失败：$e');
      await ensureConnected();
      await _sdk.send(
        channelId: channelId,
        channelType: WuKongChannelType.person,
        payload: payload,
      );
    }
  }

  Future<void> disconnect() async {
    _setConnection(connected: false, connecting: false, error: null);
    _sdk.disconnect();
  }

  void dispose() {
    _messageController.close();
    _callController.close();
    _friendController.close();
    _presenceController.close();
    _connectionController.close();
    _sdk.disconnect();
  }
}

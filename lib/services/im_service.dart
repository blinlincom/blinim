import 'dart:async';
import 'dart:convert';
import 'package:wukong_easy_sdk/wukong_easy_sdk.dart';
import '../core/app_config.dart';
import '../models/im_models.dart';

class ImService {
  final WuKongEasySDK _sdk = WuKongEasySDK.getInstance();
  final _messageController = StreamController<UnifiedMessage>.broadcast();
  bool connected = false;
  int _myId = 0;

  Stream<UnifiedMessage> get messages => _messageController.stream;

  Future<void> connect({required ImConnectInfo info, required int myId}) async {
    _myId = myId;
    final config = WuKongConfig(
      serverUrl: info.wsAddr,
      uid: info.uid,
      token: info.token,
      deviceId: 'flutter_${DateTime.now().millisecondsSinceEpoch}',
      deviceFlag: WuKongDeviceFlag.fromValue(AppConfig.deviceFlag),
    );
    await _sdk.init(config);
    _sdk.addEventListener(WuKongEvent.connect, (ConnectResult result) {
      connected = true;
    });
    _sdk.addEventListener(WuKongEvent.disconnect, (DisconnectInfo info) {
      connected = false;
    });
    _sdk.addEventListener(WuKongEvent.message, (Message message) {
      final payload = _normalizePayload(message.payload, message: message);
      _messageController.add(UnifiedMessage.fromPayload(payload, _myId));
    });
    await _sdk.connect();
  }

  Map<String, dynamic> _normalizePayload(dynamic payload, {Message? message}) {
    Map<String, dynamic> map;
    if (payload is Map<String, dynamic>) {
      map = Map<String, dynamic>.from(payload);
    } else if (payload is Map) {
      map = Map<String, dynamic>.from(payload);
    } else if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        map = decoded is Map ? Map<String, dynamic>.from(decoded) : {'msg_type': 'text', 'content': {'text': payload}};
      } catch (_) {
        map = {'msg_type': 'text', 'content': {'text': payload}};
      }
    } else {
      map = {'msg_type': 'text', 'content': {'text': '$payload'}};
    }

    // 兼容旧网页测试端/SDK 直接消息：payload 内缺少 from_user_id/to_user_id 时，从 WuKongIM envelope 兜底解析。
    final fromUid = '${map['from_uid'] ?? message?.fromUid ?? ''}';
    final channelId = '${map['to_uid'] ?? map['channel_id'] ?? message?.channelId ?? ''}';
    map.putIfAbsent('from_uid', () => fromUid);
    map.putIfAbsent('to_uid', () => channelId);
    map.putIfAbsent('from_user_id', () => _userIdFromUid(fromUid));
    map.putIfAbsent('to_user_id', () => _userIdFromUid(channelId) == 0 ? _myId : _userIdFromUid(channelId));
    map.putIfAbsent('msg_type', () => _legacyType(map));
    final c = map['content'];
    if (c is! Map) map['content'] = {'text': '${c ?? map['legacy']?['content'] ?? ''}'};
    return map;
  }

  int _userIdFromUid(String uid) {
    if (uid.contains('_')) return int.tryParse(uid.split('_').last) ?? 0;
    return int.tryParse(uid) ?? 0;
  }

  String _legacyType(Map<String, dynamic> map) {
    final t = int.tryParse('${map['message_type'] ?? map['type'] ?? map['legacy']?['type'] ?? 0}') ?? 0;
    if (t == 1) return 'image';
    if (t == 2) return 'transfer';
    return 'text';
  }

  Future<void> sendDirect({required String channelId, required Map<String, dynamic> payload}) async {
    await _sdk.send(channelId: channelId, channelType: WuKongChannelType.person, payload: payload);
  }

  Future<void> disconnect() async {
    connected = false;
    _sdk.disconnect();
  }

  void dispose() {
    _messageController.close();
    _sdk.disconnect();
  }
}

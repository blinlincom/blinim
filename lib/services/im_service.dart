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
      deviceFlag: WuKongDeviceFlag.app,
    );
    await _sdk.init(config);
    _sdk.addEventListener(WuKongEvent.connect, (ConnectResult result) {
      connected = true;
    });
    _sdk.addEventListener(WuKongEvent.disconnect, (DisconnectInfo info) {
      connected = false;
    });
    _sdk.addEventListener(WuKongEvent.message, (Message message) {
      final payload = _normalizePayload(message.payload);
      _messageController.add(UnifiedMessage.fromPayload(payload, _myId));
    });
    await _sdk.connect();
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return {'msg_type': 'text', 'content': {'text': payload}, 'from_user_id': 0, 'to_user_id': _myId};
    }
    return {'msg_type': 'text', 'content': {'text': '$payload'}, 'from_user_id': 0, 'to_user_id': _myId};
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

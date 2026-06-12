import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/app_logger.dart';
import 'client_device_context.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';
import '../models/call_signal.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class UserSearchResult {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  const UserSearchResult({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
  });
  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
    id: int.tryParse('${j['id'] ?? j['userid'] ?? j['uid'] ?? 0}') ?? 0,
    username: '${j['username'] ?? ''}',
    nickname: '${j['nickname'] ?? j['username'] ?? '用户'}',
    avatar: '${j['usertx'] ?? j['avatar'] ?? ''}',
  );
}

class UserProfileSummary {
  final String nickname;
  final String avatar;
  final String background;
  final String fans;
  final String follows;
  final String points;
  final String coins;
  final String vip;
  final String level;
  final String posts;
  final String comments;
  final String likes;
  final String views;

  const UserProfileSummary({
    this.nickname = '',
    this.avatar = '',
    this.background = '',
    this.fans = '0',
    this.follows = '0',
    this.points = '0',
    this.coins = '0',
    this.vip = '普通',
    this.level = '0',
    this.posts = '0',
    this.comments = '0',
    this.likes = '0',
    this.views = '0',
  });

  static bool _isEmptyLike(String value) {
    final v = value.trim().toLowerCase();
    return v.isEmpty ||
        v == '--' ||
        v == '0' ||
        v == 'false' ||
        v == '普通' ||
        v == '非会员';
  }

  bool get isVip => !_isEmptyLike(vip);

  factory UserProfileSummary.fromJson(Map<String, dynamic> j) {
    String pick(List<String> keys, [String fallback = '0']) {
      for (final key in keys) {
        final value = j[key];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
      return fallback;
    }

    return UserProfileSummary(
      nickname: pick(['nickname', 'name', 'nick_name'], ''),
      avatar: pick(['avatar', 'usertx', 'user_avatar', 'headimg'], ''),
      background: pick(['background', 'user_background', 'bg', 'cover'], ''),
      fans: pick(['fans', 'fan', 'fan_count', 'fans_count', 'fensi']),
      follows: pick([
        'follows',
        'follow',
        'follow_count',
        'follows_count',
        'guanzhu',
      ]),
      points: pick([
        'points',
        'point',
        'integral',
        'score',
        'experience',
        'exp',
      ]),
      coins: pick(['coins', 'coin', 'money', 'gold', 'balance']),
      vip: pick(['vip', 'vip_time', 'vip_days', 'member', 'membership'], '普通'),
      level: pick([
        'level',
        'lv',
        'grade',
        'user_level',
        'userlevel',
        'user_grade',
        'dengji',
      ], '0'),
      posts: pick(['posts', 'post_count', 'posts_count']),
      comments: pick(['comments', 'comment_count', 'comments_count']),
      likes: pick(['likes', 'like_count', 'likes_count']),
      views: pick(['views', 'view_count', 'browse_count', 'history_count']),
    );
  }
}

class ImOnlineStatus {
  final bool online;
  final String device;
  const ImOnlineStatus({required this.online, this.device = ''});

  String get label {
    if (!online) return '暂时离线';
    final d = device.trim().toLowerCase();
    if (d.contains('ios') || d.contains('iphone') || d.contains('ipad')) {
      return 'iOS在线';
    }
    if (d.contains('android') ||
        d.contains('mobile') ||
        d.contains('phone') ||
        d == '2') {
      return '手机在线';
    }
    if (d.contains('web') ||
        d.contains('h5') ||
        d.contains('browser') ||
        d == '1') {
      return 'Web在线';
    }
    if (d.contains('pc') ||
        d.contains('desktop') ||
        d.contains('windows') ||
        d.contains('mac') ||
        d.contains('linux') ||
        d == '3') {
      return '电脑在线';
    }
    return '在线';
  }
}

class ApiService {
  final String baseUrl;
  const ApiService({this.baseUrl = AppConfig.apiBase});

  String _md5(String text) => crypto.md5.convert(utf8.encode(text)).toString();

  String _aesDecrypt(String encryptedText) {
    if (AppConfig.apiAesKey.length != 16) {
      throw ApiException('数据读取失败，请稍后再试');
    }
    final key = encrypt.Key.fromUtf8(AppConfig.apiAesKey);
    final iv = encrypt.IV.fromUtf8(AppConfig.apiAesKey);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return encrypter.decrypt64(encryptedText.trim(), iv: iv);
  }

  String _base64DecodeText(String text) {
    final normalized = base64.normalize(text.trim());
    return utf8.decode(base64Decode(normalized));
  }

  dynamic _tryJsonDecode(String text) => jsonDecode(text);

  Map<String, dynamic> _decodeResponseText(String text) {
    final raw = text.trim();
    final candidates = <String>[raw];

    try {
      candidates.add(_base64DecodeText(raw));
    } catch (_) {}

    try {
      candidates.add(_aesDecrypt(raw));
    } catch (_) {}

    for (final item in candidates) {
      try {
        final decoded = _tryJsonDecode(item);
        if (decoded is Map<String, dynamic>)
          return _normalizeDecodedMap(decoded);
        if (decoded is Map)
          return _normalizeDecodedMap(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }

    throw ApiException('数据读取失败，请稍后再试');
  }

  Map<String, dynamic> _normalizeDecodedMap(Map<String, dynamic> jsonBody) {
    _verifyTimestamp(jsonBody);
    final data = jsonBody['data'];
    if (data is String && data.trim().isNotEmpty) {
      final decoded = _decodeEncryptedDataField(data);
      if (decoded != null) jsonBody = {...jsonBody, 'data': decoded};
    }
    if (AppConfig.verifyResponseSign) {
      try {
        _verifySign(jsonBody);
      } catch (_) {
        // 后台加密已成功解开且 code 校验通过时，签名差异不应导致商业页面整页空白。
        // 默然系统不同版本可能在 JSON 转义细节上与 Dart jsonEncode 不完全一致。
      }
    }
    return jsonBody;
  }

  dynamic _decodeEncryptedDataField(String encrypted) {
    final candidates = <String>[];
    try {
      candidates.add(_base64DecodeText(encrypted));
    } catch (_) {}
    try {
      candidates.add(_aesDecrypt(encrypted));
    } catch (_) {}
    for (final item in candidates) {
      try {
        return jsonDecode(item);
      } catch (_) {}
    }
    return null;
  }

  void _verifyTimestamp(Map<String, dynamic> jsonBody) {
    final value = jsonBody['timestamp'] ?? jsonBody['time'] ?? jsonBody['ts'];
    if (value == null) return;
    final raw = int.tryParse('$value');
    if (raw == null || raw <= 0) return;
    final responseMs = raw > 9999999999 ? raw : raw * 1000;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffSeconds = ((nowMs - responseMs).abs() / 1000).round();
    if (diffSeconds > AppConfig.responseTimestampMaxSkewSeconds) {
      throw ApiException('网络状态不稳定，请稍后再试');
    }
  }

  String _buildDataSign(dynamic data) {
    final sb = StringBuffer();
    if (data is Map) {
      data.forEach((key, value) {
        sb.write('$key=${jsonEncode(value)}&');
      });
    } else if (data is List) {
      for (var i = 0; i < data.length; i++) {
        sb.write('$i=${jsonEncode(data[i])}&');
      }
    }
    sb.write('secretKey=${AppConfig.apiSignSecretKey}');
    return _md5(sb.toString());
  }

  void _verifySign(Map<String, dynamic> jsonBody) {
    final sign = '${jsonBody['sign'] ?? ''}';
    if (sign.isEmpty || jsonBody['data'] == null) return;
    final localSign = _buildDataSign(jsonBody['data']);
    if (localSign != sign) {
      throw ApiException('数据校验失败，请稍后再试');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = {
      'appid': '${AppConfig.appId}',
      'appkey': AppConfig.apiAppKey,
      'timestamp': '$nowSeconds',
      'time': '$nowSeconds',
      ...data.map((k, v) => MapEntry(k, '$v')),
    };
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: body,
            )
            .timeout(const Duration(seconds: 20));
        final text = utf8.decode(res.bodyBytes);
        final jsonBody = _decodeResponseText(text);
        if ('${jsonBody['code']}' != '1') {
          final msg = '${jsonBody['msg'] ?? ''}'.trim();
          throw ApiException(msg.isEmpty ? '操作未完成，请稍后再试' : msg);
        }
        return jsonBody;
      } on ApiException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (!_isTransientNetworkError(e) || attempt == 2) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw ApiException(_friendlyNetworkMessage(lastError));
  }

  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final text = '$error'.toLowerCase();
    return text.contains('software caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('broken pipe') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('clientexception') ||
        text.contains('socketexception');
  }

  String _friendlyNetworkMessage(Object? error) {
    final text = '$error';
    if (error is TimeoutException || text.contains('Future not completed')) {
      return '网络响应超时，请稍后再试';
    }
    if (text.contains('Software caused connection abort') ||
        text.contains('Connection reset') ||
        text.contains('ClientException')) {
      return '网络刚恢复，正在重新连接，请稍后再试';
    }
    return '网络连接异常，请稍后再试';
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    final source = value is List ? value : const <dynamic>[];
    final rows = <Map<String, dynamic>>[];
    for (final item in source) {
      if (item is Map<String, dynamic>) {
        rows.add(item);
      } else if (item is Map) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }
    return rows;
  }

  dynamic _pickListSource(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const [
        'list',
        'data',
        'records',
        'items',
        'products',
        'goods',
        'rows',
      ]) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> getAppInfo() async {
    final r = await _post('/get_app_info', const <String, dynamic>{});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<UserSession> login(String username, String password) async {
    final device = ClientDeviceContext.current();
    final r = await _post('/login', {
      'username': username,
      'password': password,
      ...device.toApiFields(),
    });
    return UserSession.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<ImConnectInfo> getImConnectInfo(String token) async {
    final device = ClientDeviceContext.current();
    final r = await _post('/get_im_connect_info', {
      'usertoken': token,
      ...device.toApiFields(),
    });
    return ImConnectInfo.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<List<ConversationItem>> getMessageList(String token) async {
    final r = await _post('/get_message_list', {'usertoken': token});
    final data = r['data'];
    final list = data is List
        ? data
        : (data is Map && data['list'] is List ? data['list'] : const []);
    final result = <ConversationItem>[];
    for (final e in list) {
      try {
        if (e is Map<String, dynamic>) {
          result.add(ConversationItem.fromJson(e));
        } else if (e is Map) {
          result.add(ConversationItem.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (_) {
        // 单条会话数据异常不影响整个最近会话列表。
      }
    }
    return result;
  }

  Future<List<UnifiedMessage>> getChatLog({
    required String token,
    required int receiverId,
    required int myId,
    int page = 1,
    int limit = 30,
  }) async {
    final r = await _post('/get_chat_log', {
      'usertoken': token,
      'receiver_id': receiverId,
      'page': page,
      'limit': limit,
    });
    final data = Map<String, dynamic>.from(r['data'] ?? {});
    final list = data['list'];
    if (list is List) {
      return list
          .map(
            (e) =>
                UnifiedMessage.fromHistory(Map<String, dynamic>.from(e), myId),
          )
          .toList()
          .reversed
          .toList();
    }
    return [];
  }

  Future<String> clearPeerChatHistory({
    required String token,
    required int peerId,
  }) async {
    final r = await _postAny(const [
      '/clear_chat_history',
      '/delete_chat_history',
      '/clear_im_chat_history',
      '/delete_im_chat_history',
      '/clear_chat_log',
      '/delete_chat_log',
    ], {
      'usertoken': token,
      'peer_id': peerId,
      'friend_id': peerId,
      'receiver_id': peerId,
      'user_id': peerId,
      'both': 1,
      'delete_both': 1,
    });
    return '${r['msg'] ?? '聊天记录已清空'}';
  }

  Future<List<ImGroup>> getImGroups(String token) async {
    final r = await _post('/get_im_group_list', {'usertoken': token});
    return _asMapList(_pickListSource(r['data']))
        .map(ImGroup.fromJson)
        .where((g) => g.id > 0)
        .toList();
  }

  Future<ImGroup> createImGroup({
    required String token,
    required String name,
    required List<int> memberIds,
  }) async {
    final r = await _post('/create_im_group', {
      'usertoken': token,
      'name': name,
      'member_ids': memberIds.join(','),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('建群失败');
  }

  Future<int> sendGroupMessage({
    required String token,
    required int groupId,
    required String content,
    Map<String, dynamic>? payload,
  }) async {
    final r = await _post('/send_im_group_message', {
      'usertoken': token,
      'group_id': groupId,
      'content': content,
      if (payload != null) ..._flattenMessagePayload(payload),
    });
    return int.tryParse('${r['data']?['message_id'] ?? 0}') ?? 0;
  }
  Future<List<UnifiedMessage>> getGroupChatLog({
    required String token,
    required int groupId,
    required int myId,
    int page = 1,
    int limit = 30,
  }) async {
    final r = await _post('/get_im_group_chat_log', {
      'usertoken': token,
      'group_id': groupId,
      'page': page,
      'limit': limit,
    });
    final data = Map<String, dynamic>.from(r['data'] ?? {});
    final list = data['list'];
    if (list is List) {
      return list
          .map((e) => UnifiedMessage.fromHistory(Map<String, dynamic>.from(e), myId))
          .toList()
          .reversed
          .toList();
    }
    return [];
  }

  Future<ImGroup> getImGroupInfo({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(const ['/get_im_group_info', '/im_group_info'], {
      'usertoken': token,
      'group_id': groupId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('群资料读取失败');
  }

  Future<List<ImGroupMember>> getImGroupMembers({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(const ['/get_im_group_members', '/im_group_members', '/get_group_members'], {
      'usertoken': token,
      'group_id': groupId,
    });
    return _asMapList(_pickListSource(r['data']))
        .map(ImGroupMember.fromJson)
        .where((m) => m.userId > 0)
        .toList();
  }

  Future<ImGroup> updateImGroup({
    required String token,
    required int groupId,
    String? name,
    String? avatar,
  }) async {
    final r = await _postAny(const ['/update_im_group', '/edit_im_group', '/set_im_group_info'], {
      'usertoken': token,
      'group_id': groupId,
      if (name != null) 'name': name,
      if (name != null) 'group_name': name,
      if (avatar != null) 'avatar': avatar,
      if (avatar != null) 'group_avatar': avatar,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    return ImGroup(id: groupId, groupNo: '', name: name ?? '群聊', avatar: avatar ?? '', memberCount: 0);
  }

  Future<String> addImGroupMembers({required String token, required int groupId, required List<int> userIds}) async {
    final r = await _postAny(const ['/add_im_group_members', '/invite_im_group_members', '/group_invite_members'], {
      'usertoken': token,
      'group_id': groupId,
      'user_ids': userIds.join(','),
      'member_ids': userIds.join(','),
    });
    return '${r['msg'] ?? '已邀请成员'}';
  }

  Future<String> removeImGroupMember({required String token, required int groupId, required int userId}) async {
    final r = await _postAny(const ['/remove_im_group_member', '/kick_im_group_member', '/delete_im_group_member'], {
      'usertoken': token,
      'group_id': groupId,
      'user_id': userId,
      'member_id': userId,
    });
    return '${r['msg'] ?? '已移除成员'}';
  }

  Future<String> setImGroupAdmin({required String token, required int groupId, required int userId, required bool admin}) async {
    final r = await _postAny(const ['/set_im_group_admin', '/set_group_admin', '/im_group_set_admin'], {
      'usertoken': token,
      'group_id': groupId,
      'user_id': userId,
      'member_id': userId,
      'admin': admin ? 1 : 0,
      'role': admin ? 'admin' : 'member',
    });
    return '${r['msg'] ?? (admin ? '已设为管理员' : '已取消管理员')}';
  }

  Future<String> transferImGroup({required String token, required int groupId, required int userId}) async {
    final r = await _postAny(const ['/transfer_im_group', '/transfer_group_owner', '/im_group_transfer'], {
      'usertoken': token,
      'group_id': groupId,
      'user_id': userId,
      'new_owner_id': userId,
    });
    return '${r['msg'] ?? '已转让群主'}';
  }

  Future<String> leaveImGroup({required String token, required int groupId}) async {
    final r = await _postAny(const ['/leave_im_group', '/quit_im_group', '/exit_im_group'], {
      'usertoken': token,
      'group_id': groupId,
    });
    return '${r['msg'] ?? '已退出群聊'}';
  }

  Future<String> dismissImGroup({required String token, required int groupId}) async {
    final r = await _postAny(const ['/dismiss_im_group', '/delete_im_group', '/disband_im_group'], {
      'usertoken': token,
      'group_id': groupId,
    });
    return '${r['msg'] ?? '已解散群聊'}';
  }

  Future<Map<String, dynamic>> _postAny(List<String> paths, Map<String, dynamic> body) async {
    Object? lastError;
    for (final path in paths) {
      try {
        return await _post(path, body);
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('接口暂不可用：${lastError ?? ''}');
  }


  Future<List<UserSearchResult>> getFriends(String token) async {
    final paths = const ['/get_friends', '/get_friend_list', '/friends'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {'usertoken': token});
        return _asMapList(
          _pickListSource(r['data']),
        ).map(UserSearchResult.fromJson).where((u) => u.id > 0).toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('好友列表暂时不可用：${lastError ?? ''}');
  }

  Future<bool> isFriend(String token, int userId) async {
    try {
      final r = await _post('/is_friend', {
        'usertoken': token,
        'friend_id': userId,
        'user_id': userId,
      });
      final data = r['data'];
      final value = data is Map
          ? data['is_friend'] ?? data['friend'] ?? data['status']
          : data;
      return value == true ||
          '$value' == '1' ||
          '$value'.toLowerCase() == 'true';
    } catch (_) {
      try {
        final friends = await getFriends(token);
        return friends.any((u) => u.id == userId);
      } catch (_) {
        return false;
      }
    }
  }

  Future<String> deleteFriend(String token, int userId) async {
    final paths = const ['/delete_friend', '/remove_friend', '/del_friend'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'friend_id': userId,
          'user_id': userId,
        });
        return '${r['msg'] ?? '已删除好友'}';
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('删除好友失败：${lastError ?? ''}');
  }

  Future<String> addFriend(
    String token,
    int userId, {
    String message = '',
  }) async {
    final paths = const [
      '/add_friend',
      '/apply_friend',
      '/friend_apply',
      '/follow_users',
    ];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'friend_id': userId,
          'user_id': userId,
          'followedid': userId,
          if (message.trim().isNotEmpty) 'message': message.trim(),
        });
        return '${r['msg'] ?? '已发送好友申请'}';
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('添加好友失败：${lastError ?? ''}');
  }

  Future<String> handleFriendRequest(
    String token, {
    required int userId,
    required bool accept,
  }) async {
    final paths = const ['/handle_friend_request', '/friend_request_handle'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'user_id': userId,
          'friend_id': userId,
          'from_user_id': userId,
          'action': accept ? 'accept' : 'reject',
          'status': accept ? 1 : 2,
        });
        return '${r['msg'] ?? (accept ? '已通过好友申请' : '已拒绝好友申请')}';
      } catch (e) {
        lastError = e;
      }
    }
    if (accept) return addFriend(token, userId, message: '我通过了你的好友申请');
    throw ApiException('处理好友申请失败：${lastError ?? ''}');
  }

  Future<int> sendMessage({
    required String token,
    required int receiverId,
    required String content,
    int messageType = 0,
    Map<String, dynamic>? payload,
  }) async {
    final contentMap = payload?['content'];
    final payloadType = '${payload?['msg_type'] ?? ''}';
    final wireContent = payloadType == 'transfer' && contentMap is Map
        ? '${contentMap['amount'] ?? content}'
        : payloadType == 'emoji' && contentMap is Map
        ? _jsonEncodeAscii(
            contentMap['emoji'] ?? contentMap['text'] ?? content,
          ).replaceAll(RegExp(r'^"|"$'), '')
        : content;
    final r = await _post('/send_message', {
      'usertoken': token,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': wireContent,
      if (payload != null) ..._flattenMessagePayload(payload),
    });
    return int.tryParse('${r['data']?['message_id'] ?? 0}') ?? 0;
  }

  Future<Map<String, dynamic>> getTurnCredentials(String token) async {
    final r = await _post('/get_turn_credentials', {'usertoken': token});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getIceServers(String token) async {
    try {
      final data = await getTurnCredentials(token);
      final raw = data['ice_servers'] ?? data['iceServers'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return AppConfig.rtcIceServers;
  }

  Future<int> sendImCallSignal({
    required String token,
    required int toUserId,
    required Map<String, dynamic> payload,
  }) async {
    final content = payload['content'];
    final signal = CallSignal.tryParse(payload);
    final normalizedPayload = signal?.toPayload() ?? payload;
    final normalizedContent = normalizedPayload['content'];
    final contentMap = normalizedContent is Map
        ? Map<String, dynamic>.from(normalizedContent)
        : content is Map
        ? Map<String, dynamic>.from(content)
        : const <String, dynamic>{};
    final body = {
      'usertoken': token,
      'to_user_id': toUserId,
      'receiver_id': toUserId,
      'schema': '${normalizedPayload['schema'] ?? CallSignal.schema}',
      'msg_type': '${normalizedPayload['msg_type'] ?? CallSignal.legacyMsgType}',
      'signal_type': '${normalizedPayload['signal_type'] ?? CallSignal.msgType}',
      'call_id': '${contentMap['call_id'] ?? normalizedPayload['call_id'] ?? ''}',
      'signal_id': '${contentMap['signal_id'] ?? normalizedPayload['signal_id'] ?? normalizedPayload['client_msg_no'] ?? ''}',
      'action': '${contentMap['action'] ?? normalizedPayload['action'] ?? ''}',
      'call_action': '${contentMap['action'] ?? normalizedPayload['action'] ?? contentMap['type'] ?? ''}',
      'signal_action': '${contentMap['action'] ?? normalizedPayload['action'] ?? contentMap['type'] ?? ''}',
      'media': '${contentMap['media'] ?? normalizedPayload['media'] ?? ''}',
      'client_msg_no': '${normalizedPayload['client_msg_no'] ?? contentMap['signal_id'] ?? ''}',
      ..._flattenMessagePayload(normalizedPayload),
    };
    AppLogger.api("send_im_call_signal request call=${body['call_id']} action=${body['action']} to=$toUserId signal=${body['signal_id']}");
    final r = await _post('/send_im_call_signal', body);
    AppLogger.api("send_im_call_signal response call=${body['call_id']} action=${body['action']}", data: r['data']);
    return int.tryParse('${r['data']?['id'] ?? r['data']?['message_id'] ?? 0}') ?? 0;
  }

  Future<List<Map<String, dynamic>>> getImCallSignals({
    required String token,
    int sinceId = 0,
    String callId = '',
    int peerId = 0,
    int limit = 50,
  }) async {
    final r = await _post('/get_im_call_signals', {
      'usertoken': token,
      'since_id': sinceId,
      if (callId.isNotEmpty) 'call_id': callId,
      if (peerId > 0) 'peer_id': peerId,
      'limit': limit,
    });
    AppLogger.api('get_im_call_signals response since=$sinceId call=$callId peer=$peerId');
    final data = r['data'];
    final List<dynamic> list = data is List
        ? data
        : (data is Map && data['list'] is List
              ? List<dynamic>.from(data['list'] as List)
              : <dynamic>[]);
    final rows = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final signal = CallSignal.tryParse(row);
      if (signal == null) {
        rows.add(row);
        continue;
      }
      final payload = signal.toPayload();
      rows.add({
        ...row,
        'call_id': signal.callId,
        'signal_id': signal.signalId,
        'action': signal.action,
        'call_action': signal.action,
        'signal_action': signal.action,
        'media': signal.media,
        'from_user_id': signal.fromUserId,
        'to_user_id': signal.toUserId,
        'payload': payload,
      });
    }
    return rows;
  }

  String _jsonEncodeAscii(Object? value) {
    final json = jsonEncode(value);
    final buffer = StringBuffer();
    for (final rune in json.runes) {
      if (rune <= 0x7f) {
        buffer.writeCharCode(rune);
      } else if (rune <= 0xffff) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        final code = rune - 0x10000;
        final high = 0xd800 + (code >> 10);
        final low = 0xdc00 + (code & 0x3ff);
        buffer
          ..write('\\u${high.toRadixString(16).padLeft(4, '0')}')
          ..write('\\u${low.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return buffer.toString();
  }

  Map<String, String> _flattenMessagePayload(Map<String, dynamic> payload) {
    final content = payload['content'];
    final contentMap = content is Map
        ? Map<String, dynamic>.from(content)
        : const <String, dynamic>{};
    final type = '${payload['msg_type'] ?? ''}';
    final url =
        '${contentMap['url'] ?? contentMap['file_url'] ?? contentMap['image'] ?? contentMap['src'] ?? ''}';
    final name = '${contentMap['name'] ?? contentMap['file_name'] ?? ''}';
    return {
      'msg_type': type,
      'im_payload': _jsonEncodeAscii(payload),
      'payload': _jsonEncodeAscii(payload),
      if (type == 'call') ...{
        'call_id': '${contentMap['call_id'] ?? payload['call_id'] ?? ''}',
        'call_action': '${contentMap['action'] ?? contentMap['type'] ?? ''}',
        'dedupe_key': '${contentMap['dedupe_key'] ?? contentMap['call_record_key'] ?? ''}',
      },
      if (type == 'call_record') ...{
        'call_id': '${contentMap['call_id'] ?? payload['call_id'] ?? ''}',
        'dedupe_key': '${contentMap['call_record_key'] ?? contentMap['dedupe_key'] ?? ''}',
      },
      if (type == 'group_call_invite' ||
          type == 'group_call_join' ||
          type == 'group_call_leave' ||
          type == 'group_call_record') ...{
        'call_id':
            '${contentMap['room_id'] ?? contentMap['call_id'] ?? payload['call_id'] ?? ''}',
        'dedupe_key':
            '${contentMap['call_record_key'] ?? contentMap['dedupe_key'] ?? payload['client_msg_no'] ?? ''}',
      },
      if (type == 'transfer') ...{
        'money': '${contentMap['amount'] ?? ''}',
        'amount': '${contentMap['amount'] ?? ''}',
        'payment': '${contentMap['payment'] ?? contentMap['type'] ?? 0}',
        'type': '${contentMap['payment'] ?? contentMap['type'] ?? 0}',
        'note': '${contentMap['note'] ?? ''}',
        'image_path': '',
        'file_path': '',
        'file_name': name,
      } else if (type == 'image') ...{
        'image_path': url,
        'file_path': url,
        'file_name': name,
      } else if (type == 'video' || type == 'file') ...{
        'image_path': '',
        'file_path': url,
        'file_name': name,
      } else ...{
        'image_path': '${contentMap['image_path'] ?? ''}',
        'file_path': '${contentMap['file_path'] ?? ''}',
        'file_name': name,
      },
      };
  }

  Future<Map<String, dynamic>> uploadChatFile({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    final paths = const ['/upload_file', '/upload', '/upload_image'];
    Object? lastError;
    for (final path in paths) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final request = http.MultipartRequest('POST', uri)
          ..fields.addAll({
            'appid': '${AppConfig.appId}',
            'appkey': AppConfig.apiAppKey,
            'timestamp': '$nowSeconds',
            'time': '$nowSeconds',
            'usertoken': token,
          })
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
        final streamed = await request.send().timeout(
          const Duration(seconds: 30),
        );
        final res = await http.Response.fromStream(streamed);
        final jsonBody = _decodeResponseText(utf8.decode(res.bodyBytes));
        if ('${jsonBody['code']}' != '1')
          throw ApiException('${jsonBody['msg'] ?? '上传失败'}');
        final data = jsonBody['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return {'url': data ?? ''};
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('文件上传失败：${lastError ?? '请稍后再试'}');
  }

  Future<List<UserSearchResult>> searchUsers(
    String token,
    String keyword,
  ) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    final attempts = [
      {
        'usertoken': token,
        'keyword': kw,
        'search': kw,
        'username': kw,
        'userid': kw,
        'user_id': kw,
      },
      {'usertoken': token, 'search': kw},
      {'usertoken': token, 'keyword': kw},
      {'usertoken': token, 'username': kw},
      {'usertoken': token, 'userid': kw},
    ];
    Object? lastError;
    for (final body in attempts) {
      try {
        final r = await _post('/search_user', body);
        final data = r['data'];
        final list = data is List
            ? data
            : (data is Map && data['list'] is List ? data['list'] : const []);
        final users = <UserSearchResult>[];
        for (final item in list) {
          try {
            if (item is Map<String, dynamic>) {
              users.add(UserSearchResult.fromJson(item));
            } else if (item is Map) {
              users.add(
                UserSearchResult.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          } catch (_) {}
        }
        final parsed = users.where((u) => u.id > 0).toList();
        if (parsed.isNotEmpty) return parsed;
        lastError = '没有匹配用户';
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('搜索暂时不可用：${lastError ?? '请稍后再试'}');
  }

  Future<UserProfileSummary> getUserOtherInformation(String token) async {
    final r = await _post('/get_user_other_information', {'usertoken': token});
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      final merged = Map<String, dynamic>.from(data);
      for (final key in ['user', 'user_info', 'userinfo', 'info']) {
        final nested = data[key];
        if (nested is Map) merged.addAll(Map<String, dynamic>.from(nested));
      }
      return UserProfileSummary.fromJson(merged);
    }
    if (data is Map) {
      final merged = Map<String, dynamic>.from(data);
      for (final key in ['user', 'user_info', 'userinfo', 'info']) {
        final nested = data[key];
        if (nested is Map) merged.addAll(Map<String, dynamic>.from(nested));
      }
      return UserProfileSummary.fromJson(merged);
    }
    return const UserProfileSummary();
  }

  Future<String> userSignIn(String token) async {
    final r = await _post('/user_sign_in', {'usertoken': token});
    return '${r['msg'] ?? '签到成功'}';
  }

  Future<List<Map<String, dynamic>>> getSectionList(String token) async {
    try {
      final r = await _post('/get_section_list', {
        if (token.trim().isNotEmpty) 'usertoken': token,
      });
      return _asMapList(_pickListSource(r['data']));
    } catch (_) {
      // 板块列表是公开结构；登录态异常时降级为无 token 请求，避免首页/发布页使用帖子反推的错误板块结构。
      final r = await _post('/get_section_list', const <String, dynamic>{});
      return _asMapList(_pickListSource(r['data']));
    }
  }

  Future<List<Map<String, dynamic>>> getForumPosts(
    String token, {
    int page = 1,
    int limit = 10,
    String sectionId = '',
  }) async {
    Map<String, dynamic> extract(Map<String, dynamic> r) => r;
    List<Map<String, dynamic>> parse(Map<String, dynamic> r) {
      return _asMapList(_pickListSource(r['data']));
    }

    final params = {
      'limit': limit,
      'page': page,
      if (sectionId.trim().isNotEmpty) 'sectionid': sectionId.trim(),
      'sort': 'sticky,featured,popular,score,create_time',
      'sortOrder': 'desc,desc,desc,desc,desc',
    };
    try {
      final r = await _post('/get_posts_list', {'usertoken': token, ...params});
      final rows = parse(extract(r));
      if (rows.isNotEmpty) return rows;
    } catch (_) {}

    final fallback = await _post('/get_posts_list', params);
    return parse(fallback);
  }

  Future<List<String>> getSearchKeywords({int limit = 8}) async {
    try {
      final r = await _post('/get_search_keywords', {'limit': limit});
      final rows = _asMapList(_pickListSource(r['data']));
      final words = <String>[];
      for (final row in rows) {
        for (final key in const [
          'keyword',
          'word',
          'name',
          'title',
          'search_word',
        ]) {
          final value = row[key];
          if (value != null &&
              '$value'.trim().isNotEmpty &&
              '$value' != 'null') {
            words.add('$value'.trim());
            break;
          }
        }
      }
      if (words.isNotEmpty) return words.take(limit).toList();
    } catch (_) {}
    try {
      final app = await getAppInfo();
      final raw = '${app['site_keywords'] ?? app['keywords'] ?? ''}';
      return raw
          .split(RegExp(r'[,，\s]+'))
          .where((e) => e.trim().isNotEmpty)
          .map((e) => e.trim())
          .take(limit)
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<String> publishPost(
    String token, {
    required String sectionId,
    String subsectionId = '',
    required String title,
    required String content,
    String video = '',
    String videoCover = '',
  }) async {
    final r = await _post('/post', {
      'usertoken': token,
      'sectionid': sectionId,
      if (subsectionId.trim().isNotEmpty) 'subsectionid': subsectionId.trim(),
      'paid_reading': '0',
      'file_download_method': '0',
      'title': title,
      'content': content,
      if (video.trim().isNotEmpty) 'video': video.trim(),
      if (videoCover.trim().isNotEmpty) 'video_img': videoCover.trim(),
    });
    return '${r['msg'] ?? '发布成功'}';
  }

  Future<Map<String, dynamic>> getPostInformation(
    String token,
    String postId,
  ) async {
    final r = await _post('/get_post_information', {
      if (token.trim().isNotEmpty) 'usertoken': token,
      'postid': postId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> getPostComments(
    String postId, {
    int page = 1,
    int limit = 20,
    String commentId = '0',
  }) async {
    final r = await _post('/get_list_comments', {
      'postid': postId,
      'status': 1,
      'comment_id': commentId,
      'sort': 'time',
      'sortOrder': 'desc',
      'limit': limit,
      'page': page,
    });
    return _asMapList(_pickListSource(r['data']));
  }

  Future<String> toggleFollowUser(String token, String followedId) async {
    final r = await _post('/follow_users', {
      'usertoken': token,
      'followedid': followedId,
    });
    return '${r['msg'] ?? '操作成功'}';
  }

  Future<Map<String, dynamic>> togglePostLike(
    String token,
    String postId,
  ) async {
    final r = await _post('/like_posts', {
      'usertoken': token,
      'postid': postId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>)
      return {'msg': r['msg'] ?? '操作成功', ...data};
    if (data is Map)
      return {'msg': r['msg'] ?? '操作成功', ...Map<String, dynamic>.from(data)};
    return {'msg': r['msg'] ?? '操作成功'};
  }

  Future<String> togglePostCollection(String token, String postId) async {
    final r = await _post('/collection_posts', {
      'usertoken': token,
      'postid': postId,
    });
    return '${r['msg'] ?? '操作成功'}';
  }

  Future<String> postComment(
    String token,
    String postId,
    String content, {
    String parentId = '0',
  }) async {
    final r = await _post('/post_comment', {
      'usertoken': token,
      'postid': postId,
      'content': content,
      'parentid': parentId,
    });
    return '${r['msg'] ?? '评论成功'}';
  }

  Future<List<Map<String, dynamic>>> getProductList({
    int page = 1,
    int limit = 10,
  }) async {
    final r = await _post('/product_list', {'limit': limit, 'page': page});
    final data = r['data'];
    return _asMapList(_pickListSource(data));
  }

  Future<Map<String, dynamic>> getProductInformation(String shopId) async {
    final r = await _post('/get_product_information', {'shopid': shopId});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> buyGoods(String token, String shopId) async {
    final r = await _post('/buy_goods', {'usertoken': token, 'shopid': shopId});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'msg': r['msg'] ?? '购买成功'};
  }

  Future<List<Map<String, dynamic>>> getApiList(
    String token,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await _post(path, {'usertoken': token, ...extra});
    final data = r['data'];
    return _asMapList(_pickListSource(data));
  }

  Future<Map<String, dynamic>> getApiData(
    String token,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await _post(path, {'usertoken': token, ...extra});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'value': data ?? r['msg'] ?? 'success'};
  }

  Future<List<Map<String, dynamic>>> getMessageNotifications(
    String token, {
    int page = 1,
    int limit = 30,
    bool unreadOnly = false,
  }) async {
    final r = await _post(
      unreadOnly
          ? '/get_unread_message_notifications'
          : '/get_message_notifications',
      {'usertoken': token, 'page': page, 'limit': limit},
    );
    return _asMapList(_pickListSource(r['data']));
  }

  Future<String> clearMessageNotification(
    String token, {
    String notificationId = '',
  }) async {
    final r = await _post('/clear_message_notification', {
      'usertoken': token,
      if (notificationId.trim().isNotEmpty) 'id': notificationId.trim(),
    });
    return '${r['msg'] ?? '已处理'}';
  }

  Future<ImOnlineStatus> reportImOnlineHeartbeat({
    required String token,
    bool online = true,
  }) async {
    final device = ClientDeviceContext.current();
    final r = await _post('/im_online_heartbeat', {
      'usertoken': token,
      ...device.toApiFields(),
      'online': online ? 1 : 0,
    });
    final data = r['data'];
    if (data is Map) {
      final value = data['online'];
      final isOnline = value is bool
          ? value
          : '$value' == '1' || '$value'.toLowerCase() == 'true';
      return ImOnlineStatus(
        online: isOnline,
        device:
            '${data['device'] ?? data['platform'] ?? data['terminal'] ?? data['device_flag'] ?? ''}',
      );
    }
    return ImOnlineStatus(online: online, device: device.device);
  }

  String _pickOnlineDevice(Map data) {
    String normalize(dynamic value) => value == null ? '' : '$value'.trim();
    bool isOnlineValue(dynamic value) =>
        value == true || '$value' == '1' || '$value'.toLowerCase() == 'true' || '$value'.toLowerCase() == 'online';
    bool isMobileValue(String value) {
      final d = value.trim().toLowerCase();
      return d.contains('android') ||
          d.contains('ios') ||
          d.contains('iphone') ||
          d.contains('ipad') ||
          d.contains('mobile') ||
          d.contains('phone') ||
          d == '2' ||
          d == '4';
    }

    final devices = data['devices'] ?? data['online_devices'] ?? data['device_list'];
    if (devices is List && devices.isNotEmpty) {
      Map? firstOnline;
      Map? mobileOnline;
      for (final item in devices) {
        if (item is! Map) continue;
        final online = isOnlineValue(item['online'] ?? item['is_online'] ?? item['status']);
        if (!online) continue;
        firstOnline ??= item;
        final value = normalize(item['latest_device'] ??
            item['current_device'] ??
            item['device'] ??
            item['platform'] ??
            item['terminal'] ??
            item['device_type'] ??
            item['device_flag']);
        if (value.isNotEmpty && isMobileValue(value)) {
          mobileOnline = item;
          break;
        }
      }
      final best = mobileOnline ?? firstOnline;
      if (best != null) {
        final value = normalize(best['latest_device'] ??
            best['current_device'] ??
            best['device'] ??
            best['platform'] ??
            best['terminal'] ??
            best['device_type'] ??
            best['device_flag']);
        if (value.isNotEmpty) return value;
      }
    }

    final direct = data['latest_device'] ??
        data['current_device'] ??
        data['last_device'] ??
        data['active_device'] ??
        data['latest_platform'] ??
        data['current_platform'] ??
        data['last_platform'] ??
        data['terminal'] ??
        data['device_type'] ??
        data['platform'] ??
        data['client'] ??
        data['device'];
    final directValue = normalize(direct);
    if (directValue.isNotEmpty) return directValue;
    final flag = data['device_flag'];
    if ('$flag' == '2') return 'android';
    if ('$flag' == '4') return 'ios';
    if ('$flag' == '1') return 'web';
    return '';
  }

  Future<ImOnlineStatus> getImOnlineStatus({
    required String token,
    required int userId,
  }) async {
    final r = await _post('/get_im_online_status', {
      'usertoken': token,
      'user_id': userId,
    });
    final data = r['data'];
    if (data is Map) {
      final value = data['online'] ?? data['is_online'] ?? data['status'];
      final online = value is bool
          ? value
          : '$value' == '1' ||
                '$value'.toLowerCase() == 'true' ||
                '$value'.toLowerCase() == 'online';
      final device = _pickOnlineDevice(data);
      return ImOnlineStatus(online: online, device: device);
    }
    return const ImOnlineStatus(online: false);
  }
}

import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';

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
    return v.isEmpty || v == '--' || v == '0' || v == 'false' || v == '普通' || v == '非会员';
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
      level: pick(['level', 'lv', 'grade', 'user_level', 'userlevel', 'user_grade', 'dengji'], '0'),
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
    if (d.contains('android') || d.contains('mobile') || d.contains('phone') || d == '2') {
      return '手机在线';
    }
    if (d.contains('web') || d.contains('h5') || d.contains('browser') || d == '1') {
      return 'Web在线';
    }
    if (d.contains('pc') || d.contains('desktop') || d.contains('windows') || d.contains('mac') || d.contains('linux') || d == '3') {
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
    if (AppConfig.verifyResponseSign) _verifySign(jsonBody);
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
  }

  Future<Map<String, dynamic>> getAppInfo() async {
    final r = await _post('/get_app_info', const <String, dynamic>{});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<UserSession> login(String username, String password) async {
    final r = await _post('/login', {
      'username': username,
      'password': password,
      'device': 'flutter_app',
    });
    return UserSession.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<ImConnectInfo> getImConnectInfo(String token) async {
    final r = await _post('/get_im_connect_info', {
      'usertoken': token,
      'device_flag': AppConfig.deviceFlag,
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
    if (list is List)
      return list
          .map(
            (e) =>
                UnifiedMessage.fromHistory(Map<String, dynamic>.from(e), myId),
          )
          .toList()
          .reversed
          .toList();
    return [];
  }

  Future<int> sendMessage({
    required String token,
    required int receiverId,
    required String content,
  }) async {
    final r = await _post('/send_message', {
      'usertoken': token,
      'receiver_id': receiverId,
      'message_type': 0,
      'content': content,
    });
    return int.tryParse('${r['data']?['message_id'] ?? 0}') ?? 0;
  }

  Future<List<UserSearchResult>> searchUsers(
    String token,
    String keyword,
  ) async {
    if (keyword.trim().isEmpty) return [];
    final r = await _post('/search_user', {
      'usertoken': token,
      'keyword': keyword.trim(),
    });
    final data = r['data'];
    final list = data is List
        ? data
        : (data is Map && data['list'] is List ? data['list'] : const []);
    return list
        .map((e) => UserSearchResult.fromJson(Map<String, dynamic>.from(e)))
        .where((u) => u.id > 0)
        .toList();
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

  Future<List<Map<String, dynamic>>> getApiList(
    String token,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await _post(path, {'usertoken': token, ...extra});
    final data = r['data'];
    final list = data is List
        ? data
        : (data is Map && data['list'] is List
              ? data['list']
              : (data is Map && data['data'] is List
                    ? data['data']
                    : (data is Map && data['records'] is List
                          ? data['records']
                          : const [])));
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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
      final device =
          data['device'] ??
          data['platform'] ??
          data['terminal'] ??
          data['client'] ??
          data['device_type'] ??
          data['device_flag'] ??
          '';
      return ImOnlineStatus(online: online, device: '$device');
    }
    return const ImOnlineStatus(online: false);
  }
}

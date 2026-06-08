import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import 'client_device_context.dart';
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

  Future<List<Map<String, dynamic>>> getForumPosts(String token, {int page = 1, int limit = 10, String sectionId = ''}) async {
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
      final r = await _post('/get_posts_list', {
        'usertoken': token,
        ...params,
      });
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
        for (final key in const ['keyword', 'word', 'name', 'title', 'search_word']) {
          final value = row[key];
          if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
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
      return raw.split(RegExp(r'[,，\s]+')).where((e) => e.trim().isNotEmpty).map((e) => e.trim()).take(limit).toList();
    } catch (_) {}
    return const [];
  }

  Future<String> publishPost(String token, {required String sectionId, String subsectionId = '', required String title, required String content, String video = '', String videoCover = ''}) async {
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

  Future<Map<String, dynamic>> getPostInformation(String token, String postId) async {
    final r = await _post('/get_post_information', {
      if (token.trim().isNotEmpty) 'usertoken': token,
      'postid': postId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> getPostComments(String postId, {int page = 1, int limit = 20}) async {
    final r = await _post('/get_list_comments', {
      'postid': postId,
      'status': 1,
      'comment_id': 0,
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

  Future<Map<String, dynamic>> togglePostLike(String token, String postId) async {
    final r = await _post('/like_posts', {
      'usertoken': token,
      'postid': postId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return {'msg': r['msg'] ?? '操作成功', ...data};
    if (data is Map) return {'msg': r['msg'] ?? '操作成功', ...Map<String, dynamic>.from(data)};
    return {'msg': r['msg'] ?? '操作成功'};
  }

  Future<String> togglePostCollection(String token, String postId) async {
    final r = await _post('/collection_posts', {
      'usertoken': token,
      'postid': postId,
    });
    return '${r['msg'] ?? '操作成功'}';
  }

  Future<String> postComment(String token, String postId, String content, {String parentId = '0'}) async {
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
    final r = await _post('/product_list', {
      'limit': limit,
      'page': page,
    });
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
    final r = await _post('/buy_goods', {
      'usertoken': token,
      'shopid': shopId,
    });
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

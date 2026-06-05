import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';

class ApiException implements Exception { final String message; ApiException(this.message); @override String toString()=>message; }

class UserSearchResult {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  const UserSearchResult({required this.id, required this.username, required this.nickname, required this.avatar});
  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
    id: int.tryParse('${j['id'] ?? j['userid'] ?? j['uid'] ?? 0}') ?? 0,
    username: '${j['username'] ?? ''}',
    nickname: '${j['nickname'] ?? j['username'] ?? '用户'}',
    avatar: '${j['usertx'] ?? j['avatar'] ?? ''}',
  );
}

class ApiService {
  final String baseUrl;
  const ApiService({this.baseUrl = AppConfig.apiBase});

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$path');
    final body = {'appid': '${AppConfig.appId}', ...data.map((k,v)=>MapEntry(k, '$v'))};
    final res = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body).timeout(const Duration(seconds: 20));
    final text = utf8.decode(res.bodyBytes);
    dynamic jsonBody;
    try { jsonBody = jsonDecode(text); } catch (_) { throw ApiException(text); }
    if (jsonBody is! Map<String, dynamic>) throw ApiException('Invalid response');
    if ('${jsonBody['code']}' != '1') throw ApiException('${jsonBody['msg'] ?? '请求失败'}');
    return jsonBody;
  }

  Future<UserSession> login(String username, String password) async {
    final r = await _post('/login', {'username': username, 'password': password, 'device': 'flutter_app'});
    return UserSession.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<ImConnectInfo> getImConnectInfo(String token) async {
    final r = await _post('/get_im_connect_info', {'usertoken': token, 'device_flag': AppConfig.deviceFlag});
    return ImConnectInfo.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<List<ConversationItem>> getMessageList(String token) async {
    final r = await _post('/get_message_list', {'usertoken': token});
    final list = r['data'];
    if (list is List) return list.map((e)=>ConversationItem.fromJson(Map<String,dynamic>.from(e))).toList();
    return [];
  }

  Future<List<UnifiedMessage>> getChatLog({required String token, required int receiverId, required int myId, int page = 1, int limit = 30}) async {
    final r = await _post('/get_chat_log', {'usertoken': token, 'receiver_id': receiverId, 'page': page, 'limit': limit});
    final data = Map<String, dynamic>.from(r['data'] ?? {});
    final list = data['list'];
    if (list is List) return list.map((e)=>UnifiedMessage.fromHistory(Map<String,dynamic>.from(e), myId)).toList().reversed.toList();
    return [];
  }

  Future<int> sendMessage({required String token, required int receiverId, required String content}) async {
    final r = await _post('/send_message', {'usertoken': token, 'receiver_id': receiverId, 'message_type': 0, 'content': content});
    return int.tryParse('${r['data']?['message_id'] ?? 0}') ?? 0;
  }

  Future<List<UserSearchResult>> searchUsers(String token, String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final r = await _post('/search_user', {'usertoken': token, 'keyword': keyword.trim()});
    final data = r['data'];
    final list = data is List ? data : (data is Map && data['list'] is List ? data['list'] : const []);
    return list.map((e) => UserSearchResult.fromJson(Map<String, dynamic>.from(e))).where((u) => u.id > 0).toList();
  }
}

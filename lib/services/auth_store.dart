import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_session.dart';

class AuthStore {
  static const _key = 'session';
  Future<void> save(UserSession s) async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode(s.toJson()));
  Future<UserSession?> load() async {
    final v = (await SharedPreferences.getInstance()).getString(_key);
    if (v == null) return null;
    return UserSession.fromJson(Map<String,dynamic>.from(jsonDecode(v)));
  }
  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

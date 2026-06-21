class AppConfig {
  static const String appName = '搭个话';
  static const String apiBase = 'http://139.196.166.181/api';
  static const String appVersion = '1.1';
  static const int appId = 1;
  static const int deviceFlag = 2;

  static const List<Map<String, dynamic>> publicStunServers = [
    {'urls': 'stun:139.196.166.181:3478'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  static const bool verifyResponseSign = true;
  static const int responseTimestampMaxSkewSeconds = 300;
}

class AppConfig {
  static const String appName = '搭个话';
  static const String apiBase = 'http://139.196.166.181/api';
  static const String appVersion = '1.1';
  static const int appId = 1;
  static const int deviceFlag = 2;

  static const List<Map<String, dynamic>> rtcIceServers = [
    {'urls': 'stun:103.39.221.135:3478'},
    {'urls': 'stun:139.196.166.181:3478'},
    {
      'urls': [
        'turn:103.39.221.135:3478?transport=udp',
        'turn:103.39.221.135:3478?transport=tcp',
      ],
      'username': 'imblinlin',
      'credential': '946898zhouyu@turn',
    },
    {
      'urls': [
        'turn:139.196.166.181:3478?transport=udp',
        'turn:139.196.166.181:3478?transport=tcp',
      ],
      'username': 'imblinlin',
      'credential': '946898zhouyu@turn',
    },
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  // 后台 appkey / secretKey：只用于响应 data 签名校验，以及作为公共参数传给接口。
  // 注意：它不是 AES 解密密钥。
  static const String apiAppKey = 'RzBC0btTFEjIL21ZlNweUkPKqiv69DOd';
  static const String apiSignSecretKey = apiAppKey;

  // 输出数据全部加密：AES-128-CBC，key 与 iv 使用同一个 16 字节字符串。
  static const String apiAesKey = 'nmqZnZiQvMdj5eSX';
  static const bool verifyResponseSign = true;
  static const int responseTimestampMaxSkewSeconds = 300;
}

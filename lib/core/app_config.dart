class AppConfig {
  static const String appName = 'Blinlin';
  static const String apiBase = 'http://139.196.166.181/api';
  static const int appId = 1;
  static const int deviceFlag = 2;

  // 后台 appkey / secretKey：只用于响应 data 签名校验，以及作为公共参数传给接口。
  // 注意：它不是 AES 解密密钥。
  static const String apiAppKey = 'RzBC0btTFEjIL21ZlNweUkPKqiv69DOd';
  static const String apiSignSecretKey = apiAppKey;

  // 输出数据全部加密：AES-128-CBC，key 与 iv 使用同一个 16 字节字符串。
  static const String apiAesKey = 'nmqZnZiQvMdj5eSX';
  static const bool verifyResponseSign = true;
  static const int responseTimestampMaxSkewSeconds = 10;
}

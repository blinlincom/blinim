class AppConfig {
  static const String appName = 'Blinlin';
  static const String apiBase = 'http://139.196.166.181/api';
  static const int appId = 1;
  static const int deviceFlag = 2;

  // 默然网络验证系统：数据签名/输出解密密钥。
  // 后台开启 AES-128-CBC 输出加密时，key 与 iv 使用同一个 16 字节字符串。
  // 如果后台配置了不同密钥，只需要替换这里，不要改业务代码。
  static const String apiSecretKey = 'RzBC0btTFEjIL21ZlNweUkPKqiv69DOd';
  static const String apiAesKey = 'nmqZnZiQvMdj5eSX';
  static const bool verifyResponseSign = false;
  static const int responseTimestampMaxSkewSeconds = 10;
}

typedef UpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateInstaller {
  bool get canInstallApk => false;

  Future<String> downloadApk({
    required String url,
    required String version,
    required UpdateProgress onProgress,
  }) {
    throw UnsupportedError('当前平台不支持自动下载安装包');
  }

  Future<void> installApk(String path) {
    throw UnsupportedError('当前平台不支持自动安装');
  }
}

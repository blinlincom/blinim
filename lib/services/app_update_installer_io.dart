import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'wukong_rest_guard.dart';

typedef UpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateInstaller {
  static const MethodChannel _channel = MethodChannel('blinlin.com/app_update');

  bool get canInstallApk => Platform.isAndroid;

  Future<String> downloadApk({
    required String url,
    required String version,
    required UpdateProgress onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError('更新地址无效');
    }
    WukongRestGuard.assertClientUriAllowed(uri, blockInternalPaths: false);
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载安装包失败：HTTP ${response.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/blinlin_update_${_safeName(version)}.apk');
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received <= 0) {
        throw const HttpException('安装包为空');
      }
      onProgress(received, total);
      return file.path;
    } finally {
      client.close();
    }
  }

  Future<void> installApk(String path) async {
    await _channel.invokeMethod<bool>('installApk', {'path': path});
  }

  static String _safeName(String value) {
    final text = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return text.isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : text;
  }
}

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../wukong_rest_guard.dart';

Future<String> downloadRemoteFile({
  required String url,
  required String filename,
}) async {
  final uri = Uri.parse(url);
  WukongRestGuard.assertClientUriAllowed(uri, blockInternalPaths: false);
  final response = await http.get(uri);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('下载失败：HTTP ${response.statusCode}');
  }
  final base = await _downloadBaseDirectory();
  final dir = Directory('${base.path}/BlinDownloads');
  if (!await dir.exists()) await dir.create(recursive: true);
  final safeName = _safeFilename(filename);
  final file = File('${dir.path}/${_uniqueName(dir, safeName)}');
  await file.writeAsBytes(response.bodyBytes, flush: true);
  return file.path;
}

Future<Directory> _downloadBaseDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {}
  try {
    final external = await getExternalStorageDirectory();
    if (external != null) return external;
  } catch (_) {}
  return getApplicationDocumentsDirectory();
}

String _safeFilename(String filename) {
  final trimmed = filename.trim().isEmpty ? 'download' : filename.trim();
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _uniqueName(Directory dir, String filename) {
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot) : '';
  var candidate = filename;
  var i = 1;
  while (File('${dir.path}/$candidate').existsSync()) {
    candidate = '${stem}_$i$ext';
    i++;
  }
  return candidate;
}

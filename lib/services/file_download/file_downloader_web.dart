// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<String> downloadRemoteFile({
  required String url,
  required String filename,
}) async {
  final anchor = html.AnchorElement(href: url)
    ..download = filename.trim().isEmpty ? 'download' : filename.trim()
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return '浏览器下载';
}

import '../core/app_config.dart';

String resolveMediaUrl(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return '';
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) return text;
  if (text.startsWith('//')) {
    final scheme = Uri.tryParse(AppConfig.apiBase)?.scheme ?? 'http';
    return '$scheme:$text';
  }
  final base = Uri.tryParse(AppConfig.apiBase);
  if (base == null || !base.hasScheme || base.host.isEmpty) return text;
  if (text.startsWith('./') || text.startsWith('../')) {
    return base.resolve(text).toString();
  }
  return base.resolve(text.startsWith('/') ? text : '/$text').toString();
}

String firstMediaUrl(Iterable<Object?> values) {
  for (final value in values) {
    final url = resolveMediaUrl(value);
    if (url.isNotEmpty) return url;
  }
  return '';
}

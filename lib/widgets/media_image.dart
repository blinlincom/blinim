import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/wukong_rest_guard.dart';

class BlinMediaImage extends StatefulWidget {
  final String url;
  final bool isGif;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Widget? loading;
  final Widget? error;

  const BlinMediaImage({
    super.key,
    required this.url,
    this.isGif = false,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.loading,
    this.error,
  });

  @override
  State<BlinMediaImage> createState() => _BlinMediaImageState();
}

class _BlinMediaImageState extends State<BlinMediaImage> {
  static const int _maxCachedGifs = 80;
  static final Map<String, Future<Uint8List>> _gifFutureCache =
      <String, Future<Uint8List>>{};
  Future<Uint8List>? gifBytes;

  bool get _looksLikeGif {
    final lower = widget.url.toLowerCase();
    final uri = Uri.tryParse(lower);
    final fragment = uri?.fragment ?? '';
    final query = uri?.query ?? '';
    if (fragment.contains('gif') ||
        query.contains('is_gif=1') ||
        query.contains('animated=1') ||
        query.contains('format=gif') ||
        query.contains('media_format=gif')) {
      return true;
    }
    final clean = lower.split('?').first.split('#').first;
    return clean.endsWith('.gif');
  }

  bool get _shouldAnimateGif => widget.isGif || _looksLikeGif;

  @override
  void initState() {
    super.initState();
    _configureGifLoader();
  }

  @override
  void didUpdateWidget(covariant BlinMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.isGif != widget.isGif) {
      _configureGifLoader();
    }
  }

  void _configureGifLoader() {
    gifBytes =
        _shouldAnimateGif &&
            !kIsWeb &&
            WukongRestGuard.isClientUrlAllowed(
              widget.url,
              blockInternalPaths: false,
            )
        ? _cachedGifBytes(widget.url)
        : null;
  }

  Future<Uint8List> _cachedGifBytes(String url) {
    final cached = _gifFutureCache[url];
    if (cached != null) return cached;
    if (_gifFutureCache.length >= _maxCachedGifs) {
      _gifFutureCache.remove(_gifFutureCache.keys.first);
    }
    final future = _loadGifBytes(url);
    _gifFutureCache[url] = future;
    return future;
  }

  Future<Uint8List> _loadGifBytes(String url) async {
    final uri = Uri.parse(url).replace(fragment: '');
    WukongRestGuard.assertClientUriAllowed(uri, blockInternalPaths: false);
    final response = await http
        .get(uri, headers: const {'Accept': 'image/gif,image/*,*/*'})
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FlutterError('GIF HTTP ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    if (!_hasGifHeader(bytes)) {
      throw FlutterError('Not a GIF image');
    }
    return bytes;
  }

  bool _hasGifHeader(Uint8List bytes) {
    return bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
  }

  @override
  Widget build(BuildContext context) {
    final future = gifBytes;
    if (future == null) return _networkImage();
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done &&
            data != null &&
            data.isNotEmpty) {
          return Image.memory(
            data,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: widget.filterQuality,
            errorBuilder: (_, _, _) => _networkImage(),
          );
        }
        if (snapshot.hasError) return _networkImage();
        return widget.loading ??
            const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
    );
  }

  Widget _networkImage() {
    if (!WukongRestGuard.isClientUrlAllowed(
      widget.url,
      blockInternalPaths: false,
    )) {
      return widget.error ?? const Icon(Icons.broken_image_outlined);
    }
    final imageUrl =
        Uri.tryParse(widget.url)?.replace(fragment: '').toString() ??
        widget.url;
    return Image.network(
      imageUrl,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: widget.filterQuality,
      webHtmlElementStrategy: _shouldAnimateGif
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return widget.loading ??
            const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) =>
          widget.error ?? const Icon(Icons.broken_image_outlined),
    );
  }
}

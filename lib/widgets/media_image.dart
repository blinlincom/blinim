import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  Future<Uint8List>? gifBytes;

  bool get _looksLikeGif {
    final clean = widget.url.split('?').first.split('#').first.toLowerCase();
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
    gifBytes = _shouldAnimateGif && !kIsWeb ? _loadGifBytes(widget.url) : null;
  }

  Future<Uint8List> _loadGifBytes(String url) async {
    final uri = Uri.parse(url);
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
    return Image.network(
      widget.url,
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

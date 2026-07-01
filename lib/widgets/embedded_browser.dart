import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'blin_style.dart';

class EmbeddedBrowserScreen extends StatefulWidget {
  final Uri url;
  final String title;
  final bool enableBridge;
  final Map<String, dynamic> bridgeConfig;

  const EmbeddedBrowserScreen({
    super.key,
    required this.url,
    this.title = '网页',
    this.enableBridge = false,
    this.bridgeConfig = const <String, dynamic>{},
  });

  @override
  State<EmbeddedBrowserScreen> createState() => _EmbeddedBrowserScreenState();
}

class _EmbeddedBrowserScreenState extends State<EmbeddedBrowserScreen> {
  WebViewController? controller;
  bool loading = true;
  String? error;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (supported) {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'BlinNative',
          onMessageReceived: _handleBridgeMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => setState(() {
              loading = true;
              error = null;
            }),
            onPageFinished: (_) {
              setState(() => loading = false);
              unawaited(_injectBridge());
            },
            onWebResourceError: (e) => setState(() {
              loading = false;
              error = e.description;
            }),
          ),
        )
        ..loadRequest(widget.url);
    }
  }

  Future<void> _injectBridge() async {
    final webController = controller;
    if (!widget.enableBridge || webController == null) return;
    final configJson = jsonEncode(widget.bridgeConfig);
    final script =
        '''
(function() {
  var config = $configJson;
  function clone(value) {
    return JSON.parse(JSON.stringify(value || {}));
  }
  function post(action, payload) {
    try {
      BlinNative.postMessage(JSON.stringify({
        action: String(action || ''),
        payload: payload || {}
      }));
    } catch (e) {}
  }
  window.BlinBridge = {
    getConfig: function() { return clone(config); },
    getUser: function() { return clone(config.user || {}); },
    getToken: function() { return String((config.user && config.user.token) || ''); },
    toast: function(message) { post('toast', { message: String(message || '') }); },
    copy: function(text) { post('copy', { text: String(text || '') }); },
    openUrl: function(url) { post('openUrl', { url: String(url || '') }); },
    close: function() { post('close', {}); },
    postMessage: function(action, payload) { post(action, payload || {}); }
  };
  window.dispatchEvent(new Event('BlinBridgeReady'));
})();
''';
    try {
      await webController.runJavaScript(script);
    } catch (_) {}
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    if (!widget.enableBridge || !mounted) return;
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(message.message);
      body = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{'action': 'toast', 'payload': message.message};
    }
    final action = '${body['action'] ?? ''}'.trim();
    final payload = body['payload'];
    final data = payload is Map<String, dynamic>
        ? payload
        : payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{'message': '$payload', 'text': '$payload'};
    switch (action) {
      case 'toast':
        final text = '${data['message'] ?? data['text'] ?? ''}'.trim();
        if (text.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(text)));
        }
        break;
      case 'copy':
        final text = '${data['text'] ?? data['message'] ?? ''}';
        Clipboard.setData(ClipboardData(text: text));
        break;
      case 'openUrl':
        final uri = Uri.tryParse('${data['url'] ?? ''}'.trim());
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('链接不可打开')));
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmbeddedBrowserScreen(
              url: uri,
              title: uri.host,
              enableBridge: widget.enableBridge,
              bridgeConfig: widget.bridgeConfig,
            ),
          ),
        );
        break;
      case 'close':
        Navigator.maybePop(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: widget.title.isEmpty ? '网页' : widget.title,
            subtitle: widget.url.toString(),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              ShellAction(
                icon: Icons.copy_rounded,
                tooltip: '复制链接',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.url.toString()));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('链接已复制')));
                },
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: supported && controller != null
                ? Stack(
                    children: [
                      WebViewWidget(controller: controller!),
                      if (error != null)
                        _BrowserFallback(url: widget.url, error: error),
                    ],
                  )
                : _BrowserFallback(url: widget.url),
          ),
        ],
      ),
    ),
  );
}

class _BrowserFallback extends StatelessWidget {
  final Uri url;
  final String? error;

  const _BrowserFallback({required this.url, this.error});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SoftCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NativeIconBox(
              icon: Icons.public_rounded,
              color: BlinStyle.primary,
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              error == null ? '当前平台暂不支持内嵌网页' : '网页加载失败',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              error == null ? url.toString() : '$error\n${url.toString()}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url.toString()));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('链接已复制')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制链接'),
            ),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'blin_style.dart';

class EmbeddedBrowserScreen extends StatefulWidget {
  final Uri url;
  final String title;

  const EmbeddedBrowserScreen({
    super.key,
    required this.url,
    this.title = '网页',
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
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => setState(() {
              loading = true;
              error = null;
            }),
            onPageFinished: (_) => setState(() => loading = false),
            onWebResourceError: (e) => setState(() {
              loading = false;
              error = e.description;
            }),
          ),
        )
        ..loadRequest(widget.url);
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

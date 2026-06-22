class WukongRestGuard {
  static const _internalPathPrefixes = <String>[
    '/message',
    '/route',
    '/user',
    '/channel',
    '/conversation',
    '/conn',
    '/event',
    '/manager',
    '/varz',
    '/migrate',
  ];

  const WukongRestGuard._();

  static void assertClientUriAllowed(
    Uri uri, {
    bool blockInternalPaths = true,
  }) {
    if (_isBlocked(uri, blockInternalPaths: blockInternalPaths)) {
      throw UnsupportedError('客户端禁止直接访问悟空IM内部接口');
    }
  }

  static bool isClientUriAllowed(Uri uri, {bool blockInternalPaths = true}) {
    return !_isBlocked(uri, blockInternalPaths: blockInternalPaths);
  }

  static bool isClientUrlAllowed(String url, {bool blockInternalPaths = true}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return isClientUriAllowed(uri, blockInternalPaths: blockInternalPaths);
  }

  static bool _isBlocked(Uri uri, {required bool blockInternalPaths}) {
    if (uri.port == 5001) return true;
    if (!blockInternalPaths) return false;
    final path = uri.path.trim().toLowerCase();
    if (path.isEmpty || !path.startsWith('/')) return false;
    return _internalPathPrefixes.any(
      (prefix) => path == prefix || path.startsWith('$prefix/'),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/safe_random.dart';

class ClientDeviceContext {
  static String? _cachedDeviceId;

  final String platform;
  final String device;
  final String terminal;
  final int deviceFlag;

  const ClientDeviceContext({
    required this.platform,
    required this.device,
    required this.terminal,
    required this.deviceFlag,
  });

  Future<String> persistentDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'blinlin_install_device_id_$platform';
    final cached = prefs.getString(key);
    if (cached != null && cached.isNotEmpty) {
      _cachedDeviceId = cached;
      return cached;
    }
    final random = SafeRandom.hex(8);
    final id =
        'blinlin_${platform}_${deviceFlag}_${DateTime.now().millisecondsSinceEpoch}_$random';
    await prefs.setString(key, id);
    _cachedDeviceId = id;
    return id;
  }

  String stableDeviceId(int userId) =>
      'blinlin_${platform}_${deviceFlag}_$userId';

  String requestDeviceId() =>
      _cachedDeviceId ?? 'blinlin_${platform}_$deviceFlag';

  Map<String, dynamic> toApiFields() => {
    'device': device,
    'platform': platform,
    'terminal': terminal,
    'device_type': terminal,
    'device_flag': deviceFlag,
  };

  static ClientDeviceContext current() {
    if (kIsWeb) {
      return const ClientDeviceContext(
        platform: 'web',
        device: 'web',
        terminal: 'web',
        deviceFlag: 1,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return const ClientDeviceContext(
          platform: 'ios',
          device: 'ios',
          terminal: 'ios',
          deviceFlag: 4,
        );
      case TargetPlatform.android:
        return const ClientDeviceContext(
          platform: 'android',
          device: 'android',
          terminal: 'mobile',
          deviceFlag: 2,
        );
      case TargetPlatform.macOS:
        return const ClientDeviceContext(
          platform: 'macos',
          device: 'desktop',
          terminal: 'desktop',
          deviceFlag: 3,
        );
      case TargetPlatform.windows:
        return const ClientDeviceContext(
          platform: 'windows',
          device: 'desktop',
          terminal: 'desktop',
          deviceFlag: 3,
        );
      case TargetPlatform.linux:
        return const ClientDeviceContext(
          platform: 'linux',
          device: 'desktop',
          terminal: 'desktop',
          deviceFlag: 3,
        );
      case TargetPlatform.fuchsia:
        return const ClientDeviceContext(
          platform: 'app',
          device: 'app',
          terminal: 'app',
          deviceFlag: 2,
        );
    }
  }
}

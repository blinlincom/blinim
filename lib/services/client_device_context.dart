import 'package:flutter/foundation.dart';

class ClientDeviceContext {
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
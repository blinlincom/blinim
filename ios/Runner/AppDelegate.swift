import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenshotMonitor") {
      let channel = FlutterMethodChannel(
        name: "blinlin.com/screenshot_monitor",
        binaryMessenger: registrar.messenger()
      )
      screenshotChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        switch call.method {
        case "start":
          NotificationCenter.default.addObserver(
            self,
            selector: #selector(AppDelegate.userDidTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
          )
          result(true)
        case "stop":
          NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
          )
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  @objc private func userDidTakeScreenshot() {
    screenshotChannel?.invokeMethod(
      "onScreenshot",
      arguments: ["time": Int(Date().timeIntervalSince1970 * 1000)]
    )
  }
}

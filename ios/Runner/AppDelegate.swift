import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotChannel: FlutterMethodChannel?
  private var diagnosticsChannel: FlutterMethodChannel?
  private var callAudioChannel: FlutterMethodChannel?

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Diagnostics") {
      let channel = FlutterMethodChannel(
        name: "blinlin.com/diagnostics",
        binaryMessenger: registrar.messenger()
      )
      diagnosticsChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        switch call.method {
        case "appendLog":
          let args = call.arguments as? [String: Any]
          let line = args?["line"] as? String ?? ""
          result(self.appendDiagnosticLog(line))
        case "getLogPath":
          result(self.diagnosticLogFile().path)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallAudioSession") {
      let channel = FlutterMethodChannel(
        name: "blinlin.com/call_audio",
        binaryMessenger: registrar.messenger()
      )
      callAudioChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        switch call.method {
        case "release":
          result(self.releaseCallAudio())
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

  private func diagnosticLogFile() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("blinlin_call.log")
  }

  private func appendDiagnosticLog(_ line: String) -> Bool {
    let trimmed = String(line.prefix(8000))
    if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return false
    }
    let file = diagnosticLogFile()
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      rotateDiagnosticLogIfNeeded(file)
      let data = (trimmed + "\n").data(using: .utf8) ?? Data()
      if FileManager.default.fileExists(atPath: file.path) {
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
      } else {
        try data.write(to: file)
      }
      return true
    } catch {
      return false
    }
  }

  private func rotateDiagnosticLogIfNeeded(_ file: URL) {
    guard
      let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
      let size = attrs[.size] as? NSNumber,
      size.int64Value > 2 * 1024 * 1024
    else {
      return
    }
    let rotated = file.deletingLastPathComponent().appendingPathComponent("blinlin_call.log.1")
    try? FileManager.default.removeItem(at: rotated)
    try? FileManager.default.moveItem(at: file, to: rotated)
  }

  private func releaseCallAudio() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
      return true
    } catch {
      return false
    }
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var diagnosticsChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupDiagnosticsChannel(flutterViewController)

    super.awakeFromNib()
  }

  private func setupDiagnosticsChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "blinlin.com/diagnostics",
      binaryMessenger: controller.engine.binaryMessenger
    )
    diagnosticsChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "appendLog":
        let args = call.arguments as? [String: Any]
        let line = args?["line"] as? String ?? ""
        result(Self.appendDiagnosticLog(line))
      case "getLogPath":
        result(Self.diagnosticLogFile().path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func diagnosticLogFile() -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("Blinlin", isDirectory: true)
      .appendingPathComponent("blinlin_call.log")
  }

  private static func appendDiagnosticLog(_ line: String) -> Bool {
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

  private static func rotateDiagnosticLogIfNeeded(_ file: URL) {
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
}

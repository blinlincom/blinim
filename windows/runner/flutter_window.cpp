#include "flutter_window.h"

#include <optional>
#include <shlobj.h>

#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
constexpr int kScreenshotHotkeyId = 0x4B31;
constexpr char kScreenshotChannelName[] = "blinlin.com/screenshot_monitor";
constexpr char kDiagnosticsChannelName[] = "blinlin.com/diagnostics";
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  SetupScreenshotChannel();
  SetupDiagnosticsChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetScreenshotHotkeyEnabled(false);
  screenshot_channel_.reset();
  diagnostics_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY:
      if (wparam == kScreenshotHotkeyId) {
        NotifyScreenshot();
      }
      break;
    case WM_KEYUP:
    case WM_SYSKEYUP:
      if (wparam == VK_SNAPSHOT) {
        NotifyScreenshot();
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupScreenshotChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  screenshot_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kScreenshotChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  screenshot_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "start") {
          SetScreenshotHotkeyEnabled(true);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "stop") {
          SetScreenshotHotkeyEnabled(false);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::SetupDiagnosticsChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  diagnostics_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kDiagnosticsChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  diagnostics_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "appendLog") {
          std::string line;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("line"));
            if (it != args->end()) {
              if (const auto* value = std::get_if<std::string>(&it->second)) {
                line = *value;
              }
            }
          }
          result->Success(flutter::EncodableValue(AppendDiagnosticLog(line)));
          return;
        }
        if (call.method_name() == "getLogPath") {
          result->Success(
              flutter::EncodableValue(Utf8FromUtf16(DiagnosticLogPath().c_str())));
          return;
        }
        result->NotImplemented();
      });
}

bool FlutterWindow::AppendDiagnosticLog(const std::string& line) const {
  if (line.empty()) {
    return false;
  }
  const auto path = DiagnosticLogPath();
  const auto parent = path.substr(0, path.find_last_of(L"\\/"));
  if (!parent.empty()) {
    ::SHCreateDirectoryExW(nullptr, parent.c_str(), nullptr);
  }
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
    ULARGE_INTEGER size;
    size.HighPart = data.nFileSizeHigh;
    size.LowPart = data.nFileSizeLow;
    if (size.QuadPart > 2ULL * 1024ULL * 1024ULL) {
      const auto rotated = parent + L"\\blinlin_call.log.1";
      ::DeleteFileW(rotated.c_str());
      ::MoveFileW(path.c_str(), rotated.c_str());
    }
  }
  const auto clipped = line.substr(0, 8000) + "\n";
  HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD written = 0;
  const BOOL ok = ::WriteFile(file, clipped.data(),
                              static_cast<DWORD>(clipped.size()), &written,
                              nullptr);
  ::CloseHandle(file);
  return ok == TRUE;
}

std::wstring FlutterWindow::DiagnosticLogPath() const {
  PWSTR known_path = nullptr;
  std::wstring base;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                       &known_path)) &&
      known_path != nullptr) {
    base = known_path;
    ::CoTaskMemFree(known_path);
  }
  if (base.empty()) {
    wchar_t buffer[MAX_PATH];
    DWORD length = ::GetTempPathW(MAX_PATH, buffer);
    base = length > 0 ? std::wstring(buffer, length) : L".";
  }
  return base + L"\\Blinlin\\blinlin_call.log";
}

void FlutterWindow::SetScreenshotHotkeyEnabled(bool enabled) {
  HWND handle = GetHandle();
  if (!handle) {
    return;
  }
  if (enabled && !screenshot_hotkey_registered_) {
    screenshot_hotkey_registered_ =
        ::RegisterHotKey(handle, kScreenshotHotkeyId, 0, VK_SNAPSHOT) == TRUE;
    return;
  }
  if (!enabled && screenshot_hotkey_registered_) {
    ::UnregisterHotKey(handle, kScreenshotHotkeyId);
    screenshot_hotkey_registered_ = false;
  }
}

void FlutterWindow::NotifyScreenshot() {
  if (!screenshot_channel_) {
    return;
  }
  auto args = flutter::EncodableMap{
      {flutter::EncodableValue("time"), flutter::EncodableValue(
                                          static_cast<int64_t>(::GetTickCount64()))},
  };
  screenshot_channel_->InvokeMethod(
      "onScreenshot",
      std::make_unique<flutter::EncodableValue>(std::move(args)));
}

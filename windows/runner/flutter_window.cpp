#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kScreenshotHotkeyId = 0x4B31;
constexpr char kScreenshotChannelName[] = "blinlin.com/screenshot_monitor";
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

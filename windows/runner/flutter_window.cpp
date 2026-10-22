#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <imm.h>

#include <optional>

#include "app_window.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

// Windows 10 2004 以後才有；舊的 SDK 沒有定義
#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

// 不允許截圖時：視窗不出現在截圖、錄影與螢幕分享（WDA_EXCLUDEFROMCAPTURE）；
// 2004 以前的 Windows 10 不支援，改用 WDA_MONITOR（拍到的是一塊黑色）
bool ApplyCaptureBlock(HWND hwnd, bool block) {
  if (!block) {
    return ::SetWindowDisplayAffinity(hwnd, WDA_NONE) != FALSE;
  }
  if (::SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)) {
    return true;
  }
  return ::SetWindowDisplayAffinity(hwnd, WDA_MONITOR) != FALSE;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool start_hidden)
    : project_(project),
      start_hidden_(start_hidden),
      quit_message_(::RegisterWindowMessageW(kQuitMessageName)) {}

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
  SetupChannels();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 登入時自動開啟（--hidden）時不顯示，等使用者從系統匣叫出來
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupChannels() {
  auto messenger = flutter_controller_->engine()->messenger();
  const auto& codec = flutter::StandardMethodCodec::GetInstance();

  // 預設允許截圖（同 macOS：擋住後在 Parsec、AnyDesk 等遠端桌面上也會看不到視窗），設定頁關掉才擋
  privacy_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "securibit/privacy", &codec);
  privacy_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "configure") {
      result->NotImplemented();
      return;
    }
    bool block = true;
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("blockCapture"));
      if (it != args->end()) {
        if (const auto* value = std::get_if<bool>(&it->second)) {
          block = *value;
        }
      }
    }
    if (ApplyCaptureBlock(GetHandle(), block)) {
      result->Success();
    } else {
      result->Error("display-affinity", "SetWindowDisplayAffinity failed");
    }
  });

  // 密碼畫面暫時關掉輸入法：注音等中文輸入法開著時，Num Lock 打開的數字小鍵盤會先被輸入法攔走，
  // Flutter 收不到按鍵（Num Lock 關掉時送的是方向鍵，輸入法不處理）。離開密碼畫面再還原
  ime_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "securibit/ime", &codec);
  ime_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setEnabled") {
      result->NotImplemented();
      return;
    }
    bool enabled = true;
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto* value = std::get_if<bool>(&it->second)) {
          enabled = *value;
        }
      }
    }
    // IACE_CHILDREN：連 Flutter 畫面所在的子視窗一起
    ::ImmAssociateContextEx(GetHandle(), nullptr, enabled ? (IACE_DEFAULT | IACE_CHILDREN) : IACE_CHILDREN);
    result->Success();
  });

  tray_ = std::make_unique<Tray>(GetHandle(), messenger, start_hidden_);
}

void FlutterWindow::OnDestroy() {
  privacy_channel_ = nullptr;
  ime_channel_ = nullptr;
  tray_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (tray_) {
    // 系統匣常駐時關視窗（X、Alt+F4）只藏起來；要在 Flutter 之前攔，不然引擎會先問 Dart 要不要結束
    if (message == WM_CLOSE && tray_->HandleClose()) {
      return 0;
    }
    // 安裝檔請 App 結束（安裝、解除安裝前）
    if (message == quit_message_ && quit_message_ != 0) {
      tray_->Quit();
      return 0;
    }
    // 視窗被叫出來（系統匣、另一個執行個體、Dart 的 showWindow）：通知 Dart，並重畫一次（藏著的時候可能沒畫）
    if (message == WM_SHOWWINDOW && wparam && lparam == 0) {
      tray_->OnWindowShown();
      if (flutter_controller_) {
        flutter_controller_->ForceRedraw();
      }
    }
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_GETMINMAXINFO: {
      // 最小尺寸：內容 400 × 560（邏輯像素）加上這個 DPI 的標題列與邊框
      const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
      const double scale = dpi / 96.0;
      RECT frame = {0, 0, static_cast<LONG>(kMinWidth * scale), static_cast<LONG>(kMinHeight * scale)};
      ::AdjustWindowRectExForDpi(&frame, static_cast<DWORD>(::GetWindowLongPtr(hwnd, GWL_STYLE)), FALSE,
                                 static_cast<DWORD>(::GetWindowLongPtr(hwnd, GWL_EXSTYLE)), dpi);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = frame.right - frame.left;
      info->ptMinTrackSize.y = frame.bottom - frame.top;
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

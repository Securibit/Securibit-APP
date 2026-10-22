#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "tray.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // start_hidden：登入時自動開啟（--hidden），第一個畫面出來也不顯示，藏在系統匣
  FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 截圖保護（securibit/privacy）：設定頁關掉「允許截圖」時，視窗不出現在截圖、錄影與螢幕分享
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> privacy_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> ime_channel_;
  // 系統匣常駐、叫回主視窗與登入時自動開啟（securibit/menubar，見 tray.h）
  std::unique_ptr<Tray> tray_;

  bool start_hidden_;
  // 安裝檔請 App 結束的訊息（見 app_window.h 的 kQuitMessageName）
  UINT quit_message_;

  void SetupChannels();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

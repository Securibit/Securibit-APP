#ifndef RUNNER_TRAY_H_
#define RUNNER_TRAY_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

/*
 * Windows 系統匣常駐（channel：securibit/menubar，Dart 端見 lib/features/menubar/；
 * macOS 是 macos/Runner/MenuBarController.swift，Linux 是 linux/runner/tray.cc）：
 * - 圖示用 Shell_NotifyIcon，左鍵、右鍵都打開 TrackPopupMenu 的選單，依群組列出驗證碼，點一下複製
 * - Dart 是唯一的資料來源：原生端只拿到顯示用的文字（Dart 算好的 label），金鑰一直在 Dart；複製也是請 Dart 算當下的碼
 * - 選單由這裡在點圖示時打開，打開前先向 Dart 要含驗證碼的內容（menuWillOpen），所以不用像 Linux 一樣在視窗藏著時每秒更新；
 *   選單開著時（TrackPopupMenu 的 modal loop）不更新文字，點了以後由 Dart 算當下的碼，複製到的一定正確
 * - 打開系統匣、而且圖示真的加上去時，關掉主視窗（X、Alt+F4）只是藏起來，「結束 Securibit」才真的結束；
 *   圖示加不上去（例如檔案總管還沒啟動）時照常結束，免得視窗藏起來卻叫不回來
 * - 主視窗藏起來或重新顯示時通知 Dart（windowWillHide／windowDidShow），App 鎖定把它當成離開與回來
 * - 登入時自動開啟見 launch_at_login.h
 */
class Tray {
 public:
  // start_hidden：登入時自動開啟（--hidden），主視窗一開始就藏著
  Tray(HWND window, flutter::BinaryMessenger* messenger, bool start_hidden);
  ~Tray();

  Tray(const Tray&) = delete;
  Tray& operator=(const Tray&) = delete;

  // 使用者關視窗（X、Alt+F4）：常駐時藏起來並回傳 true；否則回傳 false，照常關閉並結束 App
  bool HandleClose();

  // 主視窗變成看得見了（不論是這裡、另一個執行個體還是系統叫回來的）
  void OnWindowShown();

  // 叫回主視窗並切到前景
  void ShowMainWindow();

  // 真的結束 App（系統匣的「結束 Securibit」、安裝檔要求結束）
  void Quit();

 private:
  enum class MenuState { kClosed, kRequested, kOpen };

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) noexcept;
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetEnabled(bool enabled);

  // 系統匣圖示
  bool AddIcon();
  void RemoveIcon();
  void OnIconRetry();
  void ShowCopied();
  void HideCopied();

  // 選單
  void RequestMenu(POINT anchor);
  void ShowMenu(unsigned int serial);
  HMENU BuildMenu();
  void AddSectionContent(const flutter::EncodableMap& section, HMENU target);
  void RunCommand(UINT command);

  // 主視窗
  void HideMainWindow();
  void FinishHide(unsigned int serial);

  HWND window_;
  HWND tray_window_ = nullptr;
  HICON icon_ = nullptr;
  UINT taskbar_created_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool enabled_ = false;
  bool icon_added_ = false;
  int icon_retries_ = 0;
  bool window_hidden_ = false;
  bool quitting_ = false;
  // 每次藏視窗加一，舊的回覆或逾時不會藏掉之後又叫回來的視窗
  unsigned int hide_serial_ = 0;
  unsigned int hidden_serial_ = 0;

  MenuState menu_state_ = MenuState::kClosed;
  // 每次要打開選單加一，Dart 的回覆與逾時哪個先到就用哪個，另一個不再打開第二次
  unsigned int menu_serial_ = 0;
  POINT menu_anchor_ = {0, 0};
  // 目前的內容（只有顯示用的文字）
  flutter::EncodableMap model_;
  // 選單裡每一筆驗證碼的 id（命令編號 kCommandFirstCode + 索引）
  std::vector<std::string> menu_ids_;
};

#endif  // RUNNER_TRAY_H_

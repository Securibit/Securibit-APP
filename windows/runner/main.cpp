#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <windows.h>

#include <algorithm>
#include <regex>
#include <cwchar>
#include <string>

#include "app_window.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// 預設大小放得下三欄（側欄｜清單｜詳細資料），同 macOS 的 MainFlutterWindow.swift；螢幕放不下時縮到放得下
constexpr int kDefaultWidth = 1180;
constexpr int kDefaultHeight = 760;

// app_links 外掛收連結的訊息編號（app_links_plugin.h 的 APPLINK_MSG_ID）
constexpr ULONG_PTR kAppLinkMessageId = WM_USER + 2;

// 命令列只有一個參數、而且像網址（securibit://、otpauth://、otpauth-migration://）時回傳它，
// 規則和 app_links 外掛的 GetLink 相同：安裝檔註冊的指令是 "securibit.exe" "%1"
std::string LinkFromCommandLine() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return "";
  }
  std::string link = argc == 2 ? Utf8FromUtf16(argv[1]) : "";
  ::LocalFree(argv);
  static const std::regex scheme(R"(^([a-z][a-z0-9+.-]+):)", std::regex_constants::icase);
  return std::regex_search(link, scheme) ? link : "";
}

// 登入時自動開啟（登錄檔的 Run 值帶 --hidden，見 launch_at_login.h）
bool HasHiddenArgument() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  bool hidden = false;
  for (int i = 1; i < argc; i++) {
    hidden = hidden || ::wcscmp(argv[i], kHiddenArgument) == 0;
  }
  ::LocalFree(argv);
  return hidden;
}

// 已經有一個 Securibit 開著（可能藏在系統匣）：把連結交給它（WM_COPYDATA，app_links 外掛在那邊收），再把它的視窗叫到前面。
// 視窗被叫出來時，那邊的 Tray 會收到 WM_SHOWWINDOW 並通知 Dart（windowDidShow）。
// 登入時自動開啟（--hidden、沒有連結）遇到已經開著的就什麼都不做，不跳出視窗。
// app_links 自己的 SendAppLink 會多讀字串後面的記憶體，所以這裡自己送（長度算到結尾的 \0）
void HandOverToRunningInstance(HWND hwnd, bool hidden) {
  const std::string link = LinkFromCommandLine();
  if (link.empty() && hidden) {
    return;
  }
  if (!link.empty()) {
    COPYDATASTRUCT data = {};
    data.dwData = kAppLinkMessageId;
    data.cbData = static_cast<DWORD>(link.size() + 1);
    data.lpData = const_cast<char*>(link.c_str());
    ::SendMessage(hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
  }
  BringWindowToFront(hwnd);
}

// 把視窗放在主螢幕的工作區（不含工作列）正中間；螢幕太小時縮小，但不小於最小尺寸
void CenteredFrame(Win32Window::Point* origin, Win32Window::Size* size) {
  const POINT zero = {0, 0};
  HMONITOR monitor = ::MonitorFromPoint(zero, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!::GetMonitorInfo(monitor, &info)) {
    return;
  }
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int left = static_cast<int>(info.rcWork.left / scale);
  const int top = static_cast<int>(info.rcWork.top / scale);
  const int width = static_cast<int>((info.rcWork.right - info.rcWork.left) / scale);
  const int height = static_cast<int>((info.rcWork.bottom - info.rcWork.top) / scale);
  size->width = std::max(kMinWidth, std::min(kDefaultWidth, width - 40));
  size->height = std::max(kMinHeight, std::min(kDefaultHeight, height - 40));
  origin->x = left + std::max(0, (width - static_cast<int>(size->width)) / 2);
  origin->y = top + std::max(0, (height - static_cast<int>(size->height)) / 2);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 同一個使用者只開一個 Securibit：已經開著時把連結交給它就結束（點 otpauth:// 連結、再點一次捷徑）
  const bool hidden = HasHiddenArgument();
  SingleInstance single_instance;
  if (!single_instance.IsFirst()) {
    HWND running = single_instance.FindRunningWindow();
    if (running != nullptr) {
      HandOverToRunningInstance(running, hidden);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(kDefaultWidth, kDefaultHeight);
  CenteredFrame(&origin, &size);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

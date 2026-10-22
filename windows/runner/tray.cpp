#include "tray.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windowsx.h>

#include <functional>
#include <variant>

#include "app_window.h"
#include "launch_at_login.h"
#include "resource.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannelName[] = "securibit/menubar";
constexpr wchar_t kTrayWindowClass[] = L"SECURIBIT_TRAY_WINDOW";
constexpr UINT kIconId = 1;
// 系統匣圖示的事件
constexpr UINT kIconMessage = WM_APP + 1;
// Dart 回覆後再打開選單（不在 channel 的回呼裡跑選單的 modal loop）
constexpr UINT kShowMenuMessage = WM_APP + 2;

constexpr UINT_PTR kHideTimer = 1;
constexpr UINT_PTR kMenuTimer = 2;
constexpr UINT_PTR kCopiedTimer = 3;
constexpr UINT_PTR kIconRetryTimer = 4;
constexpr UINT_PTR kStartupTimer = 5;
// 藏視窗前等 Dart 畫好鎖定畫面，最多等這麼久（同 macOS、Linux）
constexpr UINT kHideTimeoutMs = 500;
// Dart 沒回覆時，等這麼久就用手上的內容打開選單
constexpr UINT kMenuTimeoutMs = 1000;
// 「已複製」的通知顯示這麼久就收掉
constexpr UINT kCopiedMs = 2000;
// 圖示加不上去（檔案總管還沒準備好）時每秒重試，最多這麼多次
constexpr UINT kIconRetryMs = 1000;
constexpr int kIconRetries = 10;
// 登入時自動開啟（--hidden）後這麼久還沒有系統匣圖示，就把視窗叫出來，免得 App 開著卻看不到
constexpr UINT kStartupTimeoutMs = 15000;

// 選單的命令編號（TrackPopupMenu 回傳；0 代表沒選）
constexpr UINT kCommandOpen = 1;
constexpr UINT kCommandSettings = 2;
constexpr UINT kCommandQuit = 3;
constexpr UINT kCommandFirstCode = 100;

// MARK: - EncodableValue 小工具

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string LookupString(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Lookup(map, key);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? "" : *text;
}

bool LookupBool(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Lookup(map, key);
  const auto* flag = value == nullptr ? nullptr : std::get_if<bool>(value);
  return flag != nullptr && *flag;
}

const EncodableList* LookupList(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Lookup(map, key);
  return value == nullptr ? nullptr : std::get_if<EncodableList>(value);
}

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return L"";
  }
  const int length = ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}

// 選單文字：& 會被當成快速鍵的底線，要寫成 &&；Tab 會把後面的字推到快速鍵那一欄，換成空白
std::wstring MenuText(const std::string& text) {
  std::wstring result;
  for (wchar_t c : Utf16FromUtf8(text)) {
    if (c == L'&') {
      result += L"&&";
    } else if (c == L'\t') {
      result += L' ';
    } else {
      result += c;
    }
  }
  return result;
}

void AppendItem(HMENU menu, const std::string& text, UINT command, bool enabled) {
  ::AppendMenuW(menu, MF_STRING | (enabled ? MF_ENABLED : MF_GRAYED), command, MenuText(text).c_str());
}

void AppendSeparator(HMENU menu) {
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
}

// 回覆內容不重要、只要知道 Dart 回了（成功、失敗或沒實作都算）
std::unique_ptr<flutter::MethodResult<EncodableValue>> OnReply(std::function<void(const EncodableValue*)> done) {
  return std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
      [done](const EncodableValue* result) { done(result); },
      [done](const std::string&, const std::string&, const EncodableValue*) { done(nullptr); },
      [done]() { done(nullptr); });
}

}  // namespace

Tray::Tray(HWND window, flutter::BinaryMessenger* messenger, bool start_hidden)
    : window_(window), window_hidden_(start_hidden) {
  const HINSTANCE instance = ::GetModuleHandle(nullptr);
  WNDCLASSEXW window_class = {sizeof(WNDCLASSEXW)};
  window_class.lpfnWndProc = Tray::WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kTrayWindowClass;
  ::RegisterClassExW(&window_class);
  // 看不見的視窗：收圖示的事件、當選單的擁有者（要能切到前景，選單才會在點別的地方時收起來，所以不用 message-only 視窗）
  tray_window_ = ::CreateWindowExW(WS_EX_TOOLWINDOW, kTrayWindowClass, L"Securibit", WS_POPUP, 0, 0, 0, 0,
                                   nullptr, nullptr, instance, this);
  // 檔案總管重新啟動（或工作列重建）時要把圖示加回去
  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleMethodCall(call, std::move(result)); });

  if (start_hidden && tray_window_ != nullptr) {
    ::SetTimer(tray_window_, kStartupTimer, kStartupTimeoutMs, nullptr);
  }
}

Tray::~Tray() {
  channel_ = nullptr;
  RemoveIcon();
  if (tray_window_ != nullptr) {
    ::DestroyWindow(tray_window_);
  }
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
  }
}

// MARK: - 看不見的視窗

// static
LRESULT CALLBACK Tray::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto create = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (auto* tray = reinterpret_cast<Tray*>(::GetWindowLongPtr(hwnd, GWLP_USERDATA))) {
    if (hwnd == tray->tray_window_) {
      return tray->HandleMessage(message, wparam, lparam);
    }
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT Tray::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kIconMessage) {
    // NOTIFYICON_VERSION_4：lparam 的低位是事件，wparam 是圖示的位置（螢幕座標）
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
      case WM_CONTEXTMENU:
        RequestMenu({GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)});
        break;
    }
    return 0;
  }
  if (message == kShowMenuMessage) {
    ShowMenu(static_cast<unsigned int>(wparam));
    return 0;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    icon_added_ = false;
    if (enabled_ && !AddIcon()) {
      icon_retries_ = 0;
      ::SetTimer(tray_window_, kIconRetryTimer, kIconRetryMs, nullptr);
    }
    return 0;
  }
  if (message == WM_TIMER) {
    switch (wparam) {
      case kHideTimer:
        FinishHide(hide_serial_);
        break;
      case kMenuTimer:
        ::KillTimer(tray_window_, kMenuTimer);
        ShowMenu(menu_serial_);
        break;
      case kCopiedTimer:
        HideCopied();
        break;
      case kIconRetryTimer:
        OnIconRetry();
        break;
      case kStartupTimer:
        ::KillTimer(tray_window_, kStartupTimer);
        if (window_hidden_ && !icon_added_) {
          ShowMainWindow();
        }
        break;
    }
    return 0;
  }
  return ::DefWindowProc(tray_window_, message, wparam, lparam);
}

// MARK: - channel

void Tray::HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                            std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (method == "setEnabled") {
    SetEnabled(args != nullptr && LookupBool(*args, "enabled"));
    result->Success();
  } else if (method == "update") {
    if (args != nullptr) {
      model_ = *args;
    }
    result->Success();
  } else if (method == "showWindow") {
    ShowMainWindow();
    result->Success();
  } else if (method == "launchAtLoginStatus") {
    result->Success(EncodableValue(LaunchAtLoginStatus()));
  } else if (method == "setLaunchAtLogin") {
    std::string error;
    if (SetLaunchAtLogin(args != nullptr && LookupBool(*args, "enabled"), &error)) {
      result->Success(EncodableValue(LaunchAtLoginStatus()));
    } else {
      result->Error("launch-at-login", error);
    }
  } else if (method == "openLoginItemsSettings") {
    OpenStartupAppsSettings();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void Tray::SetEnabled(bool enabled) {
  if (enabled == enabled_) {
    return;
  }
  enabled_ = enabled;
  if (enabled) {
    if (!AddIcon()) {
      icon_retries_ = 0;
      ::SetTimer(tray_window_, kIconRetryTimer, kIconRetryMs, nullptr);
    }
  } else {
    ::KillTimer(tray_window_, kIconRetryTimer);
    RemoveIcon();
    // 沒有系統匣就不能藏著，叫回主視窗
    if (window_hidden_) {
      ShowMainWindow();
    }
  }
}

// MARK: - 系統匣圖示

bool Tray::AddIcon() {
  if (icon_added_ || tray_window_ == nullptr) {
    return icon_added_;
  }
  if (icon_ == nullptr) {
    // App 圖示的小尺寸（app_icon.ico 裡有 16、24、32…，依系統的 DPI 挑）
    const UINT dpi = ::GetDpiForSystem();
    icon_ = static_cast<HICON>(::LoadImageW(::GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                                            ::GetSystemMetricsForDpi(SM_CXSMICON, dpi),
                                            ::GetSystemMetricsForDpi(SM_CYSMICON, dpi), LR_DEFAULTCOLOR));
  }
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = tray_window_;
  data.uID = kIconId;
  // NOTIFYICON_VERSION_4 預設不顯示一般的提示文字，要加 NIF_SHOWTIP
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kIconMessage;
  data.hIcon = icon_;
  wcscpy_s(data.szTip, L"Securibit");
  if (!::Shell_NotifyIconW(NIM_ADD, &data)) {
    // 檔案總管重新啟動前就加過的話可能還留著，改用更新的
    if (!::Shell_NotifyIconW(NIM_MODIFY, &data)) {
      return false;
    }
  }
  data.uVersion = NOTIFYICON_VERSION_4;
  ::Shell_NotifyIconW(NIM_SETVERSION, &data);
  icon_added_ = true;
  ::KillTimer(tray_window_, kIconRetryTimer);
  return true;
}

void Tray::RemoveIcon() {
  ::KillTimer(tray_window_, kCopiedTimer);
  if (!icon_added_) {
    return;
  }
  icon_added_ = false;
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = tray_window_;
  data.uID = kIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
}

void Tray::OnIconRetry() {
  if (!enabled_ || AddIcon()) {
    ::KillTimer(tray_window_, kIconRetryTimer);
    return;
  }
  if (++icon_retries_ < kIconRetries) {
    return;
  }
  ::KillTimer(tray_window_, kIconRetryTimer);
  // 一直加不上去：不能藏著，叫回主視窗（之後檔案總管送 TaskbarCreated 時還會再加）
  if (window_hidden_) {
    ShowMainWindow();
  }
}

// 複製後用系統匣的通知短暫顯示「已複製」：不出聲、勿擾時不顯示、不能馬上顯示就不顯示，兩秒後收掉
void Tray::ShowCopied() {
  if (!icon_added_) {
    return;
  }
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = tray_window_;
  data.uID = kIconId;
  data.uFlags = NIF_INFO | NIF_REALTIME;
  data.dwInfoFlags = NIIF_NONE | NIIF_NOSOUND | NIIF_RESPECT_QUIET_TIME;
  wcscpy_s(data.szInfoTitle, L"已複製");
  wcscpy_s(data.szInfo, L"驗證碼已複製到剪貼簿");
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
  ::SetTimer(tray_window_, kCopiedTimer, kCopiedMs, nullptr);
}

void Tray::HideCopied() {
  ::KillTimer(tray_window_, kCopiedTimer);
  if (!icon_added_) {
    return;
  }
  // 通知的文字設成空的就會收掉
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = tray_window_;
  data.uID = kIconId;
  data.uFlags = NIF_INFO;
  ::Shell_NotifyIconW(NIM_MODIFY, &data);
}

// MARK: - 選單

// 點了圖示：先向 Dart 要含驗證碼的內容，回覆（或逾時）後再打開
void Tray::RequestMenu(POINT anchor) {
  if (!enabled_ || menu_state_ != MenuState::kClosed) {
    return;
  }
  menu_state_ = MenuState::kRequested;
  menu_anchor_ = anchor;
  const unsigned int serial = ++menu_serial_;
  ::SetTimer(tray_window_, kMenuTimer, kMenuTimeoutMs, nullptr);
  channel_->InvokeMethod("menuWillOpen", nullptr, OnReply([this, serial](const EncodableValue* result) {
                           const auto* map = result == nullptr ? nullptr : std::get_if<EncodableMap>(result);
                           if (map != nullptr && serial == menu_serial_ && menu_state_ == MenuState::kRequested) {
                             model_ = *map;
                           }
                           ::PostMessage(tray_window_, kShowMenuMessage, serial, 0);
                         }));
}

void Tray::ShowMenu(unsigned int serial) {
  if (menu_state_ != MenuState::kRequested || serial != menu_serial_) {
    return;
  }
  ::KillTimer(tray_window_, kMenuTimer);
  menu_state_ = MenuState::kOpen;
  HMENU menu = BuildMenu();
  // 選單的擁有者要在前景，點選單以外的地方時選單才會收起來（Shell_NotifyIcon 的說明）
  ::SetForegroundWindow(tray_window_);
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN;
  flags |= ::GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0 ? TPM_RIGHTALIGN : TPM_LEFTALIGN;
  const UINT command =
      static_cast<UINT>(::TrackPopupMenuEx(menu, flags, menu_anchor_.x, menu_anchor_.y, tray_window_, nullptr));
  ::PostMessage(tray_window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  menu_state_ = MenuState::kClosed;
  channel_->InvokeMethod("menuDidClose", nullptr);
  RunCommand(command);
}

HMENU Tray::BuildMenu() {
  menu_ids_.clear();
  HMENU menu = ::CreatePopupMenu();
  bool has_content = false;

  const std::string message = LookupString(model_, "message");
  if (!message.empty()) {
    // 已鎖定時點一下打開 App 解鎖
    const bool locked = LookupString(model_, "status") == "locked";
    AppendItem(menu, message, locked ? kCommandOpen : 0, locked);
    has_content = true;
  }

  if (const EncodableList* sections = LookupList(model_, "sections")) {
    const bool submenus = LookupBool(model_, "submenus");
    bool first = true;
    for (const EncodableValue& value : *sections) {
      const auto* section = std::get_if<EncodableMap>(&value);
      if (section == nullptr) {
        continue;
      }
      const std::string title = LookupString(*section, "title");
      if (submenus) {
        // 驗證碼很多時每個群組收成一個子選單
        HMENU submenu = ::CreatePopupMenu();
        AddSectionContent(*section, submenu);
        ::AppendMenuW(menu, MF_STRING | MF_POPUP, reinterpret_cast<UINT_PTR>(submenu), MenuText(title).c_str());
      } else {
        // 群組名稱是一行不能點的標題，群組之間用分隔線隔開
        if (!first) {
          AppendSeparator(menu);
        }
        AppendItem(menu, title, 0, false);
        AddSectionContent(*section, menu);
      }
      first = false;
      has_content = true;
    }
  }

  if (has_content) {
    AppendSeparator(menu);
  }
  AppendItem(menu, "打開 Securibit", kCommandOpen, true);
  if (LookupBool(model_, "showSettings")) {
    AppendItem(menu, "設定…", kCommandSettings, true);
  }
  AppendSeparator(menu);
  AppendItem(menu, "結束 Securibit", kCommandQuit, true);
  return menu;
}

// 每一筆是 Dart 算好的一行文字（「名稱　驗證碼　剩餘秒數」）；不能複製的（還沒算好、金鑰錯誤）是灰的
void Tray::AddSectionContent(const EncodableMap& section, HMENU target) {
  const EncodableList* items = LookupList(section, "items");
  if (items == nullptr || items->empty()) {
    AppendItem(target, LookupString(section, "note"), 0, false);
    return;
  }
  for (const EncodableValue& value : *items) {
    const auto* item = std::get_if<EncodableMap>(&value);
    if (item == nullptr) {
      continue;
    }
    const std::string id = LookupString(*item, "id");
    if (id.empty()) {
      continue;
    }
    const UINT command = kCommandFirstCode + static_cast<UINT>(menu_ids_.size());
    menu_ids_.push_back(id);
    AppendItem(target, LookupString(*item, "label"), command, LookupBool(*item, "copyable"));
  }
}

void Tray::RunCommand(UINT command) {
  if (command >= kCommandFirstCode && command - kCommandFirstCode < menu_ids_.size()) {
    // 由 Dart 算當下的碼並複製
    EncodableMap args = {{EncodableValue("id"), EncodableValue(menu_ids_[command - kCommandFirstCode])}};
    channel_->InvokeMethod("copy", std::make_unique<EncodableValue>(args), OnReply([this](const EncodableValue* result) {
                             const auto* copied = result == nullptr ? nullptr : std::get_if<bool>(result);
                             if (copied != nullptr && *copied) {
                               ShowCopied();
                             }
                           }));
    return;
  }
  switch (command) {
    case kCommandOpen:
      ShowMainWindow();
      break;
    case kCommandSettings:
      ShowMainWindow();
      channel_->InvokeMethod("openSettings", nullptr);
      break;
    case kCommandQuit:
      Quit();
      break;
  }
}

// MARK: - 主視窗

bool Tray::HandleClose() {
  if (quitting_ || !enabled_ || !icon_added_) {
    return false;
  }
  HideMainWindow();
  return true;
}

// 先讓 Dart 鎖定並畫好畫面再藏視窗，最多等 0.5 秒（同 macOS、Linux）
void Tray::HideMainWindow() {
  if (window_hidden_) {
    return;
  }
  window_hidden_ = true;
  const unsigned int serial = ++hide_serial_;
  ::SetTimer(tray_window_, kHideTimer, kHideTimeoutMs, nullptr);
  channel_->InvokeMethod("windowWillHide", nullptr,
                         OnReply([this, serial](const EncodableValue*) { FinishHide(serial); }));
}

// Dart 的回覆與逾時哪個先到就先藏，另一個不再做事
void Tray::FinishHide(unsigned int serial) {
  if (serial != hide_serial_ || serial == hidden_serial_) {
    return;
  }
  hidden_serial_ = serial;
  ::KillTimer(tray_window_, kHideTimer);
  // 這段時間內又被叫回來就不藏了
  if (window_hidden_) {
    ::ShowWindow(window_, SW_HIDE);
  }
}

void Tray::OnWindowShown() {
  if (!window_hidden_) {
    return;
  }
  window_hidden_ = false;
  ::KillTimer(tray_window_, kStartupTimer);
  channel_->InvokeMethod("windowDidShow", nullptr);
}

void Tray::ShowMainWindow() {
  BringWindowToFront(window_);
  OnWindowShown();
}

// 先拿掉圖示，再照一般的關閉流程結束（HandleClose 不再攔）
void Tray::Quit() {
  quitting_ = true;
  RemoveIcon();
  ::PostMessage(window_, WM_CLOSE, 0, 0);
}

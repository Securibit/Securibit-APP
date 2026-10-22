#include "launch_at_login.h"

#include <windows.h>
#include <shellapi.h>

#include <optional>
#include <vector>

#include "app_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kApprovedKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
constexpr wchar_t kValueName[] = L"Securibit";

// 目前執行中的 securibit.exe
std::wstring CurrentExecutable() {
  std::vector<wchar_t> buffer(MAX_PATH);
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return L"";
    }
    if (length < buffer.size()) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
}

// Run 值的內容："<程式>" --hidden
std::wstring RunCommandFor(const std::wstring& executable) {
  return L"\"" + executable + L"\" " + kHiddenArgument;
}

// 從 Run 值取回程式路徑：有引號時是引號裡的部分，沒有時是第一個空白之前
std::wstring ExecutableFromCommand(const std::wstring& command) {
  if (!command.empty() && command[0] == L'"') {
    const size_t end = command.find(L'"', 1);
    return command.substr(1, end == std::wstring::npos ? std::wstring::npos : end - 1);
  }
  return command.substr(0, command.find(L' '));
}

bool SamePath(const std::wstring& a, const std::wstring& b) {
  return ::CompareStringOrdinal(a.c_str(), static_cast<int>(a.size()), b.c_str(),
                                static_cast<int>(b.size()), TRUE) == CSTR_EQUAL;
}

std::optional<std::wstring> ReadRunCommand() {
  const DWORD flags = RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND;
  DWORD size = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kValueName, flags, nullptr, nullptr, &size) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1);
  size = static_cast<DWORD>(buffer.size() * sizeof(wchar_t));
  if (::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kValueName, flags, nullptr, buffer.data(), &size) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  return std::wstring(buffer.data());
}

LSTATUS WriteRunCommand(const std::wstring& command) {
  return ::RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kValueName, REG_SZ, command.c_str(),
                           static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
}

// 「設定 › 應用程式 › 啟動」與工作管理員共用的紀錄：第一個位元組是 2（或 6）代表允許，3 代表關掉；沒有這筆就是允許
bool DisabledInSettings() {
  BYTE data[64] = {};
  DWORD size = sizeof(data);
  if (::RegGetValueW(HKEY_CURRENT_USER, kApprovedKey, kValueName, RRF_RT_REG_BINARY, nullptr, data, &size) !=
          ERROR_SUCCESS ||
      size == 0) {
    return false;
  }
  return (data[0] & 1) != 0;
}

std::string SystemMessage(LSTATUS status) {
  wchar_t* text = nullptr;
  const DWORD length = ::FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
      static_cast<DWORD>(status), 0, reinterpret_cast<wchar_t*>(&text), 0, nullptr);
  std::string message = length == 0 ? "" : Utf8FromUtf16(text);
  if (text != nullptr) {
    ::LocalFree(text);
  }
  while (!message.empty() && (message.back() == '\n' || message.back() == '\r' || message.back() == ' ')) {
    message.pop_back();
  }
  return message.empty() ? "錯誤代碼 " + std::to_string(status) : message;
}

}  // namespace

std::string LaunchAtLoginStatus() {
  const std::optional<std::wstring> command = ReadRunCommand();
  if (!command.has_value()) {
    return "disabled";
  }
  // 指向目前的程式但格式不同（例如少了 --hidden），或指向的程式不在了（換了安裝位置、免安裝版換了資料夾）：改指向目前的程式。
  // 指向另一份還在的 Securibit（例如另一個資料夾的免安裝版）就不動
  const std::wstring current = CurrentExecutable();
  const std::wstring target = ExecutableFromCommand(*command);
  const std::wstring expected = RunCommandFor(current);
  if (!current.empty() && *command != expected &&
      (SamePath(target, current) || ::GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES)) {
    WriteRunCommand(expected);
  }
  return DisabledInSettings() ? "requiresApproval" : "enabled";
}

bool SetLaunchAtLogin(bool enabled, std::string* error) {
  LSTATUS status;
  if (enabled) {
    const std::wstring current = CurrentExecutable();
    if (current.empty()) {
      *error = "找不到 Securibit 的程式位置";
      return false;
    }
    status = WriteRunCommand(RunCommandFor(current));
  } else {
    status = ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kValueName);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  if (status != ERROR_SUCCESS) {
    *error = "無法寫入登錄檔：" + SystemMessage(status);
    return false;
  }
  // 在 App 裡打開就是要它自動開啟：之前在「設定 › 應用程式 › 啟動」關掉的紀錄一起清掉（沒有這筆就是允許）
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kApprovedKey, kValueName);
  return true;
}

void OpenStartupAppsSettings() {
  ::ShellExecuteW(nullptr, L"open", L"ms-settings:startupapps", nullptr, nullptr, SW_SHOWNORMAL);
}

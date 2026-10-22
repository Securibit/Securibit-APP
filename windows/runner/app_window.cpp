#include "app_window.h"

namespace {

constexpr const wchar_t kMutexName[] = L"Local\\Securibit-com.bityo.securibit";
// Flutter runner 的視窗類別（win32_window.cpp 的 kWindowClassName）
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

}  // namespace

SingleInstance::SingleInstance() {
  mutex_ = ::CreateMutexW(nullptr, FALSE, kMutexName);
  first_ = mutex_ == nullptr || ::GetLastError() != ERROR_ALREADY_EXISTS;
}

SingleInstance::~SingleInstance() {
  if (mutex_ != nullptr) {
    ::CloseHandle(mutex_);
  }
}

HWND SingleInstance::FindRunningWindow() const {
  for (int attempt = 0; attempt < 50; attempt++) {
    HWND hwnd = ::FindWindowW(kWindowClassName, kWindowTitle);
    if (hwnd != nullptr) {
      return hwnd;
    }
    ::Sleep(100);
  }
  return nullptr;
}

void BringWindowToFront(HWND hwnd) {
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  } else if (!::IsWindowVisible(hwnd)) {
    ::ShowWindow(hwnd, SW_SHOW);
  }
  if (::SetForegroundWindow(hwnd)) {
    return;
  }
  FLASHWINFO flash = {sizeof(FLASHWINFO)};
  flash.hwnd = hwnd;
  flash.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
  ::FlashWindowEx(&flash);
}

#ifndef RUNNER_APP_WINDOW_H_
#define RUNNER_APP_WINDOW_H_

#include <windows.h>

// 主視窗的標題（另一個執行個體用它和視窗類別找到開著的 Securibit）
constexpr const wchar_t kWindowTitle[] = L"Securibit";

// 登入時自動開啟帶的參數（見 launch_at_login.h）：主視窗一開始就藏在系統匣。
// Dart 端也看這個參數（lib/core/window_visibility.dart 的 hiddenArgument），兩邊要一起改
constexpr const wchar_t kHiddenArgument[] = L"--hidden";

// 請開著的 Securibit 結束的視窗訊息（RegisterWindowMessage），效果同系統匣的「結束 Securibit」。
// 安裝檔（tool/windows/securibit.iss 的 AppQuitMessage）在安裝、解除安裝前用它結束藏在系統匣的 App；兩邊要一起改
constexpr const wchar_t kQuitMessageName[] = L"Securibit.Quit";

// 最小尺寸（邏輯像素，不含標題列與邊框）：收合成單欄，同 macOS 的 contentMinSize
constexpr int kMinWidth = 400;
constexpr int kMinHeight = 560;

// 同一個使用者只能開一個 Securibit。
// 互斥鎖的名稱也寫在安裝檔（tool/windows/securibit.iss 的 AppMutexName），
// 安裝或自動更新時用它等 App 結束；兩邊要一起改
class SingleInstance {
 public:
  SingleInstance();
  ~SingleInstance();

  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // 這是第一個開的 Securibit
  bool IsFirst() const { return first_; }

  // 找到已經開著的 Securibit 的主視窗；它剛啟動、視窗還沒建立時等一下（最多幾秒），找不到回傳 nullptr
  HWND FindRunningWindow() const;

 private:
  HANDLE mutex_ = nullptr;
  bool first_ = true;
};

// 把視窗還原（最小化時）並切到前景；系統不讓切時（例如使用者正在用別的程式）改成在工作列閃爍
void BringWindowToFront(HWND hwnd);

#endif  // RUNNER_APP_WINDOW_H_

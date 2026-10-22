#ifndef RUNNER_LAUNCH_AT_LOGIN_H_
#define RUNNER_LAUNCH_AT_LOGIN_H_

#include <string>

/*
 * 登入時自動開啟：HKCU\Software\Microsoft\Windows\CurrentVersion\Run 的「Securibit」值，
 * 內容是 "<目前的 securibit.exe>" --hidden，登入時直接藏在系統匣、不跳出視窗。
 * 使用者在「設定 › 應用程式 › 啟動」或工作管理員關掉時，Windows 不動 Run 值，
 * 而是在 Explorer\StartupApproved\Run 記一筆「已停用」，所以狀態要兩邊一起看。
 * 安裝檔（tool/windows/securibit.iss）更新時改指向新的位置、解除安裝時刪掉，值的名稱兩邊要一起改。
 */

// "enabled"、"disabled" 或 "requiresApproval"（已登記，但在「設定 › 應用程式 › 啟動」被關掉）。
// 已登記但指向的程式不在了（例如換了安裝位置）時，順便改指向目前的程式
std::string LaunchAtLoginStatus();

// 登記或取消；失敗時回傳 false，error 是原因
bool SetLaunchAtLogin(bool enabled, std::string* error);

// 打開「設定 › 應用程式 › 啟動」
void OpenStartupAppsSettings();

#endif  // RUNNER_LAUNCH_AT_LOGIN_H_

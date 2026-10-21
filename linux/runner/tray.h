#ifndef RUNNER_TRAY_H_
#define RUNNER_TRAY_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

/*
 * Linux 系統匣常駐（channel：securibit/menubar，Dart 端見 lib/features/menubar/，和 macOS 選單列共用）。
 * 詳細說明見 tray.cc。
 */

// 主視窗建好、Flutter 引擎起來之後呼叫一次
void tray_attach(GtkApplication* app, GtkWindow* window,
                 FlBinaryMessenger* messenger);

// 關閉視窗（delete-event）：系統匣常駐時把視窗藏起來並回傳 TRUE（不關閉），否則回傳 FALSE 照常關閉
gboolean tray_handle_close();

// 叫回主視窗（再次開啟 App、點系統匣的「打開 Securibit」）
void tray_show_main_window();

#endif  // RUNNER_TRAY_H_

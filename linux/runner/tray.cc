#include "tray.h"

#include <libayatana-appindicator/app-indicator.h>

#include <map>
#include <string>

/*
 * Linux 系統匣常駐（Dart 端見 lib/features/menubar/，macOS 的對應實作是 macos/Runner/MenuBarController.swift）：
 * - 圖示用 Ayatana AppIndicator（StatusNotifierItem）；選單是 GTK 選單，經 dbusmenu 交給面板去畫，
 *   所以每一筆只能是一行純文字（Dart 算好的 label），不能排欄位或上色
 * - Dart 是唯一的資料來源：原生端只拿到顯示用的文字，金鑰一直在 Dart；點了要複製也是請 Dart 算當下的碼
 * - 選單要打開時（面板送 dbusmenu 的 AboutToShow 或 opened 事件；退回 GtkStatusIcon 時是 GtkMenu 的 show）向 Dart 要含驗證碼的內容。
 *   不是每個面板都會通知，所以主視窗藏起來（只能從系統匣看驗證碼）或選單開著時，每秒向 Dart 要一次最新內容
 * - 打開系統匣、而且桌面真的有系統匣（連上 StatusNotifierWatcher）時，關掉主視窗只是藏起來，「結束 Securibit」才真的結束；
 *   桌面沒有系統匣（例如沒裝 AppIndicator 擴充功能的 GNOME）時照常結束，免得視窗藏起來卻叫不回來
 * - 主視窗藏起來或重新顯示時通知 Dart（windowWillHide／windowDidShow），App 鎖定把它當成離開與回來
 */

namespace {

constexpr char kChannelName[] = "securibit/menubar";
constexpr char kIndicatorId[] = "com.bityo.securibit";
constexpr char kIconName[] = "securibit-tray-symbolic";
// 有些面板不送 closed 事件，選單打開後最多當作開著這麼久
constexpr gint64 kMenuOpenTimeoutUs = 60 * G_USEC_PER_SEC;
// 藏視窗前等 Dart 畫好鎖定畫面，最多等這麼久
constexpr guint kHideTimeoutMs = 500;
constexpr guint kCopiedMs = 1500;
constexpr char kIdKey[] = "securibit-id";

struct Tray {
  GtkApplication* app = nullptr;
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;
  AppIndicator* indicator = nullptr;
  GtkWidget* menu = nullptr;
  // dbusmenu 的根節點（AboutToShow 與 opened／closed 事件從這裡來）
  GObject* menu_root = nullptr;

  bool enabled = false;
  // 有連上 StatusNotifierWatcher（桌面有系統匣）
  bool connected = false;
  bool window_hidden = false;
  bool menu_open = false;
  gint64 menu_opened_at = 0;
  // 每次藏視窗加一，舊的回覆或逾時不會藏掉之後又叫回來的視窗
  guint hide_serial = 0;

  guint tick_source = 0;
  guint copied_source = 0;

  // 目前畫出來的內容與它的結構（結構沒變就只更新文字）
  FlValue* model = nullptr;
  std::string structure;
  std::map<std::string, GtkWidget*> code_items;
};

Tray* tray = nullptr;

// MARK: - FlValue 小工具

FlValue* lookup(FlValue* map, const char* key, FlValueType type) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP)
    return nullptr;
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != type) return nullptr;
  return value;
}

const gchar* lookup_string(FlValue* map, const char* key) {
  FlValue* value = lookup(map, key, FL_VALUE_TYPE_STRING);
  return value == nullptr ? nullptr : fl_value_get_string(value);
}

bool lookup_bool(FlValue* map, const char* key) {
  FlValue* value = lookup(map, key, FL_VALUE_TYPE_BOOL);
  return value != nullptr && fl_value_get_bool(value);
}

size_t list_length(FlValue* list) {
  return list == nullptr ? 0 : fl_value_get_length(list);
}

FlValue* list_at(FlValue* list, size_t index) {
  return fl_value_get_list_value(list, index);
}

std::string str(const gchar* value) { return value == nullptr ? "" : value; }

// MARK: - 與 Dart 溝通

void apply(FlValue* model);
void schedule_tick();

void invoke(const char* method, FlValue* args, GAsyncReadyCallback callback,
            gpointer user_data) {
  if (tray->channel == nullptr) return;
  fl_method_channel_invoke_method(tray->channel, method, args, nullptr,
                                  callback, user_data);
}

// 取得呼叫結果；失敗或沒有結果時是 nullptr。回傳的 response 要 unref
FlValue* finish(GObject* object, GAsyncResult* result,
                FlMethodResponse** response) {
  g_autoptr(GError) error = nullptr;
  *response = fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object),
                                                     result, &error);
  if (*response == nullptr) return nullptr;
  return fl_method_response_get_result(*response, nullptr);
}

// 選單開著或主視窗藏著時，才接受含驗證碼的內容
bool live() { return tray->enabled && (tray->menu_open || tray->window_hidden); }

void on_snapshot(GObject* object, GAsyncResult* result, gpointer user_data) {
  FlMethodResponse* response = nullptr;
  FlValue* value = finish(object, result, &response);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_MAP &&
      live()) {
    apply(value);
  }
  g_clear_object(&response);
}

void request_snapshot(const char* method) {
  invoke(method, nullptr, on_snapshot, nullptr);
}

// MARK: - 選單要打開／關起來

void menu_will_open() {
  if (!tray->enabled) return;
  tray->menu_open = true;
  tray->menu_opened_at = g_get_monotonic_time();
  request_snapshot("menuWillOpen");
  schedule_tick();
}

void menu_did_close() {
  if (!tray->menu_open) return;
  tray->menu_open = false;
  invoke("menuDidClose", nullptr, nullptr, nullptr);
}

gboolean on_root_about_to_show(GObject* item, gpointer user_data) {
  menu_will_open();
  return FALSE;
}

void on_root_event(GObject* item, const gchar* name, GVariant* value,
                   guint timestamp, gpointer user_data) {
  if (g_strcmp0(name, "opened") == 0) {
    menu_will_open();
  } else if (g_strcmp0(name, "closed") == 0) {
    menu_did_close();
  }
}

void on_gtk_menu_show(GtkWidget* widget, gpointer user_data) {
  menu_will_open();
}

void on_gtk_menu_hide(GtkWidget* widget, gpointer user_data) {
  menu_did_close();
}

// 從 AppIndicator 取得 dbusmenu 的根節點，接上 AboutToShow 與 opened／closed 事件
void connect_menu_root() {
  if (tray->menu_root != nullptr || tray->indicator == nullptr) return;
  GObjectClass* klass = G_OBJECT_GET_CLASS(tray->indicator);
  if (g_object_class_find_property(klass, "dbus-menu-server") == nullptr)
    return;
  GObject* server = nullptr;
  g_object_get(tray->indicator, "dbus-menu-server", &server, nullptr);
  if (server == nullptr) return;
  GObject* root = nullptr;
  if (g_object_class_find_property(G_OBJECT_GET_CLASS(server), "root-node") !=
      nullptr) {
    g_object_get(server, "root-node", &root, nullptr);
  }
  g_object_unref(server);
  if (root == nullptr) return;
  tray->menu_root = root;
  g_signal_connect(root, "about-to-show", G_CALLBACK(on_root_about_to_show),
                   nullptr);
  g_signal_connect(root, "event", G_CALLBACK(on_root_event), nullptr);
}

// MARK: - 每秒更新

gboolean on_tick(gpointer user_data) {
  tray->tick_source = 0;
  if (tray->menu_open && !tray->window_hidden &&
      g_get_monotonic_time() - tray->menu_opened_at > kMenuOpenTimeoutUs) {
    menu_did_close();
  }
  if (!live()) return G_SOURCE_REMOVE;
  request_snapshot("tick");
  schedule_tick();
  return G_SOURCE_REMOVE;
}

// 對齊整秒，驗證碼換新的那一刻就更新
void schedule_tick() {
  if (tray->tick_source != 0 || !live()) return;
  gint64 ms = g_get_real_time() / 1000;
  guint delay = static_cast<guint>(1000 - ms % 1000 + 5);
  tray->tick_source = g_timeout_add(delay, on_tick, nullptr);
}

void stop_tick() {
  if (tray->tick_source != 0) {
    g_source_remove(tray->tick_source);
    tray->tick_source = 0;
  }
}

// MARK: - 動作

gboolean on_copied_reset(gpointer user_data) {
  tray->copied_source = 0;
  if (tray->indicator != nullptr) app_indicator_set_label(tray->indicator, "", "");
  return G_SOURCE_REMOVE;
}

// 複製後圖示旁短暫顯示「已複製」（GNOME 與 Unity 系的面板會顯示，KDE 不顯示文字）
void show_copied() {
  if (tray->indicator == nullptr) return;
  app_indicator_set_label(tray->indicator, "已複製", "已複製");
  if (tray->copied_source != 0) g_source_remove(tray->copied_source);
  tray->copied_source = g_timeout_add(kCopiedMs, on_copied_reset, nullptr);
}

void on_copy_result(GObject* object, GAsyncResult* result, gpointer user_data) {
  FlMethodResponse* response = nullptr;
  FlValue* value = finish(object, result, &response);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
      fl_value_get_bool(value)) {
    show_copied();
  }
  g_clear_object(&response);
}

void on_copy(GtkMenuItem* item, gpointer user_data) {
  const gchar* id =
      static_cast<const gchar*>(g_object_get_data(G_OBJECT(item), kIdKey));
  if (id == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(id));
  invoke("copy", args, on_copy_result, nullptr);
}

void on_open_app(GtkMenuItem* item, gpointer user_data) {
  tray_show_main_window();
}

void on_open_settings(GtkMenuItem* item, gpointer user_data) {
  tray_show_main_window();
  invoke("openSettings", nullptr, nullptr, nullptr);
}

void on_quit(GtkMenuItem* item, gpointer user_data) {
  g_application_quit(G_APPLICATION(tray->app));
}

// MARK: - 選單內容

GtkWidget* add_item(GtkWidget* menu, const std::string& label, bool sensitive,
                    GCallback callback) {
  // gtk_menu_item_new_with_label 不把底線當成快速鍵，名稱裡的底線會照樣顯示
  GtkWidget* item = gtk_menu_item_new_with_label(label.c_str());
  gtk_widget_set_sensitive(item, sensitive);
  if (callback != nullptr) g_signal_connect(item, "activate", callback, nullptr);
  gtk_widget_show(item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  return item;
}

void add_separator(GtkWidget* menu) {
  GtkWidget* item = gtk_separator_menu_item_new();
  gtk_widget_show(item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
}

FlValue* sections(FlValue* model) {
  return lookup(model, "sections", FL_VALUE_TYPE_LIST);
}

FlValue* items(FlValue* section) {
  return lookup(section, "items", FL_VALUE_TYPE_LIST);
}

// 狀態、訊息、群組、各筆 id 與說明都一樣時視為同一個結構（同 macOS）
std::string structure_key(FlValue* model) {
  std::string key = str(lookup_string(model, "status")) + "\n" +
                    str(lookup_string(model, "message")) + "\n" +
                    (lookup_bool(model, "submenus") ? "1" : "0") +
                    (lookup_bool(model, "showSettings") ? "1" : "0");
  FlValue* list = sections(model);
  for (size_t i = 0; i < list_length(list); i++) {
    FlValue* section = list_at(list, i);
    key += "\n#" + str(lookup_string(section, "id")) + "|" +
           str(lookup_string(section, "title")) + "|" +
           str(lookup_string(section, "note"));
    FlValue* entries = items(section);
    for (size_t j = 0; j < list_length(entries); j++) {
      key += "\n" + str(lookup_string(list_at(entries, j), "id"));
    }
  }
  return key;
}

void add_section_content(FlValue* section, GtkWidget* target) {
  FlValue* entries = items(section);
  if (list_length(entries) == 0) {
    add_item(target, str(lookup_string(section, "note")), false, nullptr);
    return;
  }
  for (size_t i = 0; i < list_length(entries); i++) {
    FlValue* entry = list_at(entries, i);
    const gchar* id = lookup_string(entry, "id");
    if (id == nullptr) continue;
    GtkWidget* item = add_item(target, str(lookup_string(entry, "label")),
                               false, G_CALLBACK(on_copy));
    g_object_set_data_full(G_OBJECT(item), kIdKey, g_strdup(id), g_free);
    tray->code_items[id] = item;
  }
}

void update_items() {
  FlValue* list = sections(tray->model);
  for (size_t i = 0; i < list_length(list); i++) {
    FlValue* entries = items(list_at(list, i));
    for (size_t j = 0; j < list_length(entries); j++) {
      FlValue* entry = list_at(entries, j);
      auto found = tray->code_items.find(str(lookup_string(entry, "id")));
      if (found == tray->code_items.end()) continue;
      GtkMenuItem* item = GTK_MENU_ITEM(found->second);
      // 沒變的不設定，面板才不會每秒收到所有項目的變更
      std::string label = str(lookup_string(entry, "label"));
      if (str(gtk_menu_item_get_label(item)) != label)
        gtk_menu_item_set_label(item, label.c_str());
      bool copyable = lookup_bool(entry, "copyable");
      if (gtk_widget_get_sensitive(GTK_WIDGET(item)) != copyable)
        gtk_widget_set_sensitive(GTK_WIDGET(item), copyable);
    }
  }
}

void rebuild() {
  tray->structure = structure_key(tray->model);
  tray->code_items.clear();
  GtkWidget* menu = tray->menu;
  GList* children = gtk_container_get_children(GTK_CONTAINER(menu));
  for (GList* child = children; child != nullptr; child = child->next) {
    gtk_widget_destroy(GTK_WIDGET(child->data));
  }
  g_list_free(children);

  FlValue* model = tray->model;
  bool has_content = false;
  const gchar* message = lookup_string(model, "message");
  if (message != nullptr) {
    // 已鎖定時點一下打開 App 解鎖
    bool locked = g_strcmp0(lookup_string(model, "status"), "locked") == 0;
    add_item(menu, message, locked, locked ? G_CALLBACK(on_open_app) : nullptr);
    has_content = true;
  }

  FlValue* list = sections(model);
  if (lookup_bool(model, "submenus")) {
    // 驗證碼很多時每個群組收成一個子選單
    for (size_t i = 0; i < list_length(list); i++) {
      FlValue* section = list_at(list, i);
      GtkWidget* parent =
          add_item(menu, str(lookup_string(section, "title")), true, nullptr);
      GtkWidget* submenu = gtk_menu_new();
      add_section_content(section, submenu);
      gtk_menu_item_set_submenu(GTK_MENU_ITEM(parent), submenu);
      has_content = true;
    }
  } else {
    // 群組名稱是一行不能點的標題，群組之間用分隔線隔開
    for (size_t i = 0; i < list_length(list); i++) {
      FlValue* section = list_at(list, i);
      if (i > 0) add_separator(menu);
      add_item(menu, str(lookup_string(section, "title")), false, nullptr);
      add_section_content(section, menu);
      has_content = true;
    }
  }

  if (has_content) add_separator(menu);
  add_item(menu, "打開 Securibit", true, G_CALLBACK(on_open_app));
  if (lookup_bool(model, "showSettings")) {
    add_item(menu, "設定…", true, G_CALLBACK(on_open_settings));
  }
  add_separator(menu);
  add_item(menu, "結束 Securibit", true, G_CALLBACK(on_quit));

  update_items();
}

void apply(FlValue* model) {
  if (tray->model != nullptr) fl_value_unref(tray->model);
  tray->model = fl_value_ref(model);
  if (tray->menu == nullptr) return;
  if (structure_key(model) != tray->structure) {
    rebuild();
  } else {
    update_items();
  }
}

// MARK: - 系統匣圖示

// 圖示放在 bundle 的 data/icons（見 linux/CMakeLists.txt）
gchar* icon_dir() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return nullptr;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  return g_build_filename(dir, "data", "icons", nullptr);
}

void on_connection_changed(AppIndicator* indicator, gboolean connected,
                           gpointer user_data) {
  tray->connected = connected;
  // 系統匣不見了（例如面板重新啟動中）而視窗藏著，就叫回主視窗
  if (!connected && tray->window_hidden) tray_show_main_window();
}

void create_indicator() {
  g_autofree gchar* dir = icon_dir();
  tray->indicator = app_indicator_new_with_path(
      kIndicatorId, kIconName, APP_INDICATOR_CATEGORY_APPLICATION_STATUS,
      dir != nullptr ? dir : "");
  app_indicator_set_title(tray->indicator, "Securibit");
  g_signal_connect(tray->indicator, APP_INDICATOR_SIGNAL_CONNECTION_CHANGED,
                   G_CALLBACK(on_connection_changed), nullptr);

  tray->menu = gtk_menu_new();
  g_object_ref_sink(tray->menu);
  g_signal_connect(tray->menu, "show", G_CALLBACK(on_gtk_menu_show), nullptr);
  g_signal_connect(tray->menu, "hide", G_CALLBACK(on_gtk_menu_hide), nullptr);
  rebuild();
  app_indicator_set_menu(tray->indicator, GTK_MENU(tray->menu));
  connect_menu_root();
}

void set_enabled(bool enabled) {
  if (enabled == tray->enabled) return;
  tray->enabled = enabled;
  if (enabled) {
    if (tray->indicator == nullptr) create_indicator();
    app_indicator_set_status(tray->indicator, APP_INDICATOR_STATUS_ACTIVE);
    schedule_tick();
  } else {
    stop_tick();
    tray->menu_open = false;
    if (tray->indicator != nullptr)
      app_indicator_set_status(tray->indicator, APP_INDICATOR_STATUS_PASSIVE);
    // 沒有系統匣就不能藏著，叫回主視窗
    if (tray->window_hidden) tray_show_main_window();
  }
}

// MARK: - channel

void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                    gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(method, "setEnabled") == 0) {
    set_enabled(lookup_bool(args, "enabled"));
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "update") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
      apply(args);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    // 登入時自動開啟在 Linux 由 Dart 直接寫 autostart 檔
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

// MARK: - 主視窗

// Dart 的回覆與逾時哪個先到就先藏；兩邊都跑過才釋放
struct HideRequest {
  guint serial;
  bool done = false;
  int pending = 2;
};

void finish_hide(HideRequest* request) {
  if (!request->done) {
    request->done = true;
    // 這段時間內又被叫回來就不藏了
    if (tray->window_hidden && request->serial == tray->hide_serial)
      gtk_widget_hide(GTK_WIDGET(tray->window));
  }
  if (--request->pending == 0) delete request;
}

void on_will_hide_result(GObject* object, GAsyncResult* result,
                         gpointer user_data) {
  FlMethodResponse* response = nullptr;
  finish(object, result, &response);
  g_clear_object(&response);
  finish_hide(static_cast<HideRequest*>(user_data));
}

gboolean on_hide_timeout(gpointer user_data) {
  finish_hide(static_cast<HideRequest*>(user_data));
  return G_SOURCE_REMOVE;
}

// 先讓 Dart 鎖定並畫好畫面再藏視窗，最多等 0.5 秒
void hide_main_window() {
  if (tray->window_hidden) return;
  tray->window_hidden = true;
  tray->hide_serial++;
  HideRequest* request = new HideRequest();
  request->serial = tray->hide_serial;
  invoke("windowWillHide", nullptr, on_will_hide_result, request);
  g_timeout_add(kHideTimeoutMs, on_hide_timeout, request);
  schedule_tick();
}

}  // namespace

void tray_attach(GtkApplication* app, GtkWindow* window,
                 FlBinaryMessenger* messenger) {
  if (tray != nullptr) return;
  tray = new Tray();
  tray->app = app;
  tray->window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  tray->channel = fl_method_channel_new(messenger, kChannelName,
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(tray->channel, on_method_call,
                                            nullptr, nullptr);
}

gboolean tray_handle_close() {
  if (tray == nullptr || !tray->enabled || !tray->connected) return FALSE;
  hide_main_window();
  return TRUE;
}

void tray_show_main_window() {
  if (tray == nullptr) return;
  GtkWindow* window = tray->window;
  gtk_widget_show(GTK_WIDGET(window));
  gtk_window_deiconify(window);
  gtk_window_present(window);
  if (tray->window_hidden) {
    tray->window_hidden = false;
    invoke("windowDidShow", nullptr, nullptr, nullptr);
  }
}

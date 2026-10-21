#!/usr/bin/env python3
"""
最小的 StatusNotifierWatcher（make linux-smoke 用）。

容器裡沒有桌面面板，Securibit 的 AppIndicator 找不到系統匣就不會常駐。
這支程式在 session bus 上扮演 org.kde.StatusNotifierWatcher，讓 App 以為桌面有系統匣，
並把登記進來的項目（「bus 名稱/物件路徑」）一行一行寫到指定的檔案，測試腳本再用 gdbus 讀選單內容、點選單項目。

  python3 sni_watcher.py <記錄檔>
"""
import sys

from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.kde.StatusNotifierWatcher">
    <method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
    <method name="RegisterStatusNotifierHost"><arg type="s" direction="in"/></method>
    <property name="RegisteredStatusNotifierItems" type="as" access="read"/>
    <property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
    <property name="ProtocolVersion" type="i" access="read"/>
    <signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
    <signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
    <signal name="StatusNotifierHostRegistered"/>
  </interface>
</node>
"""
PATH = "/StatusNotifierWatcher"
IFACE = "org.kde.StatusNotifierWatcher"

log_path = sys.argv[1]
items = []


def on_call(conn, sender, path, iface, method, params, invocation):
    if method == "RegisterStatusNotifierItem":
        service = params.unpack()[0]
        # 只給物件路徑時，bus 名稱是呼叫者
        item = sender + service if service.startswith("/") else service + "/StatusNotifierItem"
        items.append(item)
        with open(log_path, "a") as f:
            f.write(item + "\n")
        conn.emit_signal(None, PATH, IFACE, "StatusNotifierItemRegistered", GLib.Variant("(s)", (item,)))
    invocation.return_value(None)


def on_get(conn, sender, path, iface, prop):
    if prop == "RegisteredStatusNotifierItems":
        return GLib.Variant("as", items)
    if prop == "IsStatusNotifierHostRegistered":
        return GLib.Variant("b", True)
    return GLib.Variant("i", 0)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object(PATH, node.interfaces[0], on_call, on_get, None)


Gio.bus_own_name(Gio.BusType.SESSION, IFACE, Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()

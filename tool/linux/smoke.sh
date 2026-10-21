#!/usr/bin/env bash
#
# 在容器裡實際執行 Linux bundle 並截圖（make linux-smoke 用，映像檔是 docker/linux.Dockerfile 的 smoke stage）。
# Xvfb ＋ openbox（有標題列，才看得到視窗標題）＋ dbus session ＋ gnome-keyring（Secret Service），
# 再用 sni_watcher.py 假裝桌面有系統匣，檢查：
#   1. 視窗開出來、標題是 Securibit、大小是預設的 1180×760，畫面是登入或導覽
#   2. 系統匣選單的內容（dbusmenu GetLayout）
#   3. 關閉視窗只是藏起來，App 還在跑；點系統匣的「打開 Securibit」叫回來
#   4. 再開一次 App 會叫回藏起來的視窗，不會多開一個
#   5. 「結束 Securibit」會結束 App
#   6. 桌面沒有系統匣時，關閉視窗就結束
#
# 環境變數：BUNDLE（Securibit-*-linux-*.tar.gz）、SHOTS（截圖與紀錄放這裡）、HOST_UID／HOST_GID
set -euo pipefail

if [[ -z "${IN_SESSION:-}" ]]; then
  mkdir -p "$SHOTS"
  rm -rf /tmp/app && mkdir -p /tmp/app
  tar -xzf "$BUNDLE" -C /tmp/app
  export DISPLAY=:99
  Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
  for _ in $(seq 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
  openbox >/tmp/openbox.log 2>&1 &
  set +e
  IN_SESSION=1 dbus-run-session -- "$0"
  rc=$?
  set -e
  [[ -n "${HOST_UID:-}" ]] && chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$SHOTS"
  exit $rc
fi

here="$(cd "$(dirname "$0")" && pwd)"
app=/tmp/app/securibit/securibit
pass=0
fail=0
ok() { echo "  ✓ $*"; pass=$((pass + 1)); }
bad() { echo "  ✗ $*"; fail=$((fail + 1)); }
check() { local msg="$1"; shift; if "$@"; then ok "$msg"; else bad "$msg"; fi; }

# gnome-keyring 當 Secret Service（登入狀態存在這裡）
eval "$(printf 'smoke' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)" || true
export GNOME_KEYRING_CONTROL

window_id() { xdotool search --onlyvisible --name '^Securibit$' 2>/dev/null | head -1; }
any_window_id() { xdotool search --name '^Securibit$' 2>/dev/null | head -1; }
wait_for() { local i; for i in $(seq "${2:-100}"); do eval "$1" && return 0; sleep 0.2; done; return 1; }
alive() { kill -0 "$1" 2>/dev/null; }
shot() { import -window root "$SHOTS/$1.png"; echo "    截圖：$SHOTS/$1.png"; }

# dbusmenu：讀系統匣項目的選單、找某個標籤的 id、送出點擊
sni_item() { tail -1 /tmp/sni.log; }
menu_call() {
  local item bus path menu
  item="$(sni_item)"; bus="${item%%/*}"; path="/${item#*/}"
  menu="$(gdbus call --session --dest "$bus" --object-path "$path" \
    --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem Menu | sed -E "s/.*objectpath '([^']+)'.*/\1/")"
  gdbus call --session --dest "$bus" --object-path "$menu" --method "com.canonical.dbusmenu.$1" -- "${@:2}"
}
menu_layout() { menu_call GetLayout 0 -1 "['label', 'enabled', 'type', 'children-display']"; }
menu_id() { menu_layout | grep -oE "\([0-9]+, \{[^}]*'label': <'$1'>" | head -1 | sed -E 's/^\(([0-9]+).*/\1/'; }
menu_click() { menu_call Event "$(menu_id "$1")" clicked '<int32 0>' 0 >/dev/null; }

echo "==> 1. 啟動"
python3 "$here/sni_watcher.py" /tmp/sni.log &
watcher=$!
: > /tmp/sni.log
"$app" >/tmp/app.log 2>&1 &
pid=$!
if wait_for '[[ -n "$(window_id)" ]]' 150; then ok "視窗開出來了"; else bad "視窗沒有出現"; cat /tmp/app.log; exit 1; fi
sleep 8   # 等 Flutter 畫完第一個畫面與 Supabase 初始化
win="$(window_id)"
geometry="$(xdotool getwindowgeometry "$win" | sed -n 's/.*Geometry: //p')"
title="$(xdotool getwindowname "$win")"
check "標題是 Securibit（$title）" [ "$title" = Securibit ]
check "大小是 1180x760（$geometry）" [ "$geometry" = 1180x760 ]
xprop -id "$win" WM_CLASS | sed 's/^/    /'
shot 01-window

echo "==> 2. 系統匣"
check "AppIndicator 登記到系統匣（$(sni_item)）" wait_for '[[ -s /tmp/sni.log ]]' 50
menu_call AboutToShow 0 >/dev/null || true
sleep 1.5
menu_layout > "$SHOTS/tray-menu.txt"
# 第一個是 dbusmenu 的根節點，不算
labels="$(grep -oE "'label': <'[^']*'>" "$SHOTS/tray-menu.txt" | tail -n +2 | sed -E "s/'label': <'(.*)'>/\1/" | paste -sd '|' - || true)"
echo "    選單：$labels"
check "選單有「打開 Securibit」與「結束 Securibit」" grep -q "打開 Securibit.*結束 Securibit" <<<"$labels"
check "沒有登入時顯示「尚未登入」、沒有「設定…」" [ "$labels" = '尚未登入|打開 Securibit|結束 Securibit' ]

echo "==> 3. 關閉視窗只是藏起來"
wmctrl -c Securibit
wait_for '[[ -z "$(window_id)" ]]' 50 || true
check "視窗藏起來了" [ -z "$(window_id)" ]
check "App 還在跑" alive $pid
shot 02-hidden
menu_click '打開 Securibit'
check "點「打開 Securibit」叫回視窗" wait_for '[[ -n "$(window_id)" ]]' 50
sleep 1
shot 03-reopened

echo "==> 4. 再開一次只會叫回原本的視窗"
wmctrl -c Securibit
wait_for '[[ -z "$(window_id)" ]]' 50 || true
second=0
timeout 20 "$app" >/tmp/app2.log 2>&1 || second=$?
check "第二個 App 直接結束（$second）" [ $second -eq 0 ]
check "原本的視窗回來了" wait_for '[[ -n "$(window_id)" ]]' 50
check "只有一個視窗" [ "$(xdotool search --name '^Securibit$' | wc -l)" -eq 1 ]

echo "==> 5. 結束 Securibit"
menu_click '結束 Securibit'
check "App 結束了" wait_for '! alive $pid' 50

echo "==> 6. 沒有系統匣時關閉視窗就結束"
kill $watcher; wait $watcher 2>/dev/null || true
"$app" >/tmp/app3.log 2>&1 &
pid=$!
wait_for '[[ -n "$(window_id)" ]]' 150 || true
sleep 3
wmctrl -c Securibit
check "沒有系統匣時關閉視窗就結束" wait_for '! alive $pid' 50

echo
grep -iE 'critical|error' /tmp/app.log /tmp/app3.log | grep -v 'Gdk-CRITICAL.*gdk_window_thaw' | head -20 | sed 's/^/    log: /' || true
cp /tmp/app.log "$SHOTS/app.log"
echo "通過 $pass 項，失敗 $fail 項"
[ $fail -eq 0 ]

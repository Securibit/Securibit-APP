#!/usr/bin/env bash
#
# 在乾淨的 Debian / Ubuntu 容器裡安裝 .deb 並確認能啟動（make deb-check 用）。
#
#   tool/linux/deb_check.sh <.deb 路徑>
set -euo pipefail

deb="$1"
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
echo "    系統：$PRETTY_NAME"

apt-get update -qq
# 和使用者一樣用 apt 安裝本機的 .deb（相依套件與 Recommends 由 apt 解決）
apt-get install -y -qq "$deb" >/tmp/apt.log 2>&1 || { tail -30 /tmp/apt.log; exit 1; }
dpkg -s securibit | sed -n 's/^\(Version\|Depends\|Recommends\): /    \1: /p'

# 外掛的 .so 靠主程式先載入的 libflutter，所以只檢查主程式（ldd 會連同所有間接相依一起解析）
missing="$(ldd /opt/securibit/securibit 2>&1 | grep 'not found' || true)"
if [[ -n "$missing" ]]; then
  echo "    缺少函式庫：" && echo "$missing"
  exit 1
fi
test "$(readlink /usr/bin/securibit)" = /opt/securibit/securibit
test -f /usr/share/applications/com.bityo.securibit.desktop
# 點 securibit://、otpauth://、otpauth-migration:// 連結時開 Securibit
grep -q '^MimeType=.*x-scheme-handler/otpauth-migration;' /usr/share/applications/com.bityo.securibit.desktop
test -f /usr/share/icons/hicolor/256x256/apps/com.bityo.securibit.png

# 在虛擬螢幕上啟動，10 秒後還在跑就算成功（timeout 結束時回傳 124）
apt-get install -y -qq xvfb xauth >/dev/null 2>&1
set +e
timeout 10 xvfb-run -a -s '-screen 0 1280x800x24' /usr/bin/securibit >/tmp/run.log 2>&1
rc=$?
set -e
if [[ $rc -ne 124 ]]; then
  echo "    securibit 提早結束（$rc）："
  tail -20 /tmp/run.log
  exit 1
fi
echo "    安裝與啟動正常"

#!/usr/bin/env bash
#
# 在乾淨的 Debian / Ubuntu 容器裡執行 AppImage（make appimage-check 用）。
# 只裝桌面一定會有的 GTK 3 與 OpenGL（EGL、GL）驅動，不裝系統匣、libsecret，確認 AppImage 帶的函式庫夠用、程式能啟動。
# 容器裡沒有 FUSE，用 --appimage-extract-and-run 解開再執行。
#
#   tool/linux/appimage_check.sh <AppImage 路徑>
set -euo pipefail

image="$1"
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
echo "    系統：$PRETTY_NAME"
apt-get update -qq
apt-get install -y -qq --no-install-recommends libgtk-3-0 libegl1 libgl1 xvfb xauth >/dev/null 2>&1

cp "$image" /tmp/app.AppImage
chmod +x /tmp/app.AppImage
# 模擬其他架構時 binfmt 認不得 AppImage 的魔術位元組，複本先清掉（不影響內容）
dd if=/dev/zero of=/tmp/app.AppImage bs=1 seek=8 count=3 conv=notrunc 2>/dev/null
cd /tmp
./app.AppImage --appimage-extract >/dev/null
missing="$(ldd squashfs-root/usr/lib/securibit/securibit 2>&1 | grep 'not found' || true)"
if [[ -n "$missing" ]]; then
  echo "    缺少函式庫：" && echo "$missing"
  exit 1
fi
rm -rf squashfs-root

set +e
timeout 10 xvfb-run -a -s '-screen 0 1280x800x24' ./app.AppImage --appimage-extract-and-run >/tmp/run.log 2>&1
rc=$?
set -e
if [[ $rc -ne 124 ]]; then
  echo "    AppImage 提早結束（$rc）："
  tail -20 /tmp/run.log
  exit 1
fi
echo "    AppImage 啟動正常"

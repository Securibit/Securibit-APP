#!/usr/bin/env bash
#
# 把 release bundle 打包成 .deb（由 build.sh 呼叫；要在 Debian/Ubuntu 上跑，需要 dpkg-dev）。
#
#   tool/linux/package_deb.sh <bundle 資料夾> <版本，例如 0.3.0+3> <arm64|amd64> <輸出資料夾>
#
# 安裝後：
#   /opt/securibit/                 bundle（執行檔、lib、data）
#   /usr/bin/securibit              → /opt/securibit/securibit
#   /usr/share/applications/com.bityo.securibit.desktop
#   /usr/share/icons/hicolor/<大小>/apps/com.bityo.securibit.png
# Depends 由 dpkg-shlibdeps 依 bundle 實際連結的系統函式庫算出來（bundle 自帶的 libflutter 與外掛不算），
# 再加上執行時才載入的 libEGL、libGL；
# 登入狀態存在 Secret Service，所以 Recommends gnome-keyring。
# 輸出的檔案路徑印在 stdout，其他訊息印在 stderr。
# 環境變數 DISTRO_TAG（build.sh 設定，例如 debian-12）不是空的時候，檔名加上發行版：
#   securibit_<版本>_<DISTRO_TAG>_<arm64|amd64>.deb
set -euo pipefail

bundle="$1"
full_version="$2"
deb_arch="$3"
out="$4"
version="${full_version%%+*}"
here="$(cd "$(dirname "$0")" && pwd)"
packaging="$here/../../linux/packaging"
maintainer="${DEB_MAINTAINER:-夏特稀 <mmm25002500@users.noreply.github.com>}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"

echo "==> 打包 .deb（$deb_arch）" >&2
install -d "$root/opt" "$root/usr/bin" "$root/usr/share/applications" "$root/DEBIAN"
cp -a "$bundle" "$root/opt/securibit"
ln -s /opt/securibit/securibit "$root/usr/bin/securibit"
install -m 644 "$packaging/com.bityo.securibit.desktop" "$root/usr/share/applications/"
for size in 48 128 256 512; do
  install -D -m 644 "$packaging/icons/$size/com.bityo.securibit.png" \
    "$root/usr/share/icons/hicolor/${size}x${size}/apps/com.bityo.securibit.png"
done
# 權限一律是 root 擁有、目錄 755、一般檔案 644、執行檔與 .so 755
find "$root" -type d -exec chmod 755 {} +
find "$root/opt/securibit" -type f -exec chmod 644 {} +
chmod 755 "$root/opt/securibit/securibit"
find "$root/opt/securibit/lib" -type f -name '*.so*' -exec chmod 755 {} +

# 依實際連結的系統函式庫算出 Depends
mkdir -p "$tmp/shlibs/debian"
printf 'Source: securibit\n\nPackage: securibit\nArchitecture: any\n' > "$tmp/shlibs/debian/control"
mapfile -t elves < <(find "$root/opt/securibit" -type f \( -name securibit -o -name '*.so*' \))
depends="$(cd "$tmp/shlibs" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"$root/opt/securibit/lib" "${elves[@]}" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')"
if [[ -z "$depends" ]]; then
  echo "dpkg-shlibdeps 沒有算出相依套件" >&2
  exit 1
fi
# Flutter 引擎經 libepoxy 在執行時才載入 libEGL、libGL（dlopen，dpkg-shlibdeps 看不到），沒有的話一啟動就結束
depends="$depends, libegl1, libgl1"

installed_size="$(du -sk --exclude=DEBIAN "$root" | cut -f1)"
cat > "$root/DEBIAN/control" <<CONTROL
Package: securibit
Version: $full_version
Architecture: $deb_arch
Maintainer: $maintainer
Installed-Size: $installed_size
Depends: $depends
Recommends: gnome-keyring
Section: utils
Priority: optional
Homepage: https://2fa.bityo.tw
Description: Securibit two-factor authenticator
 Securibit 兩步驟驗證器的桌面版，和 Securibit 網站共用帳號、群組與加密群組。
 可以常駐在系統匣，點一下就複製驗證碼。
CONTROL

deb="$out/securibit_${version}_${DISTRO_TAG:+${DISTRO_TAG}_}${deb_arch}.deb"
mkdir -p "$out"
dpkg-deb --build --root-owner-group -Zxz "$root" "$deb" >&2
echo "    Depends: $depends" >&2
echo "$deb"

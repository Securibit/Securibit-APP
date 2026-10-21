#!/usr/bin/env bash
#
# 把 release bundle 打包成 AppImage（由 build.sh 呼叫；需要 appimagetool、patchelf，容器裡都裝好了）。
#
#   tool/linux/package_appimage.sh <bundle 資料夾> <版本，例如 0.3.0> <aarch64|x86_64> <輸出資料夾>
#
# 不帶 glibc、GTK、GLib 這些每個桌面都有的核心函式庫（帶了反而容易和系統的衝突），
# 只帶不一定有裝的：系統匣（ayatana appindicator 與它用的 dbusmenu、ido）與 libsecret（含它用的 libgcrypt、libgpg-error）。
# OpenGL（libEGL、libGL）是顯示卡驅動的一部分，也不帶。
# 帶進來的函式庫加上 RUNPATH=$ORIGIN 互相找得到，不用設定 LD_LIBRARY_PATH（不然會傳給 App 開的瀏覽器）。
# 輸出的檔案路徑印在 stdout，其他訊息印在 stderr。
set -euo pipefail

bundle="$1"
version="$2"
appimage_arch="$3"
out="$4"
here="$(cd "$(dirname "$0")" && pwd)"
packaging="$here/../../linux/packaging"

# 要帶進 AppImage 的函式庫（soname 開頭）
bundled=(
  libayatana-appindicator3.so
  libayatana-indicator3.so
  libayatana-ido3-0.4.so
  libdbusmenu-glib.so
  libdbusmenu-gtk3.so
  libsecret-1.so
  # libsecret 用的加密函式庫，精簡安裝的系統（例如 Debian 13）不一定有
  libgcrypt.so
  libgpg-error.so
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
appdir="$tmp/Securibit.AppDir"
app="$appdir/usr/lib/securibit"

echo "==> 打包 AppImage（$appimage_arch）" >&2
install -d "$appdir/usr/lib" "$appdir/usr/share/applications"
cp -a "$bundle" "$app"

# ldd 找出實際用到的路徑，複製進 lib/
while read -r name path; do
  for want in "${bundled[@]}"; do
    if [[ "$name" == "$want"* ]]; then
      cp -L "$path" "$app/lib/$name"
      patchelf --set-rpath '$ORIGIN' "$app/lib/$name"
      echo "    帶入 $name" >&2
    fi
  done
done < <(ldd "$app/securibit" | awk '$2 == "=>" && $3 ~ /^\// { print $1, $3 }')

# 主程式的 RUNPATH 不會套用到外掛的相依，外掛在 CMake 已經設成 $ORIGIN（見 linux/CMakeLists.txt）；
# 這裡再確認一次，flutter_secure_storage 外掛要的 libsecret 才找得到帶進來的那一份。libapp.so 是 Dart 編譯出來的，不要動
for lib in "$app"/lib/*.so; do
  [[ "$(basename "$lib")" == libapp.so ]] && continue
  [[ "$(patchelf --print-rpath "$lib")" == '$ORIGIN' ]] || patchelf --set-rpath '$ORIGIN' "$lib"
done

install -m 644 "$packaging/com.bityo.securibit.desktop" "$appdir/com.bityo.securibit.desktop"
install -m 644 "$packaging/com.bityo.securibit.desktop" "$appdir/usr/share/applications/"
install -m 644 "$packaging/icons/256/com.bityo.securibit.png" "$appdir/com.bityo.securibit.png"
ln -s com.bityo.securibit.png "$appdir/.DirIcon"
for size in 48 128 256 512; do
  install -D -m 644 "$packaging/icons/$size/com.bityo.securibit.png" \
    "$appdir/usr/share/icons/hicolor/${size}x${size}/apps/com.bityo.securibit.png"
done
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage 的進入點：直接執行 bundle 裡的程式（函式庫靠 RUNPATH 找，不設定 LD_LIBRARY_PATH）
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/securibit/securibit" "$@"
APPRUN
chmod 755 "$appdir/AppRun"

image="$out/Securibit-$version-$appimage_arch.AppImage"
mkdir -p "$out"
runtime=()
if [[ -n "${APPIMAGE_RUNTIME:-}" ]]; then runtime=(--runtime-file "$APPIMAGE_RUNTIME"); fi
ARCH="$appimage_arch" VERSION="$version" appimagetool --no-appstream "${runtime[@]}" "$appdir" "$image" >&2
echo "$image"

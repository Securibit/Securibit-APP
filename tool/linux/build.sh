#!/usr/bin/env bash
#
# 建置 Linux 版並打包（Makefile 的 linux、linux-docker、deb、appimage 會呼叫這支）。
# 在 Linux 主機上直接跑，或在 docker/linux.Dockerfile 的容器裡跑；建出來的架構就是目前機器的架構。
#
#   tool/linux/build.sh bundle     建置 release bundle，打包成 dist/Securibit-<版本>-linux-<arch>.tar.gz
#   tool/linux/build.sh deb        bundle ＋ dist/securibit_<版本>_<arm64|amd64>.deb
#   tool/linux/build.sh appimage   bundle ＋ dist/Securibit-<版本>-<aarch64|x86_64>.AppImage
#   tool/linux/build.sh all        以上全部
#
# 環境變數：
#   OUT_DIR             產出放這裡（預設 <專案>/dist）
#   WORK_DIR            有設定時先把原始碼同步到 $WORK_DIR/app 再建置（容器裡用：不動到主機的 .dart_tool、build，
#                       而且 $WORK_DIR 是 volume，第二次建置只重編有改的部分）
#   HOST_UID、HOST_GID  容器以 root 執行時，把產出的擁有者改回主機的使用者
set -euo pipefail

what="${1:-bundle}"
case "$what" in bundle|deb|appimage|all) ;; *) echo "用法：$0 <bundle|deb|appimage|all>" >&2; exit 2 ;; esac

src="$(cd "$(dirname "$0")/../.." && pwd)"
out="${OUT_DIR:-$src/dist}"

if [[ ! -f "$src/env.json" ]]; then
  echo "找不到 env.json：先 cp env.example.json env.json 並填入連線設定（見 README）" >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) arch=arm64; deb_arch=arm64; appimage_arch=aarch64 ;;
  x86_64|amd64) arch=x64; deb_arch=amd64; appimage_arch=x86_64 ;;
  *) echo "不支援的架構：$(uname -m)" >&2; exit 1 ;;
esac

# pubspec 的 version: 0.3.0+3 → 版本 0.3.0、建置編號 3
full_version="$(sed -n 's/^version: *//p' "$src/pubspec.yaml" | tr -d '[:space:]')"
version="${full_version%%+*}"

app="$src"
if [[ -n "${WORK_DIR:-}" ]]; then
  app="$WORK_DIR/app"
  mkdir -p "$app"
  echo "==> 同步原始碼到 $app"
  # 主機產生的檔案（含絕對路徑的 .dart_tool、各平台的 build）不要帶進來；容器自己的 build 留著重複使用
  rsync -a --delete \
    --exclude '/.git/' --exclude '/.dart_tool/' --exclude '/build/' --exclude '/dist/' \
    --exclude '/linux/flutter/ephemeral/' --exclude '/rust/target/' \
    --exclude '/android/' --exclude '/ios/' --exclude '/macos/' --exclude '/windows/' --exclude '/web/' \
    --exclude '.DS_Store' \
    "$src/" "$app/"
fi

cd "$app"
echo "==> flutter build linux（$arch）"
flutter --version | head -1
flutter pub get
flutter build linux --release \
  --obfuscate --split-debug-info="build/symbols/linux-$arch" \
  --dart-define-from-file=env.json

bundle="$app/build/linux/$arch/release/bundle"
mkdir -p "$out"
outputs=()

# 解開後是 securibit/ 資料夾，裡面直接執行 ./securibit
tarball="$out/Securibit-$version-linux-$arch.tar.gz"
echo "==> $tarball"
tar -C "$(dirname "$bundle")" --transform 's,^bundle,securibit,' -czf "$tarball" bundle
outputs+=("$tarball")

if [[ "$what" == deb || "$what" == all ]]; then
  outputs+=("$("$app/tool/linux/package_deb.sh" "$bundle" "$full_version" "$deb_arch" "$out")")
fi
if [[ "$what" == appimage || "$what" == all ]]; then
  outputs+=("$("$app/tool/linux/package_appimage.sh" "$bundle" "$version" "$appimage_arch" "$out")")
fi

if [[ -n "${HOST_UID:-}" ]]; then
  chown "$HOST_UID:${HOST_GID:-$HOST_UID}" "$out" "${outputs[@]}"
fi

echo
echo "完成："
for f in "${outputs[@]}"; do echo "  ${f#"$src"/}"; done

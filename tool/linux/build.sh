#!/usr/bin/env bash
#
# 建置 Linux 版並打包（Makefile 的 linux、deb、linux-all 會呼叫這支）。
# 在 Linux 主機上直接跑，或在 docker/linux.Dockerfile 的容器裡跑；建出來的架構就是目前機器的架構。
#
#   tool/linux/build.sh bundle     建置 release bundle，打包成 dist/Securibit-<版本>-linux-<arch>.tar.gz
#   tool/linux/build.sh deb        bundle ＋ dist/securibit_<版本>_<arm64|amd64>.deb
#   tool/linux/build.sh all        bundle ＋ .deb
#
# 檔名的發行版：在 Ubuntu 22.04 上建置（預設，相容性最廣）時檔名不加；其他發行版會加上 <ID>-<VERSION_ID>，
# 例如 Securibit-0.3.0-linux-debian-12-x64.tar.gz、securibit_0.3.0_debian-12_amd64.deb。
# 這次的產出檔名寫在 $OUT_DIR/.last-build（一行一個），make 的 REMOTE 建置靠它把產出拉回來。
#
# 環境變數：
#   OUT_DIR             產出放這裡（預設 <專案>/dist）
#   LINUX_DISTRO        檔名用的發行版，例如 debian-12（Docker 建置時由 Makefile 傳入 DISTRO；
#                       沒設定時讀 /etc/os-release，也就是建置這台機器本身的系統）
#   WORK_DIR            有設定時先把原始碼同步到 $WORK_DIR/app 再建置（容器裡用：不動到主機的 .dart_tool、build，
#                       而且 $WORK_DIR 是 volume，第二次建置只重編有改的部分）
#   HOST_UID、HOST_GID  容器以 root 執行時，把產出的擁有者改回主機的使用者
set -euo pipefail

what="${1:-bundle}"
case "$what" in bundle|deb|all) ;; *) echo "用法：$0 <bundle|deb|all>" >&2; exit 2 ;; esac

src="$(cd "$(dirname "$0")/../.." && pwd)"
out="${OUT_DIR:-$src/dist}"

if [[ ! -f "$src/env.json" ]]; then
  echo "找不到 env.json：先 cp env.example.json env.json 並填入連線設定（見 README）" >&2
  exit 1
fi

# 直接在主機上建置時，先確認工具都在（容器裡都裝好了）
missing=()
command -v flutter >/dev/null || missing+=("flutter（Flutter 3.35.3）")
command -v cargo >/dev/null && command -v rustup >/dev/null || missing+=("cargo／rustup（用 https://rustup.rs 安裝 Rust）")
if [[ "$what" != bundle ]]; then
  command -v dpkg-shlibdeps >/dev/null || missing+=("dpkg-shlibdeps（apt 套件 dpkg-dev）")
fi
if (( ${#missing[@]} )); then
  echo "直接建置還缺：" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "執行 make linux-deps 安裝系統套件並查看 Flutter、Rust 的安裝方式，或改用 Docker：make $what LINUX_DOCKER=1" >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) arch=arm64; deb_arch=arm64 ;;
  x86_64|amd64) arch=x64; deb_arch=amd64 ;;
  *) echo "不支援的架構：$(uname -m)" >&2; exit 1 ;;
esac

# 檔名的發行版標記（ubuntu-22.04 不加）
distro="${LINUX_DISTRO:-$(. /etc/os-release 2>/dev/null && echo "$ID${VERSION_ID:+-$VERSION_ID}")}"
if [[ "$distro" == ubuntu-22.04 ]]; then DISTRO_TAG=""; else DISTRO_TAG="$distro"; fi
export DISTRO_TAG

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
tarball="$out/Securibit-$version-linux-${DISTRO_TAG:+$DISTRO_TAG-}$arch.tar.gz"
echo "==> $tarball"
tar -C "$(dirname "$bundle")" --transform 's,^bundle,securibit,' -czf "$tarball" bundle
outputs+=("$tarball")

if [[ "$what" == deb || "$what" == all ]]; then
  outputs+=("$("$app/tool/linux/package_deb.sh" "$bundle" "$full_version" "$deb_arch" "$out")")
fi

# 這次的產出清單（REMOTE 建置用）
manifest="$out/.last-build"
for f in "${outputs[@]}"; do basename "$f"; done > "$manifest"

if [[ -n "${HOST_UID:-}" ]]; then
  chown "$HOST_UID:${HOST_GID:-$HOST_UID}" "$out" "$manifest" "${outputs[@]}"
fi

echo
echo "完成："
for f in "${outputs[@]}"; do echo "  ${f#"$src"/}"; done

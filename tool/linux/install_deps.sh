#!/usr/bin/env bash
#
# 主機直接建置 Linux 版前的準備（make linux-deps 用；GitHub Actions 也用它安裝系統套件）。
#   1. 用 apt 安裝建置需要的系統套件（Debian / Ubuntu；不是 root 時用 sudo）
#   2. 檢查 Flutter 與 Rust（cargo、rustup）有沒有裝。沒有的話只印出安裝方式，不會自動安裝
#
# 套件和 docker/linux.Dockerfile 的 build stage 相同，改的時候兩邊一起改。
#
# 環境變數：FLUTTER（flutter 的路徑，預設 flutter）、FLUTTER_WANT（專案要的 Flutter 版本，預設 3.35.3）
set -euo pipefail

flutter="${FLUTTER:-flutter}"
want="${FLUTTER_WANT:-3.35.3}"

packages=(
  # Flutter 本身與下載工具
  ca-certificates curl git unzip xz-utils zip file rsync
  # Flutter Linux 桌面的編譯工具
  clang cmake ninja-build pkg-config make
  # App 用到的函式庫：GTK 3、libsecret（登入狀態）、jsoncpp、ayatana appindicator（系統匣）
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev
  # 打包 .deb（dpkg-shlibdeps、dpkg-deb）
  dpkg-dev
)

if ! command -v apt-get >/dev/null; then
  echo "這支只支援用 apt 的發行版（Debian、Ubuntu 與其衍生版）。其他發行版請自行安裝對應的套件：" >&2
  printf '  %s\n' "${packages[@]}" >&2
  echo "或改用 Docker 建置（make deb LINUX_DOCKER=1）。" >&2
  exit 1
fi

sudo=()
if [[ $(id -u) -ne 0 ]]; then
  if ! command -v sudo >/dev/null; then
    echo "需要 root 權限安裝套件，但找不到 sudo。請用 root 執行，或先安裝 sudo。" >&2
    exit 1
  fi
  sudo=(sudo)
fi

echo "==> 安裝系統套件（apt）"
echo "    ${packages[*]}"
export DEBIAN_FRONTEND=noninteractive
"${sudo[@]}" apt-get update
"${sudo[@]}" apt-get install -y --no-install-recommends "${packages[@]}"

echo
echo "==> 檢查 Flutter 與 Rust"
todo=0

if command -v "$flutter" >/dev/null; then
  have="$("$flutter" --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')"
  if [[ "$have" == "$want" ]]; then
    echo "    Flutter $have"
  else
    echo "    Flutter ${have:-（讀不到版本）}：專案使用 $want，版本不同可能建置失敗或行為不同。"
    echo "    可以另外下載 $want：git clone --depth 1 --branch $want https://github.com/flutter/flutter.git ~/flutter-$want"
    echo "    再用 make deb FLUTTER=~/flutter-$want/bin/flutter 建置"
  fi
else
  todo=1
  cat <<EOF
    找不到 flutter。安裝 Flutter $want（不用 sudo，裝在家目錄）：

      git clone --depth 1 --branch $want https://github.com/flutter/flutter.git ~/flutter
      echo 'export PATH="\$HOME/flutter/bin:\$PATH"' >> ~/.profile
      source ~/.profile
      flutter --version      # 第一次執行會下載 Dart SDK

EOF
fi

if command -v cargo >/dev/null && command -v rustup >/dev/null; then
  echo "    $(cargo --version)，$(rustup --version 2>/dev/null | head -1)"
else
  todo=1
  if command -v cargo >/dev/null; then
    echo "    有 cargo 但沒有 rustup：Rust 核心的建置工具（cargokit）要用 rustup 管理工具鏈，"
    echo "    請移除發行版的 cargo／rustc 套件，改用 rustup 安裝："
  else
    echo "    找不到 cargo。用 rustup 安裝 Rust（不用 sudo，裝在家目錄）："
  fi
  cat <<'EOF'

      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      source "$HOME/.cargo/env"

EOF
fi

echo
if (( todo )); then
  echo "系統套件已安裝；裝好上面缺的 Flutter／Rust 後，執行 make deb（或 make linux-all）。"
else
  echo "都準備好了，執行 make deb（或 make linux-all）。"
fi

# syntax=docker/dockerfile:1
#
# Securibit 的 Linux 建置環境（make linux-docker / deb / linux-all 用）。
# 以 Ubuntu 22.04 為底（glibc 2.35），建出來的 bundle 與 .deb 在 22.04 以後的發行版都能跑。
# 原始碼不放進映像檔：執行時把專案掛在 /src，建置目錄、pub 快取與 cargo registry 放在 volume 重複使用。
#
#   docker build --platform linux/arm64 --build-arg FLUTTER_VERSION=3.35.3 -f docker/linux.Dockerfile -t securibit-linux:3.35.3-arm64 docker
#
# 兩個 stage：
#   build  建置與打包需要的工具
#   smoke  另外加上 Xvfb、視窗管理員、dbus、gnome-keyring 與截圖工具，在容器裡實際開 App 截圖（make linux-smoke）

FROM ubuntu:22.04 AS build

ARG FLUTTER_VERSION=3.35.3

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Flutter Linux 桌面需要的編譯工具與函式庫，加上系統匣（ayatana appindicator）、打包（dpkg-dev）
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file rsync \
      clang cmake ninja-build pkg-config make \
      libgtk-3-dev libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev \
      dpkg-dev imagemagick desktop-file-utils \
    && rm -rf /var/lib/apt/lists/*

# Flutter（版本與主機相同，由 Makefile 讀 `flutter --version` 傳入）
ENV FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/opt/pub-cache \
    PATH=/opt/flutter/bin:/opt/cargo/bin:$PATH
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter \
    && git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --no-cli-animations \
       --enable-linux-desktop --no-enable-android --no-enable-ios --no-enable-web --no-enable-macos-desktop \
    && dart --disable-analytics \
    && flutter precache --linux --no-android --no-ios --no-web \
    && flutter --version

# Rust（Rust 核心經 flutter_rust_bridge / cargokit 編譯時要用）；registry 在執行時掛 volume 快取
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable \
    && rustup --version && cargo --version

WORKDIR /src

FROM build AS smoke
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb xauth x11-utils x11-apps openbox wmctrl xdotool dbus dbus-x11 gnome-keyring libsecret-tools \
      python3 python3-gi gir1.2-glib-2.0 fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

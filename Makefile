# Securibit APP 的建置入口。`make` 或 `make help` 列出所有目標。
#
# 所有產出都放在 dist/，檔名帶 pubspec.yaml 的版本：
#   Securibit-<版本>-macos.zip               macOS App（未簽章公證，見 README）
#   Securibit-<版本>-ios-unsigned.ipa        iOS（沒有簽章，要用 Xcode 或其他工具簽過才能安裝）
#   securibit-<版本>-<abi>.apk                Android，每種處理器一個（arm64-v8a、armeabi-v7a、x86_64）
#   securibit-<版本>.aab                      Android App Bundle（上架 Google Play）
#   Securibit-<版本>-linux-<arm64|x64>.tar.gz Linux release bundle，解開後執行 securibit/securibit
#   securibit_<版本>_<arm64|amd64>.deb        Debian / Ubuntu 套件
#   Securibit-<版本>-<aarch64|x86_64>.AppImage
#
# Linux 版要在 Linux 上建置：主機是 Linux 時直接建置，其他主機（例如 macOS）用 Docker（docker/linux.Dockerfile）。
# Docker 映像檔會重複使用，pub 快取、cargo registry 與建置目錄放在 volume（securibit-<arch>-*），第二次建置很快。

SHELL := /bin/bash
.DEFAULT_GOAL := help

FLUTTER ?= flutter
DOCKER ?= docker
DIST := dist
DEFINES := --dart-define-from-file=env.json

# 版本：pubspec.yaml 的 version: 0.3.0+3 → 0.3.0
VERSION_FULL := $(shell sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]')
VERSION := $(firstword $(subst +, ,$(VERSION_FULL)))

HOST_OS := $(shell uname -s)
HOST_MACHINE := $(shell uname -m)
ifneq ($(filter arm64 aarch64,$(HOST_MACHINE)),)
  HOST_ARCH := arm64
else
  HOST_ARCH := x64
endif

# Linux 的目標架構：arm64 或 x64（預設和主機相同；Apple Silicon 上建 x64 會透過模擬執行，比較慢）
ARCH ?= $(HOST_ARCH)
ifeq ($(filter arm64 x64,$(ARCH)),)
  $(error ARCH 只能是 arm64 或 x64)
endif
DOCKER_PLATFORM := $(if $(filter x64,$(ARCH)),linux/amd64,linux/arm64)
DEB_ARCH := $(if $(filter x64,$(ARCH)),amd64,arm64)
APPIMAGE_ARCH := $(if $(filter x64,$(ARCH)),x86_64,aarch64)

# Linux 主機上預設直接建置；LINUX_DOCKER=1 強制用 Docker。主機架構不同時一定用 Docker
ifeq ($(HOST_OS),Linux)
  LINUX_DOCKER ?= $(if $(filter $(ARCH),$(HOST_ARCH)),0,1)
else
  LINUX_DOCKER := 1
endif

# 容器裡的 Flutter 版本和主機相同（讀 `flutter --version`，讀不到時用目前固定的版本）。
# 用到時才讀、只讀一次（make help 不用等 flutter）
ifeq ($(origin FLUTTER_VERSION),undefined)
FLUTTER_VERSION = $(eval FLUTTER_VERSION := $(or $(shell $(FLUTTER) --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'),3.35.3))$(FLUTTER_VERSION)
endif
IMAGE = securibit-linux:$(FLUTTER_VERSION)-$(ARCH)
SMOKE_IMAGE = $(IMAGE)-smoke

DOCKER_VOLUMES := \
  -v "$(CURDIR)":/src \
  -v securibit-$(ARCH)-work:/work \
  -v securibit-$(ARCH)-pub-cache:/opt/pub-cache \
  -v securibit-$(ARCH)-cargo-registry:/opt/cargo/registry \
  -v securibit-$(ARCH)-cargo-git:/opt/cargo/git
DOCKER_RUN := $(DOCKER) run --rm --platform $(DOCKER_PLATFORM) $(DOCKER_VOLUMES) \
  -e WORK_DIR=/work -e OUT_DIR=/src/$(DIST) -e HOST_UID=$(shell id -u) -e HOST_GID=$(shell id -g)

.PHONY: help deps analyze test clean env-check rust-lib rust-test codegen codegen-tool \
  macos ios apk aab \
  linux linux-docker deb appimage linux-all docker-image docker-smoke-image linux-smoke deb-check appimage-check \
  dist docker-clean

help: ## 列出所有目標
	@echo "Securibit APP $(VERSION_FULL)（產出放在 $(DIST)/）"
	@echo
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "變數："
	@echo "  ARCH=arm64|x64     Linux 的目標架構（預設 $(HOST_ARCH)，和主機相同）"
	@echo "  LINUX_DOCKER=1     在 Linux 主機上也用 Docker 建置"
	@echo "  FLUTTER=...        flutter 的路徑（預設 flutter）"

# ─── 基本 ──────────────────────────────────────────────

deps: ## 安裝 Dart 套件（flutter pub get）
	$(FLUTTER) pub get

analyze: ## 靜態檢查（flutter analyze）
	$(FLUTTER) analyze

test: rust-lib rust-test ## 執行測試（Rust 核心的 cargo test，再 flutter test）
	$(FLUTTER) test

# ─── Rust 安全核心 ─────────────────────────────────────

rust-lib: ## 建置這台主機用的 Rust 核心函式庫（flutter test 會載入它）
	cd rust && cargo build --release -p securibit_api

rust-test: ## Rust 核心的單元測試（RFC 6238、網站的加密向量）
	cd rust && cargo test --workspace --release

codegen: ## 改了 rust/api 之後重新產生 Dart binding（lib/src/rust/）
	flutter_rust_bridge_codegen generate

codegen-tool: ## 安裝固定版本的 flutter_rust_bridge_codegen
	cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked

clean: ## 清掉建置結果與 dist/（Docker 的 volume 用 make docker-clean）
	$(FLUTTER) clean
	rm -rf $(DIST)

# 所有建置目標都先檢查 env.json，並建立 dist/
env-check:
	@if [[ ! -f env.json ]]; then \
	  echo "找不到 env.json：先 cp env.example.json env.json 並填入連線設定（見 README）" >&2; exit 1; \
	fi
	@mkdir -p $(DIST)

# ─── 各平台 ────────────────────────────────────────────

macos: env-check ## macOS release，壓成 Securibit-<版本>-macos.zip
	$(FLUTTER) build macos --release $(DEFINES)
	rm -f $(DIST)/Securibit-$(VERSION)-macos.zip
	ditto -c -k --sequesterRsrc --keepParent build/macos/Build/Products/Release/securibit.app $(DIST)/Securibit-$(VERSION)-macos.zip
	@echo "→ $(DIST)/Securibit-$(VERSION)-macos.zip"

ios: env-check ## iOS release（不簽章），打包成 Securibit-<版本>-ios-unsigned.ipa
	$(FLUTTER) build ios --release --no-codesign $(DEFINES)
	rm -rf build/ios/ipa-unsigned && mkdir -p build/ios/ipa-unsigned/Payload
	cp -R build/ios/iphoneos/Runner.app build/ios/ipa-unsigned/Payload/
	cd build/ios/ipa-unsigned && rm -f ../../../$(DIST)/Securibit-$(VERSION)-ios-unsigned.ipa && zip -qry ../../../$(DIST)/Securibit-$(VERSION)-ios-unsigned.ipa Payload
	@echo "→ $(DIST)/Securibit-$(VERSION)-ios-unsigned.ipa"

apk: env-check ## Android APK：每種處理器一個、混淆並去掉除錯符號（符號在 build/symbols）
	$(FLUTTER) build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols $(DEFINES)
	@for abi in arm64-v8a armeabi-v7a x86_64; do \
	  src=build/app/outputs/flutter-apk/app-$$abi-release.apk; \
	  if [[ -f $$src ]]; then cp $$src $(DIST)/securibit-$(VERSION)-$$abi.apk; echo "→ $(DIST)/securibit-$(VERSION)-$$abi.apk"; fi; \
	done

aab: env-check ## Android App Bundle（上架 Google Play）
	$(FLUTTER) build appbundle --release --obfuscate --split-debug-info=build/symbols $(DEFINES)
	cp build/app/outputs/bundle/release/app-release.aab $(DIST)/securibit-$(VERSION).aab
	@echo "→ $(DIST)/securibit-$(VERSION).aab"

# ─── Linux ─────────────────────────────────────────────

ifeq ($(LINUX_DOCKER),1)
linux: linux-docker ## Linux release bundle（Linux 主機直接建置，其他主機用 Docker）→ .tar.gz
deb: env-check docker-image ## Linux .deb（ARCH=arm64|x64）
	$(DOCKER_RUN) $(IMAGE) tool/linux/build.sh deb
appimage: env-check docker-image ## Linux AppImage（ARCH=arm64|x64）
	$(DOCKER_RUN) $(IMAGE) tool/linux/build.sh appimage
linux-all: env-check docker-image ## Linux 的 .tar.gz、.deb、AppImage 一次建好
	$(DOCKER_RUN) $(IMAGE) tool/linux/build.sh all
else
linux: env-check
	tool/linux/build.sh bundle
deb: env-check
	tool/linux/build.sh deb
appimage: env-check
	tool/linux/build.sh appimage
linux-all: env-check
	tool/linux/build.sh all
endif

linux-docker: env-check docker-image ## 在 Docker 裡建置 Linux release bundle（ARCH=arm64|x64）
	$(DOCKER_RUN) $(IMAGE) tool/linux/build.sh bundle

docker-image: ## 建立（或更新）Linux 建置用的 Docker 映像檔
	$(DOCKER) build --platform $(DOCKER_PLATFORM) --target build \
	  --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  -t $(IMAGE) -f docker/linux.Dockerfile docker

docker-smoke-image:
	$(DOCKER) build --platform $(DOCKER_PLATFORM) --target smoke \
	  --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  -t $(SMOKE_IMAGE) -f docker/linux.Dockerfile docker

linux-smoke: docker-smoke-image ## 在容器的 Xvfb 裡實際開 App、測試系統匣並截圖（先 make linux）→ build/linux-smoke/
	@test -f $(DIST)/Securibit-$(VERSION)-linux-$(ARCH).tar.gz || { echo "先執行 make linux ARCH=$(ARCH)" >&2; exit 1; }
	$(DOCKER) run --rm --platform $(DOCKER_PLATFORM) -v "$(CURDIR)":/src \
	  -e BUNDLE=/src/$(DIST)/Securibit-$(VERSION)-linux-$(ARCH).tar.gz -e SHOTS=/src/build/linux-smoke/$(ARCH) \
	  -e HOST_UID=$(shell id -u) -e HOST_GID=$(shell id -g) \
	  $(SMOKE_IMAGE) tool/linux/smoke.sh

deb-check: ## 在乾淨的 Ubuntu 22.04／24.04、Debian 12／13 容器裡安裝 .deb，確認相依套件與程式能啟動
	@test -f $(DIST)/securibit_$(VERSION)_$(DEB_ARCH).deb || { echo "先執行 make deb ARCH=$(ARCH)" >&2; exit 1; }
	@for base in ubuntu:22.04 ubuntu:24.04 debian:12 debian:13; do \
	  echo "==> $$base"; \
	  $(DOCKER) run --rm --platform $(DOCKER_PLATFORM) -v "$(CURDIR)":/src:ro $$base \
	    bash /src/tool/linux/deb_check.sh /src/$(DIST)/securibit_$(VERSION)_$(DEB_ARCH).deb || exit 1; \
	done

appimage-check: ## 在只裝了 GTK 的乾淨 Ubuntu 22.04、Debian 13 容器裡執行 AppImage，確認帶的函式庫夠用
	@test -f $(DIST)/Securibit-$(VERSION)-$(APPIMAGE_ARCH).AppImage || { echo "先執行 make appimage ARCH=$(ARCH)" >&2; exit 1; }
	@for base in ubuntu:22.04 debian:13; do \
	  echo "==> $$base"; \
	  $(DOCKER) run --rm --platform $(DOCKER_PLATFORM) -v "$(CURDIR)":/src:ro $$base \
	    bash /src/tool/linux/appimage_check.sh /src/$(DIST)/Securibit-$(VERSION)-$(APPIMAGE_ARCH).AppImage || exit 1; \
	done

docker-clean: ## 刪掉 Linux 建置用的 Docker volume（下次會重新下載套件、完整重建）
	-$(DOCKER) volume rm securibit-$(ARCH)-work securibit-$(ARCH)-pub-cache securibit-$(ARCH)-cargo-registry securibit-$(ARCH)-cargo-git

# ─── 發行 ──────────────────────────────────────────────

# macOS 主機：macOS、iOS、Android（有 Android SDK 時）、Linux（Docker 有在跑時）
# Linux 主機：Android（有 Android SDK 時）、Linux
HAS_ANDROID := $(if $(or $(ANDROID_HOME),$(ANDROID_SDK_ROOT),$(wildcard $(HOME)/Library/Android/sdk),$(wildcard $(HOME)/Android/Sdk)),1,)
HAS_DOCKER = $(shell $(DOCKER) info >/dev/null 2>&1 && echo 1)
DIST_TARGETS = $(if $(filter Darwin,$(HOST_OS)),macos ios) \
  $(if $(HAS_ANDROID),apk aab) \
  $(if $(or $(filter 0,$(LINUX_DOCKER)),$(HAS_DOCKER)),linux-all)

dist: env-check ## 建置這台主機能建的所有平台
	@echo "這台主機會建置：$(strip $(DIST_TARGETS))"
	@$(MAKE) --no-print-directory $(DIST_TARGETS)
	@echo
	@ls -lh $(DIST)

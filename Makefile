# Securibit APP 的建置入口。`make` 或 `make help` 列出所有目標。
#
# 所有產出都放在 dist/，檔名帶 pubspec.yaml 的版本：
#   Securibit-<版本>-macos.dmg               macOS 安裝檔：拖曳 securibit.app 到「應用程式」（未簽章公證，見 README）
#   Securibit-<版本>-macos.zip               macOS App（同上，壓縮檔）
#   Securibit-<版本>-ios-unsigned.ipa        iOS（沒有簽章，要用 Xcode 或其他工具簽過才能安裝）
#   securibit-<版本>-<abi>.apk                Android，每種處理器一個（arm64-v8a、armeabi-v7a、x86_64）
#   securibit-<版本>.aab                      Android App Bundle（上架 Google Play）
#   Securibit-<版本>-linux-<arm64|x64>.tar.gz Linux release bundle，解開後執行 securibit/securibit
#   securibit_<版本>_<arm64|amd64>.deb        Debian / Ubuntu 套件
#   （Linux 在 Ubuntu 22.04 以外的系統建置時，檔名多一段發行版，例如
#     Securibit-<版本>-linux-debian-12-x64.tar.gz、securibit_<版本>_debian-12_amd64.deb）
#
# Linux 版要在 Linux 上建置，make linux／deb／linux-all 會自動選建置方式：
#   - REMOTE=user@host：把原始碼 rsync 到另一台 Linux，在那裡跑同一個目標，再把產出拉回 dist/
#   - 不是 Linux 的主機（例如 macOS）：用 Docker（docker/linux.Dockerfile）
#   - Linux 主機：有 flutter、cargo、rustup 就直接建置；沒有但 Docker 能用就改用 Docker；都沒有就說明要裝什麼。
#     LINUX_DOCKER=0／1 可以強制直接建置／用 Docker；有指定 DISTRO 或 ARCH 和主機不同時也用 Docker
# Docker 建置的底層發行版用 DISTRO 選（ubuntu-22.04、ubuntu-24.04、debian-12、debian-13，預設 ubuntu-22.04，
# 相容性最廣）。映像檔 securibit-linux:<Flutter 版本>-<DISTRO>-<arch> 會重複使用，pub 快取、cargo registry
# 與建置目錄放在 volume（securibit-<DISTRO>-<arch>-*），第二次建置很快。
# 也可以不用自己的電腦，改用 GitHub Actions 建置（.github/workflows/linux.yml）。
# REMOTE 等個人設定可以寫在 local.mk（不會提交，範例見 local.mk.example）。

SHELL := /bin/bash
.DEFAULT_GOAL := help

# 個人設定（REMOTE、REMOTE_SSH_OPTS、DISTRO…），要在下面判斷「有沒有明確指定」之前載入
-include local.mk

# 變數是不是使用者明確指定的（命令列、環境變數或 local.mk）
explicit = $(filter command line environment file override,$(origin $(1)))
# REMOTE 建置時，把明確指定的變數原樣傳給遠端（沒指定的由遠端自己決定，例如 ARCH 用遠端的架構）
REMOTE_PASS := $(strip $(foreach v,ARCH DISTRO LINUX_DOCKER FLUTTER_VERSION,$(if $(call explicit,$(v)),$(v)=$($(v)))))
DISTRO_EXPLICIT := $(call explicit,DISTRO)
LINUX_DOCKER_EXPLICIT := $(call explicit,LINUX_DOCKER)

FLUTTER ?= flutter
DOCKER ?= docker
DIST := dist
DEFINES := --dart-define-from-file=env.json
# 專案使用的 Flutter 版本（GitHub Actions、Docker 映像檔讀不到主機版本時都用它）
FLUTTER_PINNED := 3.35.3

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

# Docker 建置用的發行版
DISTROS := ubuntu-22.04 ubuntu-24.04 debian-12 debian-13
DISTRO ?= ubuntu-22.04
ifneq ($(words $(DISTRO)),1)
  $(error DISTRO 只能是 $(DISTROS) 其中之一)
endif
ifeq ($(filter $(DISTROS),$(DISTRO)),)
  $(error DISTRO 只能是 $(DISTROS) 其中之一)
endif
ifneq ($(filter-out 0 1,$(LINUX_DOCKER)),)
  $(error LINUX_DOCKER 只能是 0 或 1)
endif

# 在另一台 Linux 上建置
REMOTE ?=
REMOTE_DIR ?= ~/securibit-build
REMOTE_SSH_OPTS ?=

# Linux 的建置方式：remote、docker、host（直接在這台主機建置）、none（無法建置）
ifneq ($(strip $(REMOTE)),)
  LINUX_BUILD := remote
else ifneq ($(HOST_OS),Linux)
  LINUX_BUILD := docker
else ifneq ($(LINUX_DOCKER_EXPLICIT),)
  LINUX_BUILD := $(if $(filter 1,$(LINUX_DOCKER)),docker,host)
else ifneq ($(ARCH),$(HOST_ARCH))
  LINUX_BUILD := docker
else ifneq ($(DISTRO_EXPLICIT),)
  LINUX_BUILD := docker
else ifeq ($(shell command -v $(FLUTTER) >/dev/null && command -v cargo >/dev/null && command -v rustup >/dev/null && echo 1),1)
  LINUX_BUILD := host
else ifeq ($(shell $(DOCKER) info >/dev/null 2>&1 && echo 1),1)
  LINUX_BUILD := docker
else
  LINUX_BUILD := none
endif
ifeq ($(LINUX_BUILD),host)
  ifneq ($(DISTRO_EXPLICIT),)
    $(warning LINUX_DOCKER=0 直接建置時用主機本身的系統，DISTRO=$(DISTRO) 不會用到)
  endif
endif

# 產出檔名的發行版：Docker 建置是 DISTRO，主機直接建置是主機本身的系統（/etc/os-release 的 ID-VERSION_ID）。
# ubuntu-22.04 不加在檔名裡（相容性最廣的那份），其他的加，例如 securibit_0.3.0_debian-12_amd64.deb。
# tool/linux/build.sh 用同樣的規則命名
ifeq ($(HOST_OS),Linux)
  HOST_DISTRO := $(shell . /etc/os-release 2>/dev/null && echo "$$ID$${VERSION_ID:+-$$VERSION_ID}")
endif
ART_DISTRO := $(if $(filter host,$(LINUX_BUILD)),$(HOST_DISTRO),$(DISTRO))
ART_TAG := $(if $(filter ubuntu-22.04,$(ART_DISTRO)),,$(ART_DISTRO))
TARBALL := $(DIST)/Securibit-$(VERSION)-linux-$(if $(ART_TAG),$(ART_TAG)-)$(ARCH).tar.gz
DEB := $(DIST)/securibit_$(VERSION)_$(if $(ART_TAG),$(ART_TAG)_)$(DEB_ARCH).deb

# 容器裡的 Flutter 版本和主機相同（讀 `flutter --version`，讀不到時用 FLUTTER_PINNED）。
# 用到時才讀、只讀一次（make help 不用等 flutter）
ifeq ($(origin FLUTTER_VERSION),undefined)
FLUTTER_VERSION = $(eval FLUTTER_VERSION := $(or $(shell $(FLUTTER) --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'),$(FLUTTER_PINNED)))$(FLUTTER_VERSION)
endif
# ubuntu-22.04 → ubuntu:22.04；不同發行版的映像檔與 volume 分開，不互相污染
BASE_IMAGE := $(subst -,:,$(ART_DISTRO))
IMAGE = securibit-linux:$(FLUTTER_VERSION)-$(ART_DISTRO)-$(ARCH)
SMOKE_IMAGE = $(IMAGE)-smoke
VOLUME_PREFIX := securibit-$(ART_DISTRO)-$(ARCH)

DOCKER_VOLUMES := \
  -v "$(CURDIR)":/src \
  -v $(VOLUME_PREFIX)-work:/work \
  -v $(VOLUME_PREFIX)-pub-cache:/opt/pub-cache \
  -v $(VOLUME_PREFIX)-cargo-registry:/opt/cargo/registry \
  -v $(VOLUME_PREFIX)-cargo-git:/opt/cargo/git
DOCKER_RUN := $(DOCKER) run --rm --platform $(DOCKER_PLATFORM) $(DOCKER_VOLUMES) \
  -e WORK_DIR=/work -e OUT_DIR=/src/$(DIST) -e LINUX_DISTRO=$(ART_DISTRO) \
  -e HOST_UID=$(shell id -u) -e HOST_GID=$(shell id -g)

LINUX_BUILD_DESC := $(if $(filter remote,$(LINUX_BUILD)),在 $(REMOTE) 上建置（$(REMOTE_DIR)）,$(if $(filter docker,$(LINUX_BUILD)),Docker（$(DISTRO)，$(ARCH)）,$(if $(filter host,$(LINUX_BUILD)),直接在這台主機建置（$(HOST_DISTRO)，$(ARCH)）,無法建置：沒有 flutter／cargo／rustup，Docker 也不能用（make deb 會說明要裝什麼）)))

.PHONY: help deps analyze test clean env-check rust-lib rust-test codegen codegen-tool \
  macos ios apk aab \
  linux deb linux-all linux-deps docker-image docker-smoke-image linux-smoke deb-check \
  dist docker-clean

help: ## 列出所有目標
	@echo "Securibit APP $(VERSION_FULL)（產出放在 $(DIST)/）"
	@echo
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "Linux 建置（目前會用：$(LINUX_BUILD_DESC)）："
	@echo "  ARCH=arm64|x64        目標架構（預設 $(HOST_ARCH)，和主機相同；REMOTE 時預設是遠端主機的架構）"
	@echo "  DISTRO=...            Docker 建置用的發行版：ubuntu-22.04（預設，相容性最廣）、ubuntu-24.04、debian-12、debian-13"
	@echo "  LINUX_DOCKER=0|1      Linux 主機上強制直接建置／用 Docker（預設自動：有 flutter、cargo、rustup 就直接建置，否則用 Docker）"
	@echo "  REMOTE=user@host      在另一台 Linux 上建置，完成後把產出拉回 $(DIST)/"
	@echo "  REMOTE_DIR=...        遠端的建置資料夾（預設 ~/securibit-build）"
	@echo "  REMOTE_SSH_OPTS=...   ssh 的額外參數，例如 '-i ~/.ssh/金鑰'"
	@echo "  FLUTTER=...           flutter 的路徑（預設 flutter）"
	@echo "  REMOTE 等設定可以寫在 local.mk（見 local.mk.example）"

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

macos: env-check ## macOS release：Securibit-<版本>-macos.dmg（拖曳安裝）與 .zip
	$(FLUTTER) build macos --release $(DEFINES)
	rm -f $(DIST)/Securibit-$(VERSION)-macos.zip
	ditto -c -k --sequesterRsrc --keepParent build/macos/Build/Products/Release/securibit.app $(DIST)/Securibit-$(VERSION)-macos.zip
	@echo "→ $(DIST)/Securibit-$(VERSION)-macos.zip"
	@# 安裝檔：securibit.app 加上指向 /Applications 的「應用程式」捷徑，用系統內建的 hdiutil 做成壓縮的映像檔
	rm -rf build/macos/dmg && mkdir -p build/macos/dmg
	ditto build/macos/Build/Products/Release/securibit.app build/macos/dmg/securibit.app
	ln -s /Applications build/macos/dmg/應用程式
	hdiutil create -volname "Securibit $(VERSION)" -srcfolder build/macos/dmg -fs HFS+ -format UDZO -ov $(DIST)/Securibit-$(VERSION)-macos.dmg
	rm -rf build/macos/dmg
	@echo "→ $(DIST)/Securibit-$(VERSION)-macos.dmg"

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

# REMOTE：rsync 原始碼過去（不帶各平台的建置結果、其他平台的資料夾與 local.mk），在遠端跑同一個目標，
# 再依遠端 dist/.last-build（build.sh 寫的這次產出清單）把產出拉回來。
# REMOTE_DIR 開頭的 ~/ 去掉，變成相對於遠端家目錄的路徑（ssh、rsync 都從家目錄開始）
REMOTE_PATH := $(patsubst ~/%,%,$(REMOTE_DIR))
REMOTE_SSH_E := ssh $(subst ~/,$(HOME)/,$(REMOTE_SSH_OPTS))
REMOTE_SSH := $(REMOTE_SSH_E) $(REMOTE)
RSYNC_EXCLUDES := --exclude=/.git/ --exclude=/build/ --exclude=/dist/ --exclude=/.dart_tool/ \
  --exclude=/rust/target/ --exclude=/android/ --exclude=/ios/ --exclude=/macos/ --exclude=/windows/ \
  --exclude=/web/ --exclude=/linux/flutter/ephemeral/ --exclude=/local.mk --exclude=.DS_Store

define remote_sync
	@echo "==> 同步原始碼到 $(REMOTE):$(REMOTE_DIR)"
	@$(REMOTE_SSH) 'mkdir -p $(REMOTE_PATH)'
	rsync -az --delete -e '$(REMOTE_SSH_E)' $(RSYNC_EXCLUDES) ./ '$(REMOTE):$(REMOTE_PATH)/'
endef

# 用 login shell 執行，才讀得到遠端 ~/.profile 裡的 PATH（例如 ~/.cargo/bin、自己裝的 Flutter）
define remote_make
	@echo "==> 在 $(REMOTE) 上執行 make $(1) $(REMOTE_PASS)"
	$(REMOTE_SSH) "bash -lc 'cd $(REMOTE_PATH) && make --no-print-directory $(1) REMOTE= $(REMOTE_PASS)'"
endef

define remote_fetch
	@echo "==> 取回產出到 $(DIST)/"
	@files="$$($(REMOTE_SSH) 'cat $(REMOTE_PATH)/$(DIST)/.last-build' | tr '\n' ' ')" && test -n "$$files" && \
	  $(REMOTE_SSH) "cd $(REMOTE_PATH)/$(DIST) && tar -cf - $$files" | tar -xf - -C $(DIST) && \
	  for f in $$files; do echo "  $(DIST)/$$f"; done
endef

define linux_none
	@{ \
	  echo "這台 Linux 主機目前沒辦法建置 Linux 版："; \
	  command -v $(FLUTTER) >/dev/null || echo "  - 找不到 flutter（直接建置需要 Flutter $(FLUTTER_PINNED)）"; \
	  command -v cargo >/dev/null && command -v rustup >/dev/null || echo "  - 找不到 cargo／rustup（直接建置需要 Rust，要用 rustup 安裝）"; \
	  echo "  - Docker 不能用（沒有安裝，或 docker info 失敗：服務沒啟動、或目前使用者不在 docker 群組）"; \
	  echo; \
	  echo "二選一："; \
	  echo "  A. 用 Docker 建置（最簡單，不用裝 Flutter、Rust）："; \
	  echo "     安裝 Docker Engine（https://docs.docker.com/engine/install/），"; \
	  echo "     執行 sudo usermod -aG docker \$$USER 後重新登入，確認 docker info 沒有錯誤，再執行 make $@"; \
	  echo "  B. 直接在這台主機建置："; \
	  echo "     make linux-deps 安裝系統套件（Debian／Ubuntu），再依它的說明安裝 Flutter $(FLUTTER_PINNED) 與 Rust（rustup），"; \
	  echo "     然後執行 make $@"; \
	  echo "也可以用 REMOTE=user@host 改到另一台 Linux 上建置（見 README）。"; \
	} >&2; exit 1
endef

# linux_build,<build.sh 的參數>,<make 目標>
ifeq ($(LINUX_BUILD),remote)
  linux_build = $(remote_sync)$(newline)$(call remote_make,$(2))$(newline)$(remote_fetch)
else ifeq ($(LINUX_BUILD),docker)
  linux_build = $(DOCKER_RUN) $(IMAGE) tool/linux/build.sh $(1)
else ifeq ($(LINUX_BUILD),host)
  linux_build = tool/linux/build.sh $(1)
else
  linux_build = $(linux_none)
endif
define newline


endef
LINUX_PREREQ := $(if $(filter docker,$(LINUX_BUILD)),docker-image)

linux: env-check $(LINUX_PREREQ) ## Linux release bundle → .tar.gz（自動選建置方式，見下方「Linux 建置」）
	$(call linux_build,bundle,linux)

deb: env-check $(LINUX_PREREQ) ## Linux .deb（也會產出 .tar.gz）
	$(call linux_build,deb,deb)

linux-all: env-check $(LINUX_PREREQ) ## Linux 的 .tar.gz 和 .deb 一次建好
	$(call linux_build,all,linux-all)

linux-deps: ## 在這台 Debian／Ubuntu 上用 sudo apt 安裝直接建置需要的系統套件，並檢查 Flutter、Rust
	FLUTTER="$(FLUTTER)" FLUTTER_WANT=$(FLUTTER_PINNED) tool/linux/install_deps.sh

docker-image: ## 建立（或更新）Linux 建置用的 Docker 映像檔（DISTRO、ARCH）
	$(DOCKER) build --platform $(DOCKER_PLATFORM) --target build \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  -t $(IMAGE) -f docker/linux.Dockerfile docker

docker-smoke-image:
	$(DOCKER) build --platform $(DOCKER_PLATFORM) --target smoke \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  -t $(SMOKE_IMAGE) -f docker/linux.Dockerfile docker

linux-smoke: docker-smoke-image ## 在容器的 Xvfb 裡實際開 App、測試系統匣並截圖（先 make linux）→ build/linux-smoke/
	@test -f $(TARBALL) || { echo "找不到 $(TARBALL)，先執行 make linux（ARCH、DISTRO 要相同）" >&2; exit 1; }
	$(DOCKER) run --rm --platform $(DOCKER_PLATFORM) -v "$(CURDIR)":/src \
	  -e BUNDLE=/src/$(TARBALL) -e SHOTS=/src/build/linux-smoke/$(ART_DISTRO)-$(ARCH) \
	  -e HOST_UID=$(shell id -u) -e HOST_GID=$(shell id -g) \
	  $(SMOKE_IMAGE) tool/linux/smoke.sh

# 預設（ubuntu-22.04）的 .deb 在四個發行版都檢查；其他發行版建的只在同一個發行版檢查
DEB_CHECK_IMAGES ?= $(if $(ART_TAG),$(BASE_IMAGE),ubuntu:22.04 ubuntu:24.04 debian:12 debian:13)

deb-check: ## 在乾淨的 Ubuntu／Debian 容器裡 apt install .deb，確認相依套件與程式能啟動（DISTRO、ARCH 和建置時相同）
ifeq ($(LINUX_BUILD),remote)
	$(remote_sync)
	$(call remote_make,deb-check)
else
	@test -f $(DEB) || { echo "找不到 $(DEB)，先執行 make deb（ARCH、DISTRO 要相同）" >&2; exit 1; }
	@for base in $(DEB_CHECK_IMAGES); do \
	  echo "==> $$base"; \
	  $(DOCKER) run --rm --platform $(DOCKER_PLATFORM) -v "$(CURDIR)":/src:ro $$base \
	    bash /src/tool/linux/deb_check.sh /src/$(DEB) || exit 1; \
	done
endif

docker-clean: ## 刪掉 Linux 建置用的 Docker volume（DISTRO、ARCH；下次會重新下載套件、完整重建）
	-$(DOCKER) volume rm $(VOLUME_PREFIX)-work $(VOLUME_PREFIX)-pub-cache $(VOLUME_PREFIX)-cargo-registry $(VOLUME_PREFIX)-cargo-git

# ─── 發行 ──────────────────────────────────────────────

# macOS 主機：macOS、iOS、Android（有 Android SDK 時）、Linux（Docker 有在跑或有設定 REMOTE 時）
# Linux 主機：Android（有 Android SDK 時）、Linux（能建置時）
HAS_ANDROID := $(if $(or $(ANDROID_HOME),$(ANDROID_SDK_ROOT),$(wildcard $(HOME)/Library/Android/sdk),$(wildcard $(HOME)/Android/Sdk)),1,)
HAS_DOCKER = $(shell $(DOCKER) info >/dev/null 2>&1 && echo 1)
DIST_TARGETS = $(if $(filter Darwin,$(HOST_OS)),macos ios) \
  $(if $(HAS_ANDROID),apk aab) \
  $(if $(or $(filter host remote,$(LINUX_BUILD)),$(and $(filter docker,$(LINUX_BUILD)),$(HAS_DOCKER))),linux-all)

dist: env-check ## 建置這台主機能建的所有平台
	@echo "這台主機會建置：$(strip $(DIST_TARGETS))"
	@$(MAKE) --no-print-directory $(DIST_TARGETS)
	@echo
	@ls -lh $(DIST)

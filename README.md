# Securibit APP

<p align="center">
    <img src="assets/logo.png" width="96" />
</p>

Securibit 的兩步驟驗證器 App，支援 iOS、Android、macOS、Linux、Windows（不提供網頁版，網頁請用 [2fa.bityo.tw](https://2fa.bityo.tw)）。
後端和網站 [Securibit-Web](https://github.com/Securibit/Securibit-Web) 共用同一個 Supabase：登入、群組、權限、加密群組都和網站一致，在網站新增的驗證碼 App 馬上看得到。

| 項目 | 內容 |
| --- | --- |
| Framework | Flutter 3.35（Dart 3.9） |
| 後端 | Supabase（Auth + Postgres RPC），網站的 `/api/groups/codes`、`/api/record-login` |
| 狀態管理 | provider + ChangeNotifier |
| 安全核心 | Rust（`rust/core`，RustCrypto：PBKDF2-SHA256、HMAC、AES-GCM），透過 flutter_rust_bridge v2 給 Flutter 呼叫；TOTP、加密群組（與網站相容）、App 鎖定雜湊、記憶體裡的金鑰都在這裡 |
| 其他 | supabase_flutter、google_sign_in、app_links、flutter_secure_storage、mobile_scanner、local_auth |
| App ID | 各平台都是 `com.bityo.securibit`（iOS / macOS bundle id、Android applicationId 與 namespace、Linux application id）；Windows 安裝檔另有固定的 AppId（`tool/windows/securibit.iss`） |

## 設定

### 0. Rust

安全核心是 Rust，`flutter build` / `flutter run` 時由 cargokit 自動編譯（iOS、Android、macOS、Linux、Windows 都一樣），需要先裝好 [rustup](https://rustup.rs)：

```bash
rustup toolchain install stable
# 第一次編譯時 cargokit 會自動加上需要的 target；Android 需要 Android Studio 裡的 NDK
```

改了 `rust/api/src/api/` 底下的函式後要重新產生 Dart 端的介面（`lib/src/rust/`）：

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked   # 只要裝一次
flutter_rust_bridge_codegen generate
```

### 1. 連線設定 `env.json`

連線資訊用 `--dart-define-from-file` 帶入，不寫死在程式裡。複製範例後填入網站 `.env.local` 的值：

```bash
cp env.example.json env.json
```

```json
{
  "SUPABASE_URL": "https://<project>.supabase.co",
  "SUPABASE_ANON_KEY": "<anon public key>",
  "SECURIBIT_WEB_URL": "https://2fa.bityo.tw",
  "GOOGLE_WEB_CLIENT_ID": "",
  "GOOGLE_IOS_CLIENT_ID": ""
}
```

- `SUPABASE_URL`、`SUPABASE_ANON_KEY`：網站的 `NEXT_PUBLIC_SUPABASE_URL`、`NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SECURIBIT_WEB_URL`：網站網址。只有「查看驗證碼」權限（看不到金鑰）的驗證碼由網站產生動態碼，登入紀錄也記在網站
- `GOOGLE_WEB_CLIENT_ID`、`GOOGLE_IOS_CLIENT_ID`：手機原生 Google 登入用的 OAuth 用戶端 ID（見「3. 手機原生 Google 登入」）。留空時手機改用瀏覽器登入

`env.json` 已列在 `.gitignore`，不要提交。

### 2. Supabase 登入轉址

App 用 Google 登入（PKCE），登入完成後要轉回 App。到 Supabase 後台 **Authentication → URL Configuration → Redirect URLs** 加入：

| 平台 | Redirect URL |
| --- | --- |
| iOS、Android、macOS | `securibit://login-callback` |
| Linux、Windows | `http://127.0.0.1:*/login-callback`（App 在本機隨機埠號開一個暫時的伺服器接登入結果） |

網站目前只有 Google 登入，App 也只有 Google 登入。

### 3. 手機原生 Google 登入（iOS、Android）

iOS 和 Android 在 App 內直接跳出 Google 帳號選單（Android 走 Credential Manager），不用開瀏覽器；拿到 Google 的 ID token 後用 `signInWithIdToken` 換成 Supabase session。macOS、Linux、Windows 維持瀏覽器登入。
**還沒設定用戶端 ID 時手機會自動改用瀏覽器登入**（上一節的 `securibit://login-callback`），所以可以先不設定。

1. **建立 iOS 用戶端**：[Google Cloud Console](https://console.cloud.google.com/) → 選 Supabase 用的那個專案 → **APIs & Services → Credentials** → **Create credentials → OAuth client ID** → Application type 選 **iOS**，Bundle ID 填 `com.bityo.securibit`（App Store ID、Team ID 上架後再補）→ Create。記下 **Client ID** 和 **iOS URL scheme**（`com.googleusercontent.apps.…`）
2. **建立 Android 用戶端**：同一頁再 **Create credentials → OAuth client ID** → Application type 選 **Android**，Package name 填 `com.bityo.securibit`，SHA-1 填 debug keystore 的指紋：

   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
   ```

   之後有 release 簽章（或上架 Google Play 用 Play App Signing）時，要再建一個 Android 用戶端填 release 的 SHA-1，debug 和 release 指紋不同。Android 用戶端 ID 不用寫進 App
3. **找到網頁用戶端**：Credentials 頁 **OAuth 2.0 Client IDs** 裡 Type 是 **Web application** 的那一個，就是 Supabase Google provider 用的（和 Supabase 後台 Google provider 的 Client ID 相同）。記下它的 Client ID
4. **Supabase 後台**：**Authentication → Sign In / Providers → Google** →
   - **Client IDs**（Authorized Client IDs）改成「網頁用戶端,iOS 用戶端,Android 用戶端」，用逗號分隔、**網頁用戶端放第一個**（原本的網頁 Client ID 和 Client Secret 不要動，網站還在用）
   - 打開 **Skip nonce check**：iOS 的 Google SDK 會自己在 ID token 放 nonce，App 拿不到原始值，Supabase 文件建議 iOS 原生登入開這個選項
   - Save
5. **填入 App**：
   - `env.json`：`GOOGLE_WEB_CLIENT_ID` 填網頁用戶端 ID、`GOOGLE_IOS_CLIENT_ID` 填 iOS 用戶端 ID
   - `ios/Flutter/GoogleSignIn.xcconfig`：`GOOGLE_REVERSED_CLIENT_ID` 填第 1 步的 iOS URL scheme（就是 iOS 用戶端 ID 反過來寫，例如 `1234-abcd.apps.googleusercontent.com` → `com.googleusercontent.apps.1234-abcd`）。這個值會放進 Info.plist 的 URL scheme，沒辦法用 dart-define 帶入；用戶端 ID 不是機密，可以提交

Android 的 Credential Manager 在 release 版需要的 R8 規則已經放在 `android/app/proguard-rules.pro`。
Android 登入一按就回「已取消」通常是設定錯誤（package name、SHA-1 或網頁用戶端 ID 不對），不是使用者取消。

## 執行

```bash
flutter pub get

# macOS（支援 hot reload：在終端機按 r 重新載入、R 重新啟動）
flutter run -d macos --dart-define-from-file=env.json

# 其他平台
flutter run -d <iPhone / Android 裝置 id> --dart-define-from-file=env.json
flutter run -d linux --dart-define-from-file=env.json
flutter run -d windows --dart-define-from-file=env.json
```

`flutter devices` 可以列出可用的裝置。沒有帶 `--dart-define-from-file` 時 App 會顯示「缺少連線設定」。

## 建置

建置一律用最上層的 `Makefile`，產出都放在 `dist/`，檔名帶 `pubspec.yaml` 的版本。`make`（或 `make help`）列出所有目標。
所有建置目標都需要 `env.json`，沒有的話會直接停下來提示。

| 目標 | 產出（`dist/`） | 說明 |
| --- | --- | --- |
| `make deps`、`make analyze`、`make test`、`make clean` | | `flutter pub get`、`flutter analyze`、`flutter test`、清掉建置結果與 `dist/` |
| `make macos` | `Securibit-<版本>-macos.dmg`、`.zip` | macOS release（未簽章公證）。`.dmg` 是安裝檔：打開後把 securibit.app 拖到「應用程式」（用系統內建的 `hdiutil` 製作） |
| `make ios` | `Securibit-<版本>-ios-unsigned.ipa` | iOS release，不簽章（`--no-codesign`），要再用 Xcode 等工具簽過才能安裝 |
| `make apk` | `securibit-<版本>-arm64-v8a.apk` 等 | GitHub 版（會自己更新）：每種處理器一個 APK，混淆並去掉除錯符號（符號在 `build/symbols`，當機回報要用） |
| `make aab` | `securibit-<版本>.aab` | 上架 Google Play 用的 App Bundle（不含自我更新與 `REQUEST_INSTALL_PACKAGES`，見下方「檢查與自動更新」），Play 會依手機只下載需要的部分 |
| `make linux` | `Securibit-<版本>-linux-<arm64\|x64>.tar.gz` | Linux release bundle，解開後執行 `securibit/securibit`。自動選建置方式（見下方「Linux」） |
| `make deb` | `securibit_<版本>_<arm64\|amd64>.deb` | Debian / Ubuntu 套件（也會產出 .tar.gz） |
| `make linux-all` | 以上兩種 | 一次建好 Linux 的 .tar.gz 和 .deb |
| `make linux-deps` | | 在 Debian / Ubuntu 主機上安裝直接建置需要的系統套件，並檢查 Flutter、Rust |
| `make windows` | `Securibit-<版本>-windows-x64-setup.exe`、`Securibit-<版本>-windows-x64.zip` | Windows 安裝檔與免安裝版。要在 Windows 上建置：設定 `WIN_REMOTE=user@host` 時送到那台 Windows 建置再拉回來（見下方「Windows」） |
| `make dist` | | 建置這台主機能建的所有平台（macOS 主機：macOS、iOS、有 Android SDK 時加 Android、Docker 有在跑時加 Linux、有設定 `WIN_REMOTE` 時加 Windows） |
| `make checksums` | `SHA256SUMS.txt` | 這個版本所有產出的 SHA-256（每個建置目標建完都會自動更新）；發版時一起上傳，App 自動更新時用它確認檔案完整 |

一般 Android 手機裝 `arm64-v8a` 那個 APK 就好。QR 掃描用的是 Google Play 服務裡的 ML Kit 模型（沒有包進 APK），沒有 Google Play 服務的手機（例如部分華為）無法掃 QR，但可以貼上 otpauth 連結。

### 檢查與自動更新

macOS、Linux、Windows、Android（GitHub 版）開啟時會讀 `env.json` 的 `UPDATE_REPO`（例如 `Securibit/Securibit-APP`）在 GitHub 的最新正式 Release，之後每小時再查一次；`UPDATE_REPO` 留空就關閉。iOS 與 Google Play 版不檢查。
有新版本時在背景下載這個平台的安裝檔，和 Release 附的 `SHA256SUMS.txt` 比對，不符就丟掉、絕不安裝（下載失敗會安靜地重試）；通過後提示「新版本已準備好」，按「重新啟動並更新」：

- macOS：下載 `.zip`，用 `ditto` 解開並確認 Bundle ID、版本與簽章（Team ID 和目前的 App 相同），App 結束後由替換腳本把目前執行中的 .app（不一定在「應用程式」）換成新版、拿掉隔離屬性再打開；使用者直接結束 App 時也會順便換好。從磁碟映像檔或 App Translocation 執行、或沒有寫入權限時，提示先搬到「應用程式」或用瀏覽器下載。為了能替換自己，1.2.0 起關掉 App Sandbox，第一次啟動時會把舊沙盒裡的設定搬過來（`macos/Runner/SandboxMigration.swift`）
- Linux `.tar.gz`：資料夾可以寫入時同 macOS（等 App 結束後替換資料夾並重新打開），不能寫入時用瀏覽器下載
- Linux `.deb`（執行檔在 `/usr`、`/opt` 底下或由 dpkg 管理）：「立即更新」用 `pkexec apt-get install -y` 安裝後重新打開；沒有 pkexec 或取消授權時說明原因，可以改用瀏覽器下載
- Windows 安裝檔裝的（執行檔旁邊有 Inno Setup 的 `unins000.exe`）：下載 `Securibit-<版本>-windows-x64-setup.exe`，按「重新啟動並更新」時用 `/SILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /SP- /UPDATE` 啟動它再結束 App；安裝檔先等 App 結束（互斥鎖），裝好後自動打開新版。每個使用者各自安裝，不會跳出 UAC；App 自己下載的檔案沒有「從網路下載」的標記，也不會跳 SmartScreen
- Windows 免安裝版（`.zip` 解開的）：不自動更新，提示用瀏覽器下載
- Android：下載這支手機 ABI 的 APK，交給系統的安裝畫面（第一次要允許「安裝不明應用程式」）。Google Play 不允許 App 自己下載更新，所以 `make aab` 用 `--android-project-arg=distribution=play` 建置：不合併 `android/app/src/selfUpdate/AndroidManifest.xml`（`REQUEST_INSTALL_PACKAGES` 與 FileProvider），App 執行時看到沒有這個權限就整個關掉檢查更新。沒有用 product flavor，因為 flavor 會讓每次 `flutter run`／`build` 都得加 `--flavor`

發版時標籤用 `v<版本>`（例如 `v0.4.0`，和 `pubspec.yaml` 的版本相同），附件直接用 `dist/` 的檔名：`Securibit-<版本>-macos.dmg` 與 `.zip`、`securibit_<版本>_<amd64|arm64>.deb`、`Securibit-<版本>-linux-<x64|arm64>.tar.gz`、`securibit-<版本>-<arm64-v8a|armeabi-v7a|x86_64>.apk`、`Securibit-<版本>-windows-x64-setup.exe` 與 `Securibit-<版本>-windows-x64.zip`，再加上 `SHA256SUMS.txt`（沒有附的話 App 只會提示用瀏覽器下載）。

本機測試整個流程：`python3 tool/update_feed.py <放安裝檔的資料夾> <假的版本>` 在 `127.0.0.1:8765` 提供假的 `latest.json`、安裝檔與 `SHA256SUMS.txt`，App 用 `--dart-define=UPDATE_FEED_URL=http://127.0.0.1:8765/latest.json` 建置就會改讀這份（只有這時允許 http）。正式版不要設定。

### Linux

Linux 版只有兩種產出：`.tar.gz`（release bundle）和 `.deb`（Debian / Ubuntu 套件），而且要在 Linux 上建置。`make linux`、`make deb`、`make linux-all` 會自動選建置方式：

| 情況 | 建置方式 |
| --- | --- |
| 有設定 `REMOTE=user@host` | 把原始碼 rsync 到那台 Linux，在那裡跑同一個目標，完成後把產出拉回本機 `dist/` |
| 不是 Linux 的主機（例如 macOS） | Docker（`docker/linux.Dockerfile`） |
| Linux 主機，有 `flutter`、`cargo`、`rustup` | 直接在主機上建置 |
| Linux 主機，沒有上面的工具，但 Docker 能用（`docker info` 成功） | 自動改用 Docker |
| 兩者都沒有 | 停下來，說明要裝什麼 |

`LINUX_DOCKER=0` / `LINUX_DOCKER=1` 可以強制直接建置 / 用 Docker；在 Linux 主機上有指定 `DISTRO`，或 `ARCH` 和主機不同時，也會用 Docker。`make help` 最後一段會顯示這台主機目前會用哪一種。

#### 自己編譯

任何人 clone 下來都可以自己編譯。步驟：

1. **取得原始碼**

   ```bash
   git clone https://github.com/Securibit/Securibit-APP.git
   cd Securibit-APP
   ```

2. **準備自己的 Supabase 專案與 `env.json`**。repo 裡沒有任何正式環境的網址或金鑰，自己編譯的版本要接自己的 Supabase 專案：

   1. 到 [Supabase](https://supabase.com) 建一個專案
   2. 到專案的 **SQL Editor**，貼上並執行 [Securibit-Web](https://github.com/Securibit/Securibit-Web) 的 `database/init.sql`，一次建好所有資料表與函式
   3. App 目前只有 Google 登入（沒有 Email 密碼登入）：到 **Authentication → Sign In / Providers → Google** 打開 Google，填入自己在 [Google Cloud Console](https://console.cloud.google.com/) 建的「網頁應用程式」OAuth 用戶端 ID 與密鑰（Google 那邊的已授權重新導向 URI 填 Supabase 頁面上顯示的 Callback URL）；再到 **Authentication → URL Configuration → Redirect URLs** 加入 `http://127.0.0.1:*/login-callback`（Linux 版登入完成後轉回 App 用，見上面「2. Supabase 登入轉址」）
   4. 複製範例並填入自己專案的值（**Project Settings → API** 裡的 Project URL 與 anon public key）：

      ```bash
      cp env.example.json env.json
      ```

      - `SUPABASE_URL`、`SUPABASE_ANON_KEY`：自己專案的 URL 與 anon key
      - `SECURIBIT_WEB_URL`：自己架的 Securibit-Web 網址。App 有三件事要呼叫網站：記錄登入紀錄、「只能查看驗證碼」權限的群組產生驗證碼、管理員刪除使用者。網站必須接同一個 Supabase 專案，沒有自己架的話這三項會失敗（其他功能不受影響），網址維持範例值即可
      - `GOOGLE_WEB_CLIENT_ID`、`GOOGLE_IOS_CLIENT_ID`：只給 iOS / Android 手機原生 Google 登入用。Linux 版一律開瀏覽器走 Supabase 的 Google 登入，不會用到，留空就好（手機留空時也會改用瀏覽器登入）

   沒有 `env.json` 時建置會直接停下來提示；`env.json` 已列在 `.gitignore`，不要提交。

3. **二選一準備建置環境**

   - **A. 用 Docker（最簡單，不用裝 Flutter、Rust）**：安裝 [Docker Engine](https://docs.docker.com/engine/install/)，執行 `sudo usermod -aG docker $USER` 後重新登入，確認 `docker info` 沒有錯誤。第一次建置會先建映像檔（下載 Flutter、Rust 與系統套件，約 4 GB），之後重複使用
   - **B. 直接在主機上建置（Debian / Ubuntu）**：

     ```bash
     make linux-deps      # 用 sudo apt 安裝 clang、cmake、ninja、GTK 3、libsecret、jsoncpp、ayatana appindicator、dpkg-dev 等
     ```

     它會檢查 Flutter 與 Rust，沒裝的話印出安裝方式（不會自動安裝）：Flutter 用專案的版本 3.35.3（`git clone --depth 1 --branch 3.35.3 https://github.com/flutter/flutter.git ~/flutter`，把 `~/flutter/bin` 加進 PATH），Rust 用 [rustup](https://rustup.rs) 安裝（Rust 核心的建置工具要用 rustup，發行版的 `cargo` 套件不夠）

4. **建置**

   ```bash
   make deb          # 產出 dist/securibit_<版本>_<amd64|arm64>.deb 和 dist/Securibit-<版本>-linux-<x64|arm64>.tar.gz
   ```

5. **安裝或執行**

   ```bash
   sudo apt install ./dist/securibit_0.3.0_amd64.deb     # 相依套件由 apt 自動安裝，裝好後從應用程式選單開啟，或執行 securibit
   # 或不安裝，直接解開 tar.gz 執行：
   tar -xzf dist/Securibit-0.3.0-linux-x64.tar.gz
   ./securibit/securibit
   ```

   `.tar.gz` 不會幫你裝相依套件，系統要有 GTK 3、libsecret 與系統匣用的 `libayatana-appindicator3-1`（Debian / Ubuntu：`sudo apt install libayatana-appindicator3-1 libsecret-1-0 libgtk-3-0`，大部分桌面系統已經有 GTK 3 與 libsecret）。

**架構要對**：x64（amd64）的電腦用 x64 的產出，arm64（例如 Raspberry Pi 4/5、ARM 筆電）用 arm64 的產出。`ARCH` 預設和建置的主機相同；Docker 可以用 `ARCH=x64` / `ARCH=arm64` 建另一種架構（透過模擬執行，慢很多）。

#### 選發行版：`DISTRO=`

Docker 建置可以選底層的發行版：`ubuntu-22.04`（預設）、`ubuntu-24.04`、`debian-12`、`debian-13`。

```bash
make deb DISTRO=debian-12
```

- 預設的 Ubuntu 22.04（glibc 2.35）建出來的程式在 Ubuntu 22.04 以後、Debian 12 以後的發行版都能跑，相容性最廣，檔名不帶發行版：`securibit_0.3.0_amd64.deb`、`Securibit-0.3.0-linux-x64.tar.gz`
- 其他發行版建出來的只保證在同一版（或更新）上能跑，檔名會加上發行版：`securibit_0.3.0_debian-12_amd64.deb`、`Securibit-0.3.0-linux-debian-12-x64.tar.gz`
- 每個發行版有自己的映像檔（`securibit-linux:<Flutter 版本>-<DISTRO>-<arch>`，各約 4 GB）與 volume（`securibit-<DISTRO>-<arch>-work`、`-pub-cache`、`-cargo-registry`、`-cargo-git`），不互相影響；`make docker-clean DISTRO=… ARCH=…` 刪掉該組 volume
- 直接在主機上建置時不看 `DISTRO`，用主機本身的系統：檔名的發行版取自 `/etc/os-release`（`<ID>-<VERSION_ID>`），在 Ubuntu 22.04 上不加，其他系統例如 Debian 12 會是 `securibit_0.3.0_debian-12_amd64.deb`

#### 在另一台 Linux 上建置：`REMOTE=`

在 Mac 或沒有 Docker 的電腦上，可以借另一台 Linux（有 Docker，或有 Flutter 與 Rust）建置：

```bash
make deb REMOTE=user@192.168.1.20
make deb REMOTE=user@192.168.1.20 REMOTE_SSH_OPTS='-i ~/.ssh/id_ed25519' DISTRO=debian-12
```

- 先用 rsync 把原始碼（含 `env.json`）同步到遠端的 `REMOTE_DIR`（預設 `~/securibit-build`），不帶 `.git`、`build`、`dist`、`.dart_tool`、`rust/target`、其他平台的資料夾與 `local.mk`
- 再 ssh 到遠端跑同一個 make 目標，有指定的 `ARCH`、`DISTRO`、`LINUX_DOCKER` 會一起傳過去；沒指定時由遠端自己決定（例如 `ARCH` 用遠端的架構、自動選直接建置或 Docker）
- 完成後把遠端這次的產出拉回本機 `dist/`
- 遠端要有 `rsync` 與 `make`；`make deb-check REMOTE=…` 也可以直接在遠端跑安裝檢查
- 常用的設定可以寫在 `local.mk`（已列在 `.gitignore`），之後只要打 `make deb`：

  ```bash
  cp local.mk.example local.mk    # 填入 REMOTE、REMOTE_SSH_OPTS 等
  ```

#### GitHub Actions

不想在自己的電腦上建置的話，用 GitHub Actions（`.github/workflows/linux.yml`）：在 GitHub 的 Ubuntu 22.04 主機上直接建置 x64 與 arm64（和 `make linux-deps`、`make linux-all` 相同的流程），跑完安裝檢查，產出放在該次執行的 Artifacts。到 Actions → Linux → Run workflow 手動執行；選 `v*` 標籤執行時會附到同名的 Release。第一次要先在 repo 的 Settings → Secrets and variables → Actions 設定 `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`GOOGLE_WEB_CLIENT_ID`。

#### 打包內容與檢查

- Docker 的建置環境在 `docker/linux.Dockerfile`：`DISTRO` 對應的發行版、和主機相同版本的 Flutter（讀 `flutter --version`，讀不到時用 3.35.3）、clang、cmake、ninja、GTK 3、libsecret、ayatana appindicator，以及 rustup 與 cargo（Rust 核心要用）
- `.deb`：程式裝在 `/opt/securibit`，`/usr/bin/securibit` 指向它，另外有 `.desktop` 與 48、128、256、512 的 hicolor 圖示（`linux/packaging/`）。
  `Depends` 由 `dpkg-shlibdeps` 依實際連結的函式庫算出來（GTK 3、libsecret、ayatana appindicator 等），再加上執行時才載入的 libEGL、libGL；`Recommends: gnome-keyring`

檢查打包結果（都在 Docker 裡，`ARCH`、`DISTRO` 要和建置時相同）：

```bash
make linux-smoke                 # 在 Xvfb 裡實際開 App：視窗大小與標題、系統匣選單、關視窗藏到系統匣、再開一次叫回視窗、結束；截圖在 build/linux-smoke/
make deb-check                   # 在乾淨的 Ubuntu 22.04／24.04、Debian 12／13 裡 apt install .deb 並啟動
make deb-check DISTRO=debian-12  # 其他發行版建的 .deb 只在同一個發行版裡檢查
```

登入狀態存在系統金鑰圈（Secret Service，例如 gnome-keyring 或 KWallet），系統沒有的話登入狀態會改存一般設定檔，離線快取和「記住密語」會失效且不會提示，請確認桌面環境有在跑 gnome-keyring 或 KWallet。
Linux 的 Flutter 不會自己找中文的備援字型，App 依序使用 Noto Sans CJK TC、文泉驛等常見字型（見 `lib/core/platform.dart`），系統至少要裝一套中文字型（例如 `fonts-noto-cjk`）。

### Windows

Windows 版要在 Windows 10 以上（x64）建置，產出兩種：

- `Securibit-<版本>-windows-x64-setup.exe`：安裝檔（Inno Setup，`tool/windows/securibit.iss`）。每個使用者各自安裝在 `%LOCALAPPDATA%\Programs\Securibit`，不需要系統管理員；建立開始功能表捷徑（桌面捷徑可以勾選）；在 `HKCU\Software\Classes` 註冊 `securibit`、`otpauth`、`otpauth-migration` 三種連結；介面有繁體中文與英文（依系統語言）；完成頁可以勾選打開 Securibit。解除安裝會刪掉程式、捷徑、`securibit://`、登入時自動開啟的 Run 值與自動更新的暫存檔；`otpauth`、`otpauth-migration` 還指向 Securibit 時才刪（使用者後來改用別的驗證器就不動）。設定與登入資料（`%APPDATA%\BITYO\Securibit`）照 macOS、Linux 的慣例留著
- `Securibit-<版本>-windows-x64.zip`：免安裝版，解開後執行 `Securibit\securibit.exe`。不會註冊連結、不會自動更新

兩種都沒有程式碼簽章：用瀏覽器下載後第一次打開時，SmartScreen 會顯示「Windows 已保護您的電腦」，要按「其他資訊」→「仍要執行」。

#### 自己在 Windows 上建置

1. 安裝：
   - [Flutter 3.35.3](https://docs.flutter.dev/get-started/install/windows/desktop)（加到 `PATH`，或放在 `%USERPROFILE%\flutter`）與 Git
   - Visual Studio 2022 或 Build Tools 2022 的「使用 C++ 的桌面開發」，**另外勾選「適用於最新 v143 建置工具的 C++ ATL」**（`flutter_secure_storage` 的 Windows 外掛要用 ATL，沒有的話會出現找不到 `atlstr.h`）
   - [Rust](https://rustup.rs)：`rustup default stable-msvc`
   - [Inno Setup 6](https://jrsoftware.org/isinfo.php)（或 `winget install JRSoftware.InnoSetup`）
   - 打開「設定 › 系統 › 開發人員專用 › 開發人員模式」（Flutter 外掛要用到 symbolic link）
2. 準備 `env.json`（同上面的「自己編譯」）
3. 在專案資料夾執行：

   ```powershell
   powershell -NoProfile -File tool\windows\build.ps1
   ```

   會依序 `flutter build windows --release`、把 Visual Studio 的 Visual C++ 執行階段（`msvcp140.dll`、`vcruntime140.dll` 等）放進 App 的資料夾（乾淨的 Windows 不一定有）、打包 `.zip`、用 Inno Setup 做安裝檔，最後重新產生 `dist\SHA256SUMS.txt`（`dist\` 裡這個版本的所有產出）。`FLUTTER`、`ISCC` 環境變數可以指定 flutter 與 `ISCC.exe` 的路徑

開發時用 `flutter run -d windows --dart-define-from-file=env.json`。同一個使用者只能開一個 Securibit：已經開著安裝版時，`flutter run` 開的程式會把視窗交給它然後結束，要先關掉安裝版。

`build.ps1` 會在這次建置裡把 `PATH` 中的 `WindowsApps` 拿掉：從 Microsoft Store 裝的 PowerShell 7 在 SSH 等非互動的登入裡執行會「存取被拒」，`flutter.bat` 找到它就會失敗。

#### 從 Mac 送到另一台 Windows 建置：`WIN_REMOTE=`

```bash
make windows WIN_REMOTE=user@192.168.1.30 WIN_SSH_OPTS='-i ~/.ssh/id_ed25519'
```

- Windows 要開啟 OpenSSH 伺服器（預設的 shell 是 cmd），上面的工具都裝好
- 原始碼（含 `env.json`，不含 `.git`、`build`、`dist`、`.dart_tool`、`rust/target`、Android／iOS／macOS 的資料夾、`local.mk` 與簽章金鑰）用 `tar` 經 ssh 送到遠端家目錄下的 `WIN_REMOTE_DIR`（預設 `securibit-build`）。Windows 沒有 rsync，所以送之前先刪掉遠端的 `lib`、`test`、`tool` 等原始碼資料夾，`build` 等快取留著，第二次建置比較快
- 在遠端執行 `tool\windows\build.ps1`，再依 `dist\.last-build` 用 `scp` 把這次的產出拉回本機 `dist/`，最後更新 `dist/SHA256SUMS.txt`
- `WIN_REMOTE`、`WIN_SSH_OPTS`、`WIN_REMOTE_DIR` 可以寫在 `local.mk`

#### Windows 上的功能

| 功能 | 狀態 |
| --- | --- |
| 登入 | Google 登入開瀏覽器，用 127.0.0.1 本機轉址帶回 App（同 macOS、Linux） |
| 安全儲存 | `flutter_secure_storage` 的 Windows 版不用認證管理員（每筆上限 2560 bytes），而是把全部項目合成一份 JSON，用 DPAPI 綁這個 Windows 使用者加密，存在 `%APPDATA%\BITYO\Securibit\flutter_secure_storage.dat`，大的離線快取也放得下。每次寫入都是整份重寫，App 把 Windows 上的讀寫排隊一筆一筆做（`lib/core/secure_store.dart`） |
| 從圖片讀 QR Code | Rust 核心（同 Linux），支援 PNG、JPG、WebP、GIF、BMP |
| 相機掃描 | 沒有（mobile_scanner 沒有 Windows 版），按鈕不顯示 |
| 禁止截圖 | 設定頁關掉「允許截圖」時用 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`，視窗不出現在截圖、錄影與螢幕分享（2004 以前的 Windows 10 會拍到黑色）。預設允許，同 macOS、Linux |
| 點連結打開 App | 安裝檔註冊三種連結；App 已經開著時，新開的程式把連結交給原本的視窗（`WM_COPYDATA`）並叫到前面，自己結束（`windows/runner/main.cpp`，同一個使用者只會有一個 Securibit） |
| 自動更新 | 安裝檔裝的會自動更新；免安裝版用瀏覽器下載（見上方「檢查與自動更新」） |
| 系統匣常駐、登入時自動開啟 | 見下方「Windows 系統匣」 |
| 生物辨識（Windows Hello） | 還沒做：App 鎖定可以用密碼、PIN 或圖形 |

## 測試

```bash
# Rust 安全核心的單元測試
(cd rust && cargo test --workspace --release)

# Flutter 的測試會載入本機編好的 Rust 函式庫（見 test/flutter_test_config.dart），要先編一次
(cd rust && cargo build --release -p securibit_api)
flutter analyze
flutter test
```

測試包含（Rust 與 Dart 兩邊都有，Dart 端測的是透過 Rust 算出來的結果）：

- TOTP：RFC 6238 的 SHA-1 / SHA-256 / SHA-512（8 位數）測試向量，以及和網站 totp-generator 對照的結果
- otpauth:// 連結解析、Base32 檢查、表單驗證（錯誤訊息和網站相同）
- 加密群組：用網站自己的 `src/lib/vault/crypto.ts` 產生的測試向量解密，證明兩邊相容。重新產生向量：`tool/gen_vault_vector.sh ../Securibit-Web`（需要 node 22 以上），結果同時填進 `test/vault_test.dart` 與 `rust/core/src/vault.rs`
- App 鎖定：改用 Rust 之前由 Dart 存在裝置上的雜湊照樣驗證得過
- 記憶體裡的金鑰：鎖定時清掉、離線快取封起來的格式
- 選單列／系統匣的內容（分組、釘選、鎖定、遮住驗證碼、Linux 與 Windows 用的一行文字）、各平台的差異與設定頁的說明，以及 Linux 登入時自動開啟的 autostart 檔
- 自動更新：各平台要下載的檔案（含 Windows 安裝檔與免安裝版）、安裝方式的判斷、Windows 安裝檔的參數；Windows 安全儲存的排隊

## 程式結構

```
rust/
  core/                   securibit-core：純 Rust 的安全核心（不依賴 flutter_rust_bridge）
                          base32、secret、validate、totp、otpauth、vault（enc:v1）、lock、sealed、store
  api/                    securibit_api：flutter_rust_bridge 的薄薄一層，加上直接連 Supabase 取得金鑰（reqwest + rustls）
rust_builder/             FRB 產生的 FFI plugin 外殼，cargokit 在 flutter build 時編譯 rust/api
lib/
  main.dart               初始化 Rust 安全核心、Supabase、各個狀態
  src/rust/               flutter_rust_bridge 產生的 Dart 介面（不要手改）
  app.dart                主題、依登入狀態切換畫面
  core/                   連線設定、RPC、主題代幣、共用元件、秒針
  features/
    auth/                 Google 登入（手機原生 / 深層連結 / 桌面本機轉址）、profile
    groups/               my_groups、邀請、側欄
    codes/                驗證碼清單、詳細資料、新增與編輯、QR Code 掃描
      totp/               TOTP、otpauth、類別、表單驗證（對應網站 src/lib/totp，計算在 Rust）
    vault/                加密群組的解鎖（對應網站 src/lib/vault，計算在 Rust）
    cache/                離線快取（系統安全儲存；金鑰由 Rust 用這台裝置的金鑰封起來）
    settings/             主題、生物辨識鎖定、帳戶資訊、登出
    menubar/              macOS 選單列、Linux 與 Windows 系統匣的內容與原生端的溝通，Linux 的登入時自動開啟
                          （原生端在 macos/Runner/MenuBarController.swift、linux/runner/tray.cc、windows/runner/tray.cpp）
    shell/                三欄 / 側欄的版面
windows/runner/           Windows 的原生端：單一執行個體與連結轉交、視窗大小、截圖保護（securibit/privacy）、
                          系統匣（tray.cpp）、登入時自動開啟（launch_at_login.cpp）
tool/windows/             Windows 的建置腳本（build.ps1）與 Inno Setup 安裝檔（securibit.iss、繁體中文介面翻譯）
```

版面參考 Proton Pass：寬視窗是「群組側欄｜驗證碼清單｜詳細資料」三欄；視窗變窄時側欄收進左上角的選單；手機是清單一頁、點一筆開詳細資料。

### macOS 選單列

macOS 版預設常駐在選單列：關掉視窗（紅色按鈕或 ⌘W）只是把視窗藏起來並收起 Dock 圖示，⌘Q 或選單的「結束 Securibit」才會結束。
點選單列圖示會用原生選單依群組列出驗證碼（釘選的在前、每秒更新、快到期變紅），點一下複製。
App 鎖定中、加密群組沒解鎖、沒有登入時不列出驗證碼；開了「隱藏驗證碼」時顯示圓點，點了一樣複製。
資料一律由 Dart 算好再交給原生端，原生端只拿到顯示用的文字，不會拿到金鑰。
設定頁可以關掉「在選單列顯示」（關掉後關視窗就結束 App），以及打開「登入時自動開啟」（macOS 13 以上）。

### Linux 系統匣

Linux 版用同一份選單內容常駐在系統匣（Ayatana AppIndicator，原生端在 `linux/runner/tray.cc`）：
點圖示依群組列出驗證碼（釘選的在前），點一下複製；最下面是「打開 Securibit」「設定…」「結束 Securibit」。
鎖定、加密群組沒解鎖、沒有登入時的顯示和 macOS 一樣，原生端一樣只拿到顯示用的文字。

- 系統匣的選單由桌面面板畫，只能顯示一行文字（「名稱　驗證碼　剩餘秒數」，快到期時是「剩 5 秒」），不能上色或對齊欄位
- 面板打開選單時會通知 App（dbusmenu 的 AboutToShow），App 這時更新驗證碼；不是每個面板都會通知，所以主視窗藏起來時每秒更新一次選單內容
- 打開系統匣時關掉視窗只是藏起來，選「結束 Securibit」才會結束；再開一次 App 會叫回藏起來的視窗（同時只會有一個 Securibit）。桌面沒有系統匣時關掉視窗就直接結束，免得叫不回來
- 視窗藏起來算離開 App、叫回來算回來，App 鎖定照常生效
- 設定頁的「在系統匣顯示」與「登入時自動開啟」：後者會在 `~/.config/autostart/com.bityo.securibit.desktop` 寫入（或刪除）啟動項目，指向目前執行的程式
- GNOME 要先安裝 [AppIndicator 擴充功能](https://extensions.gnome.org/extension/615/appindicator-support/)（Ubuntu 已內建）才看得到圖示；KDE、XFCE、Cinnamon 可以直接使用

### Windows 系統匣

Windows 版用同一份選單內容常駐在系統匣（`Shell_NotifyIcon` 與 `TrackPopupMenu`，原生端在 `windows/runner/tray.cpp`）：
左鍵或右鍵點圖示都會打開選單，依群組列出驗證碼（驗證碼很多時每個群組收成子選單），點一下複製，系統匣跳出「已複製」的通知（不出聲、勿擾時不顯示，兩秒後收掉）。
鎖定、加密群組沒解鎖、沒有登入時的顯示和 macOS、Linux 一樣，原生端一樣只拿到顯示用的文字。

- 選單只能顯示一行文字（同 Linux）；打開前才向 App 要最新的驗證碼，選單開著時文字不更新，點了以後由 App 算當下的碼，複製到的一定正確
- 打開系統匣時關掉視窗（X、Alt+F4）只是藏起來，選「結束 Securibit」才會結束；從系統匣選「打開 Securibit」或再開一次 App 會叫回視窗。圖示加不上去時關掉視窗就直接結束
- 視窗藏起來算離開 App、叫回來算回來，App 鎖定照常生效
- 「登入時自動開啟」寫在 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的 `Securibit`（`"<securibit.exe>" --hidden`），登入時直接藏在系統匣、不跳出視窗；在「設定 › 應用程式 › 啟動」關掉的話，設定頁會說明要到那裡打開。安裝檔更新時改指向新的位置，解除安裝時刪掉
- 安裝或解除安裝時 Securibit 還開著（例如藏在系統匣），安裝檔會先問，再請 App 自己結束（送 `Securibit.Quit` 視窗訊息）；App 自動更新是 App 先結束再安裝，照常運作
- Windows 11 預設把新的圖示收在工作列右下角的「^」裡，可以拖到工作列上一直顯示

## 開發者
由幣友 BITYO 與靈魂之神工作室共同開發。

- 夏特稀 — <https://github.com/mmm25002500>
- 糖豆魚 — <https://github.com/PTDTW>

## 貢獻
有問題就開 issue。要改東西的話 fork 出去開分支發 PR，commit 訊息寫清楚、確認 `flutter analyze` 與 `flutter test` 都過了再丟。

## 金鑰放在哪裡

- 驗證碼的金鑰由 Rust 直接向 Supabase 取得（`group_account_secrets`，Dart 只給網址、anon key 與登入 token），解密（加密群組）、產生驗證碼都在 Rust，Dart 只拿到驗證碼
- 只有使用者按了「顯示金鑰」、「複製金鑰」或編輯時，Dart 才向 Rust 取出那一筆金鑰
- 加密群組解開的金鑰只在 Rust；「在這台裝置記住」存的是用這台裝置的金鑰包過的密文
- 離線快取裡的金鑰由 Rust 用這台裝置的金鑰（32 位元組隨機，存在系統安全儲存）封起來，Dart 只存密文
- App 鎖定、登出、加密群組鎖定、刪除驗證碼、離開畫面時，Rust 記憶體裡的金鑰歸零；App 鎖定期間不接受新的金鑰，解鎖後從離線快取放回來

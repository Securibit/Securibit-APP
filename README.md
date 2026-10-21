# Securibit APP

<p align="center">
    <img src="assets/logo.png" width="96" />
</p>

Securibit 的兩步驟驗證器 App，支援 iOS、Android、macOS、Linux（不提供網頁版，網頁請用 [2fa.bityo.tw](https://2fa.bityo.tw)）。
後端和網站 [Securibit-Web](https://github.com/Securibit/Securibit-Web) 共用同一個 Supabase：登入、群組、權限、加密群組都和網站一致，在網站新增的驗證碼 App 馬上看得到。

| 項目 | 內容 |
| --- | --- |
| Framework | Flutter 3.35（Dart 3.9） |
| 後端 | Supabase（Auth + Postgres RPC），網站的 `/api/groups/codes`、`/api/record-login` |
| 狀態管理 | provider + ChangeNotifier |
| 加密 | cryptography / cryptography_flutter（PBKDF2-SHA256 60 萬次 → AES-GCM，與網站相容） |
| 其他 | supabase_flutter、google_sign_in、app_links、flutter_secure_storage、mobile_scanner、local_auth |
| App ID | 各平台都是 `com.bityo.securibit`（iOS / macOS bundle id、Android applicationId 與 namespace、Linux application id） |

## 設定

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
| Linux | `http://127.0.0.1:*/login-callback`（App 在本機隨機埠號開一個暫時的伺服器接登入結果） |

網站目前只有 Google 登入，App 也只有 Google 登入。

### 3. 手機原生 Google 登入（iOS、Android）

iOS 和 Android 在 App 內直接跳出 Google 帳號選單（Android 走 Credential Manager），不用開瀏覽器；拿到 Google 的 ID token 後用 `signInWithIdToken` 換成 Supabase session。macOS、Linux 維持瀏覽器登入。
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
```

`flutter devices` 可以列出可用的裝置。沒有帶 `--dart-define-from-file` 時 App 會顯示「缺少連線設定」。

## 建置

```bash
flutter build macos --release --dart-define-from-file=env.json
flutter build ios --release --dart-define-from-file=env.json
# Android：每種處理器各出一個 APK，並去掉除錯符號（符號存在 build/symbols，當機回報要用）
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json
# 上架 Google Play 用 App Bundle，Play 會依手機只下載需要的部分
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json
flutter build linux --release --dart-define-from-file=env.json   # 要在 Linux 上建置
```

一般 Android 手機裝 `app-arm64-v8a-release.apk` 就好。QR 掃描用的是 Google Play 服務裡的 ML Kit 模型（沒有包進 APK），沒有 Google Play 服務的手機（例如部分華為）無法掃 QR，但可以貼上 otpauth 連結。

Linux（Debian/Ubuntu）需要先安裝：

```bash
sudo apt install libgtk-3-dev libsecret-1-dev libjsoncpp-dev pkg-config clang cmake ninja-build
```

產出在 `build/linux/<x64|arm64>/release/bundle/`。登入狀態存在系統金鑰圈（Secret Service，例如 gnome-keyring 或 KWallet），系統沒有的話登入狀態會改存一般設定檔，離線快取和「記住密語」會失效且不會提示，請確認桌面環境有在跑 gnome-keyring 或 KWallet。

## 測試

```bash
flutter analyze
flutter test
```

測試包含：

- TOTP：RFC 6238 的 SHA-1 / SHA-256 / SHA-512（8 位數）測試向量，以及和網站 totp-generator 對照的結果
- otpauth:// 連結解析、Base32 檢查、表單驗證（錯誤訊息和網站相同）
- 加密群組：用網站自己的 `src/lib/vault/crypto.ts` 產生的測試向量解密，證明兩邊相容。重新產生向量：`tool/gen_vault_vector.sh ../Securibit-Web`（需要 node 22 以上）

## 程式結構

```
lib/
  main.dart               初始化 Supabase、各個狀態
  app.dart                主題、依登入狀態切換畫面
  core/                   連線設定、RPC、主題代幣、共用元件、秒針
  features/
    auth/                 Google 登入（手機原生 / 深層連結 / Linux 本機轉址）、profile
    groups/               my_groups、邀請、側欄
    codes/                驗證碼清單、詳細資料、新增與編輯、QR Code 掃描
      totp/               TOTP、Base32、otpauth、類別、表單驗證（對應網站 src/lib/totp）
    vault/                加密群組的解鎖（對應網站 src/lib/vault）
    cache/                離線快取（系統安全儲存）
    settings/             主題、生物辨識鎖定、帳戶資訊、登出
    menubar/              macOS 選單列的內容與原生端的溝通（原生端在 macos/Runner/MenuBarController.swift）
    shell/                三欄 / 側欄的版面
```

版面參考 Proton Pass：寬視窗是「群組側欄｜驗證碼清單｜詳細資料」三欄；視窗變窄時側欄收進左上角的選單；手機是清單一頁、點一筆開詳細資料。

### macOS 選單列

macOS 版預設常駐在選單列：關掉視窗（紅色按鈕或 ⌘W）只是把視窗藏起來並收起 Dock 圖示，⌘Q 或選單的「結束 Securibit」才會結束。
點選單列圖示會用原生選單依群組列出驗證碼（釘選的在前、每秒更新、快到期變紅），點一下複製。
App 鎖定中、加密群組沒解鎖、沒有登入時不列出驗證碼；開了「隱藏驗證碼」時顯示圓點，點了一樣複製。
資料一律由 Dart 算好再交給原生端，原生端只拿到顯示用的文字，不會拿到金鑰。
設定頁可以關掉「在選單列顯示」（關掉後關視窗就結束 App），以及打開「登入時自動開啟」（macOS 13 以上）。

## 開發者
- 夏特稀 — <https://github.com/mmm25002500>

## 貢獻
有問題就開 issue。要改東西的話 fork 出去開分支發 PR，commit 訊息寫清楚、確認 `flutter analyze` 與 `flutter test` 都過了再丟。

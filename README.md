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
| 其他 | supabase_flutter、app_links、flutter_secure_storage、mobile_scanner、local_auth |

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
  "SECURIBIT_WEB_URL": "https://2fa.bityo.tw"
}
```

- `SUPABASE_URL`、`SUPABASE_ANON_KEY`：網站的 `NEXT_PUBLIC_SUPABASE_URL`、`NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SECURIBIT_WEB_URL`：網站網址。只有「查看驗證碼」權限（看不到金鑰）的驗證碼由網站產生動態碼，登入紀錄也記在網站

`env.json` 已列在 `.gitignore`，不要提交。

### 2. Supabase 登入轉址

App 用 Google 登入（PKCE），登入完成後要轉回 App。到 Supabase 後台 **Authentication → URL Configuration → Redirect URLs** 加入：

| 平台 | Redirect URL |
| --- | --- |
| iOS、Android、macOS | `securibit://login-callback` |
| Linux | `http://127.0.0.1:*/login-callback`（App 在本機隨機埠號開一個暫時的伺服器接登入結果） |

網站目前只有 Google 登入，App 也只有 Google 登入。

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
flutter build apk --release --dart-define-from-file=env.json
flutter build linux --release --dart-define-from-file=env.json   # 要在 Linux 上建置
```

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
    auth/                 Google 登入（深層連結 / Linux 本機轉址）、profile
    groups/               my_groups、邀請、側欄
    codes/                驗證碼清單、詳細資料、新增與編輯、QR Code 掃描
      totp/               TOTP、Base32、otpauth、類別、表單驗證（對應網站 src/lib/totp）
    vault/                加密群組的解鎖（對應網站 src/lib/vault）
    cache/                離線快取（系統安全儲存）
    settings/             主題、生物辨識鎖定、帳戶資訊、登出
    shell/                三欄 / 側欄的版面
```

版面參考 Proton Pass：寬視窗是「群組側欄｜驗證碼清單｜詳細資料」三欄；視窗變窄時側欄收進左上角的選單；手機是清單一頁、點一筆開詳細資料。

## 開發者
- 夏特稀 — <https://github.com/mmm25002500>

## 貢獻
有問題就開 issue。要改東西的話 fork 出去開分支發 PR，commit 訊息寫清楚、確認 `flutter analyze` 與 `flutter test` 都過了再丟。

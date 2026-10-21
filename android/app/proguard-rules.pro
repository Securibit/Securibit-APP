# Google 原生登入（google_sign_in → Credential Manager）：release 版開了 R8，
# 要保留 Play 服務的 Credential Manager 實作，否則找不到 provider（Android 官方文件的規則）
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}

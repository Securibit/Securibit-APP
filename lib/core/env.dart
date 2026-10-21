// 連線設定：用 --dart-define-from-file=env.json 帶入（見 README），不寫死在程式裡
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // 網站網址：「只能查看驗證碼、看不到金鑰」時要請網站的 API 產生動態碼，登入紀錄也記在網站
  static const webUrl = String.fromEnvironment('SECURIBIT_WEB_URL', defaultValue: 'https://2fa.bityo.tw');

  // Google 原生登入（iOS / Android）用的 OAuth 用戶端 ID，不是機密。
  // 網頁用戶端 ID 當 serverClientId，讓 idToken 的 audience 是 Supabase 認得的那一個；
  // 沒填的話手機改用瀏覽器登入（同桌面版）
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

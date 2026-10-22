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

  // 檢查更新用的 GitHub repo（owner/name），讀它的 Releases；留空就不檢查更新（自己架後端的人可以關掉或指向自己的 repo）
  static const updateRepo = String.fromEnvironment('UPDATE_REPO');

  // 只在開發測試時用：改讀這個網址的「最新版」JSON（格式同 GitHub 的 releases/latest，可以是本機的 http），
  // 用來在本機測整個自動更新流程。正式版不設定，照 UPDATE_REPO 讀 GitHub
  static const updateFeedUrl = String.fromEnvironment('UPDATE_FEED_URL');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

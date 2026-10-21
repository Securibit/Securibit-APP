// 連線設定：用 --dart-define-from-file=env.json 帶入（見 README），不寫死在程式裡
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // 網站網址：「只能查看驗證碼、看不到金鑰」時要請網站的 API 產生動態碼，登入紀錄也記在網站
  static const webUrl = String.fromEnvironment('SECURIBIT_WEB_URL', defaultValue: 'https://2fa.bityo.tw');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

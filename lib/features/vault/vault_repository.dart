import '../../core/env.dart';
import '../../core/json.dart';
import '../../core/platform.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../../src/rust/api/secrets.dart' show SupabaseConnection;

/// 讓 Rust 直接連 Supabase 用的連線資訊（重新加密的金鑰由 Rust 自己取得、寫回，不經過 Dart）；token 過期時先換新
Future<Result<SupabaseConnection>> vaultConnection() async {
  var session = supabase.auth.currentSession;
  if (session == null) return const Err('尚未登入');
  if (session.isExpired) {
    try {
      session = (await supabase.auth.refreshSession()).session ?? session;
    } catch (error) {
      return errorResult(error);
    }
  }
  return Ok(SupabaseConnection(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    accessToken: session.accessToken,
    userAgent: AppPlatform.userAgent,
  ));
}

/// 忘記加密密碼：清空我擁有且已加密的群組裡的驗證碼，那些群組改成沒加密，並停用加密（同網站 resetVault）
Future<Result<void>> resetVault() => rpcVoid('vault_reset');

// ---------- 密碼備援（escrow） ----------

/// 伺服器還沒有目前這組密碼的備援密文（解鎖成功後問，缺少就補）
Future<Result<bool>> escrowNeeded() => rpc('vault_escrow_needed', (data) => asBool(data));

/// 補存備援密文（綁定目前的加密設定）
Future<Result<void>> escrowPut(String escrow) => rpcVoid('vault_escrow_put', {'escrow': escrow});

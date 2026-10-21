import '../../src/rust/api/secrets.dart' as core;
import 'code_models.dart';

/*
 * 指向 Rust 記憶體裡的一筆金鑰（不含金鑰本身）。
 * 產碼在 Rust 做，只有使用者按了顯示、複製或編輯時才用 reveal 取出金鑰。
 * scope 是記憶體裡的一格：每個畫面（主畫面的群組、選單列、後台）各用各的，關掉時清掉自己那一格。
 */
class SecretHandle {
  const SecretHandle({required this.scope, required this.accountId, required this.valid});

  final String scope;
  final String accountId;
  // 格式正確（解不開的加密金鑰是 false，畫面顯示「金鑰錯誤」）
  final bool valid;

  /// 第 counter 個週期（時間 / 週期）與下一個週期的驗證碼
  core.OtpCodes codes(GroupAccount account, int counter) => core.secretsOtp(
        scope: scope,
        id: accountId,
        digits: account.digits,
        algorithm: account.algorithm.label,
        counter: counter,
      );

  /// 使用者按了顯示、複製或編輯時才取出（正規化後的）金鑰；格式錯誤或已清掉時是 null
  String? reveal() => core.secretsReveal(scope: scope, id: accountId);

  static Map<String, SecretHandle> fromMetas(String scope, List<core.SecretMeta>? metas) => {
        for (final meta in metas ?? const <core.SecretMeta>[])
          meta.id: SecretHandle(scope: scope, accountId: meta.id, valid: meta.valid),
      };
}

var _nextScope = 0;

/// 產生一格新的 scope（prefix 只是方便除錯）
String newSecretScope(String prefix) => '$prefix:${_nextScope++}';

/// 清掉這一格的全部金鑰（歸零）
void clearSecretScope(String scope) => core.secretsClearScope(scope: scope);

/// 刪掉一筆驗證碼時把它的金鑰歸零
void removeSecret(String scope, String accountId) => core.secretsRemove(scope: scope, id: accountId);

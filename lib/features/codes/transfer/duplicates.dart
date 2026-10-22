import '../code_models.dart';
import '../codes_controller.dart';
import '../totp/secret.dart';
import '../totp/totp_params.dart';

/*
 * 金鑰重複的檢查（同網站 AddCodeClient / BulkImportModal）：
 * 只比得到我有「查看金鑰」的那些；金鑰在 Rust，比對時才用 SecretHandle.reveal 取出來，比完就丟掉。
 */

/// 群組裡和 secret 相同金鑰的第一筆；沒有就是 null
GroupAccount? findDuplicate(List<GroupAccount> accounts, String? Function(GroupAccount account) reveal, String secret) {
  final target = normalizeSecret(secret);
  if (target.isEmpty) return null;
  for (final account in accounts) {
    final existing = reveal(account);
    if (existing != null && existing.isNotEmpty && normalizeSecret(existing) == target) return account;
  }
  return null;
}

/// 目前群組裡和 secret 相同金鑰的那一筆
GroupAccount? findDuplicateIn(CodesController controller, String secret) =>
    findDuplicate(controller.ordered, (account) => controller.secretOf(account)?.reveal(), secret);

/// 每一筆和誰重複：群組裡已經有是「已存在」，和清單裡前面某一筆相同是「和第 N 筆相同」，沒重複是 null。
/// 兩種分開標，不然清單裡自己重複的（例如 Google Authenticator 存了兩次）看起來像群組裡已經有
List<String?> duplicateLabels(Iterable<String> existing, List<TotpInput> items) {
  final have = {for (final secret in existing) normalizeSecret(secret)};
  final first = <String, int>{};
  final labels = <String?>[];
  for (final (i, item) in items.indexed) {
    final secret = normalizeSecret(item.secret);
    if (have.contains(secret)) {
      labels.add('已存在');
      continue;
    }
    final earlier = first.putIfAbsent(secret, () => i);
    labels.add(earlier == i ? null : '和第 ${earlier + 1} 筆相同');
  }
  return labels;
}

/// 每一筆是否和既有的、或和清單裡前面的重複（重複的預設不勾）
List<bool> markDuplicates(Iterable<String> existing, List<TotpInput> items) =>
    [for (final label in duplicateLabels(existing, items)) label != null];

/// 目前群組裡我看得到的全部金鑰（正規化），給整批匯入標示「已存在」
Set<String> existingSecrets(CodesController controller) => {
      for (final account in controller.ordered)
        if (controller.secretOf(account)?.reveal() case final secret? when secret.isNotEmpty) normalizeSecret(secret),
    };

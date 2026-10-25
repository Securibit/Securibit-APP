import '../../../core/result.dart';
import '../../../core/rpc.dart';
import '../../../src/rust/api/vault.dart' as vault;
import '../totp/categories.dart';
import '../totp/secret.dart';
import '../totp/totp_params.dart';

/*
 * 整批匯入（同網站 AddCodeClient 的 handleBulkImport → addGroupAccounts）：一次 group_account_add 送出全部。
 * 加密群組的金鑰逐筆在 Rust 用已解鎖的加密金鑰加密成 enc:v1 才送出；沒加密的群組送正規化後的明文（資料庫會拒絕存入密文）。
 */

const vaultLockedMessage = '加密群組已鎖定，請先解鎖';

/// 加密一個金鑰；加密群組還沒解鎖時回傳 null
typedef SecretEncrypter = String? Function(String secret);

String? _vaultEncrypt(String secret) => vault.vaultEncrypt(text: secret);

/// 組出要送給 group_account_add 的 items。
/// category 有填就取代各筆原本的類別（可多個），留空則保留各筆自己的；加密群組有任何一筆加密失敗（已鎖定）就整批不送
Result<List<Map<String, dynamic>>> buildImportItems(
  List<TotpInput> inputs, {
  String category = '',
  required bool encrypted,
  SecretEncrypter encrypt = _vaultEncrypt,
}) {
  final override = normalizeCategories(category);
  final items = <Map<String, dynamic>>[];
  for (final input in inputs) {
    final normalized = normalizeSecret(input.secret);
    final secret = encrypted ? encrypt(normalized) : normalized;
    if (secret == null) return const Err(vaultLockedMessage);
    items.add(input
        .copyWith(
          name: input.name.trim(),
          category: override.isNotEmpty ? override : normalizeCategories(input.category),
          secret: secret,
        )
        .toJson());
  }
  return Ok(items);
}

/// 資料庫一次最多收幾筆（totp_import_items / group_account_add 的上限）
const importBatchSize = 500;

/// 把多筆驗證碼加到群組，回傳新的 id（順序同 inputs）；超過上限時分批送出，
/// 中途失敗時前面的批次已經存好，訊息會說明匯入了幾筆
Future<Result<List<String>>> importGroupAccounts(
  String gid,
  List<TotpInput> inputs, {
  String category = '',
  required bool encrypted,
}) async {
  if (inputs.isEmpty) return const Ok([]);
  switch (buildImportItems(inputs, category: category, encrypted: encrypted)) {
    case Err(:final message):
      return Err(message);
    case Ok(data: final items):
      final ids = <String>[];
      for (var start = 0; start < items.length; start += importBatchSize) {
        final batch = items.sublist(start, (start + importBatchSize).clamp(0, items.length));
        final result = await rpc('group_account_add', (data) => data is List ? data.map((e) => '$e').toList() : <String>[], {
          'gid': gid,
          'items': batch,
        });
        switch (result) {
          case Ok(:final data):
            ids.addAll(data);
          case Err(:final message, :final offline):
            return Err(ids.isEmpty ? message : '已匯入 ${ids.length} 筆，其餘失敗：$message', offline: offline);
        }
      }
      return Ok(ids);
  }
}

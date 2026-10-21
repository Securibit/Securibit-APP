import 'package:cryptography/cryptography.dart';

import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../vault/vault_crypto.dart';
import 'code_models.dart';
import 'totp/categories.dart';
import 'totp/secret.dart';
import 'totp/totp_params.dart';

// 群組裡我看得到的驗證碼（不含金鑰），原始 JSON 給離線快取
Future<Result<List<Map<String, dynamic>>>> loadGroupAccountsRaw(String gid) => rpc('group_accounts', asMapList, {'gid': gid});

// 我有「查看金鑰」的全部金鑰 { id: secret }，加密群組是 enc:v1 密文（會記一筆「查看金鑰」紀錄）
Future<Result<Map<String, String>>> loadGroupAccountSecretsRaw(String gid) => rpc(
      'group_account_secrets',
      (data) => asMap(data).map((k, v) => MapEntry(k, asString(v))),
      {'gid': gid},
    );

/// 給 key 時（加密群組）把 enc:v1 密文解開；解不開的（例如別的裝置用舊密碼寫入）保留原值，畫面會顯示金鑰錯誤
Future<Map<String, String>> decryptSecrets(Map<String, String> raw, SecretKey? key) async {
  if (key == null) return raw;
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (!isEncrypted(entry.value)) {
      result[entry.key] = entry.value;
      continue;
    }
    try {
      result[entry.key] = await decryptText(key, entry.value);
    } catch (_) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

// 只有「查看驗證碼」時，請網站產生動態碼（金鑰不會傳到 App）
Future<Result<ServerCodes>> loadGroupCodes(String gid) async {
  final sentAt = DateTime.now().millisecondsSinceEpoch;
  final result = await callWebApi('/api/groups/codes', {'groupId': gid});
  switch (result) {
    case Ok(:final data):
      final now = asInt(data['now'], sentAt);
      // 取來回時間的中點估計時間差
      final offset = now - (sentAt + DateTime.now().millisecondsSinceEpoch) ~/ 2;
      final codes = asMap(data['codes']).map((id, value) {
        final entry = asMap(value);
        return MapEntry(id, ServerCode(code: asNullableString(entry['code']), next: asNullableString(entry['next'])));
      });
      return Ok(ServerCodes(offsetMs: offset, at: now, codes: codes));
    case Err(:final message, :final offline):
      return Err(message, offline: offline);
  }
}

// 加密群組要給 key：先在 App 把金鑰加密成 enc:v1 再送出；沒加密的群組不要給（資料庫會拒絕存入密文）
Future<String> _encodeSecret(String secret, SecretKey? key) async {
  final normalized = normalizeSecret(secret);
  return key == null ? normalized : encryptText(key, normalized);
}

Future<Result<List<String>>> addGroupAccount(String gid, TotpInput input, SecretKey? key) async {
  final item = input
      .copyWith(name: input.name.trim(), category: normalizeCategories(input.category), secret: await _encodeSecret(input.secret, key))
      .toJson();
  return rpc('group_account_add', (data) => data is List ? data.map((e) => '$e').toList() : <String>[], {
    'gid': gid,
    'items': [item],
  });
}

/// 只送要修改的欄位；secret 為 null 代表不修改（避免沒有「查看金鑰」的人誤把金鑰清掉）
Future<Result<void>> updateGroupAccount(String accountId, TotpInput input, {String? secret, SecretKey? key}) async {
  final patch = <String, dynamic>{
    'name': input.name.trim(),
    'category': normalizeCategories(input.category),
    'digits': input.digits,
    'period': input.period,
    'algorithm': input.algorithm.label,
    if (secret != null) 'secret': await _encodeSecret(secret, key),
  };
  return rpcVoid('group_account_update', {'account_id': accountId, 'patch': patch});
}

Future<Result<void>> setPinned(String accountId, bool pinned) =>
    rpcVoid('group_account_update', {'account_id': accountId, 'patch': {'pinned': pinned}});

Future<Result<void>> deleteGroupAccount(String accountId) => rpcVoid('group_account_delete', {'account_id': accountId});

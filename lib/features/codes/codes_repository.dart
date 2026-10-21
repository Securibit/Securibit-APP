import '../../core/env.dart';
import '../../core/json.dart';
import '../../core/platform.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../../src/rust/api/secrets.dart' as core;
import '../../src/rust/api/vault.dart' as vault;
import 'code_models.dart';
import 'secret_handle.dart';
import 'totp/categories.dart';
import 'totp/secret.dart';
import 'totp/totp_params.dart';

// 群組裡我看得到的驗證碼（不含金鑰），原始 JSON 給離線快取
Future<Result<List<Map<String, dynamic>>>> loadGroupAccountsRaw(String gid) => rpc('group_accounts', asMapList, {'gid': gid});

/// 讀回來的金鑰：handles 指向 Rust 記憶體裡的金鑰，sealedCache 是封起來給離線快取存的密文
class SecretsLoad {
  const SecretsLoad({required this.handles, required this.sealedCache, required this.sealed});

  final Map<String, SecretHandle> handles;
  final String? sealedCache;
  // App 鎖定中，金鑰沒有放進記憶體（解鎖後從 sealedCache 放回來）
  final bool sealed;
}

/// 我有「查看金鑰」的全部金鑰（會記一筆「查看金鑰」紀錄）。
/// 由 Rust 直接連 Supabase 取得、解密（加密群組）並留在 Rust 的 scope 裡，金鑰不經過 Dart
Future<Result<SecretsLoad>> loadGroupSecrets(String gid, {required String scope, required bool encrypted}) async {
  var session = supabase.auth.currentSession;
  if (session == null) return const Err('尚未登入');
  if (session.isExpired) {
    try {
      session = (await supabase.auth.refreshSession()).session ?? session;
    } catch (error) {
      return errorResult(error);
    }
  }
  final result = await core.secretsFetch(
    connection: core.SupabaseConnection(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      accessToken: session.accessToken,
      userAgent: AppPlatform.userAgent,
    ),
    gid: gid,
    scope: scope,
    encrypted: encrypted,
  );
  final error = result.error;
  if (error != null) return Err(error, offline: result.offline);
  return Ok(SecretsLoad(handles: SecretHandle.fromMetas(scope, result.metas), sealedCache: result.cache, sealed: result.sealed));
}

/// 從離線快取的密文放回 Rust 的 scope；解不開或 App 鎖定中回傳 null
Map<String, SecretHandle>? restoreGroupSecrets(String scope, String? sealedCache, {required bool encrypted}) {
  if (sealedCache == null) return const {};
  final metas = core.secretsRestore(scope: scope, encrypted: encrypted, cache: sealedCache);
  return metas == null ? null : SecretHandle.fromMetas(scope, metas);
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

// 加密群組：先在 Rust 把金鑰加密成 enc:v1 再送出；沒加密的群組不要加密（資料庫會拒絕存入密文）
// 金鑰是使用者在表單打的，本來就在 Dart；加密群組還沒解鎖時回傳 null
String? _encodeSecret(String secret, {required bool encrypted}) {
  final normalized = normalizeSecret(secret);
  return encrypted ? vault.vaultEncrypt(text: normalized) : normalized;
}

const _vaultLocked = '加密群組已鎖定，請先解鎖';

Future<Result<List<String>>> addGroupAccount(String gid, TotpInput input, {required bool encrypted}) async {
  final secret = _encodeSecret(input.secret, encrypted: encrypted);
  if (secret == null) return const Err(_vaultLocked);
  final item = input.copyWith(name: input.name.trim(), category: normalizeCategories(input.category), secret: secret).toJson();
  return rpc('group_account_add', (data) => data is List ? data.map((e) => '$e').toList() : <String>[], {
    'gid': gid,
    'items': [item],
  });
}

/// 只送要修改的欄位；secret 為 null 代表不修改（避免沒有「查看金鑰」的人誤把金鑰清掉）
Future<Result<void>> updateGroupAccount(String accountId, TotpInput input, {String? secret, required bool encrypted}) async {
  final encoded = secret == null ? null : _encodeSecret(secret, encrypted: encrypted);
  if (secret != null && encoded == null) return const Err(_vaultLocked);
  final patch = <String, dynamic>{
    'name': input.name.trim(),
    'category': normalizeCategories(input.category),
    'digits': input.digits,
    'period': input.period,
    'algorithm': input.algorithm.label,
    'secret': ?encoded,
  };
  return rpcVoid('group_account_update', {'account_id': accountId, 'patch': patch});
}

Future<Result<void>> setPinned(String accountId, bool pinned) =>
    rpcVoid('group_account_update', {'account_id': accountId, 'patch': {'pinned': pinned}});

Future<Result<void>> deleteGroupAccount(String accountId) => rpcVoid('group_account_delete', {'account_id': accountId});

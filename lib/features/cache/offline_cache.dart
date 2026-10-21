import 'dart:convert';

import '../../core/secure_store.dart';

/*
 * 離線快取：最後一次載入的個人資料、群組清單、各群組的驗證碼清單與金鑰，存在系統的安全儲存。
 * 金鑰存的是資料庫裡的原始值：加密群組是 enc:v1 密文，要解鎖後才解得開，不會因為快取而外洩。
 * 只有「查看驗證碼」權限的（伺服器產碼）沒有金鑰，離線時無法顯示。
 */
class OfflineCache {
  const OfflineCache();

  static const _prefix = 'cache:';

  String _profileKey(String uid) => '$_prefix$uid:profile';
  String _groupsKey(String uid) => '$_prefix$uid:groups';
  String _groupKey(String uid, String gid) => '$_prefix$uid:group:$gid';

  Future<void> _write(String key, Object value) async {
    try {
      await secureStore.write(key: key, value: jsonEncode(value));
    } catch (_) {
      // 存不了就只是沒有離線快取
    }
  }

  Future<Object?> _read(String key) async {
    try {
      final raw = await secureStore.read(key: key);
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(String uid, Map<String, dynamic> json) => _write(_profileKey(uid), json);
  Future<Map<String, dynamic>?> loadProfile(String uid) async => _asMap(await _read(_profileKey(uid)));

  Future<void> saveGroups(String uid, List<Map<String, dynamic>> json) => _write(_groupsKey(uid), json);
  Future<List<Map<String, dynamic>>?> loadGroups(String uid) async {
    final value = await _read(_groupsKey(uid));
    return value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : null;
  }

  Future<void> saveGroupData(String uid, String gid, CachedGroupData data) =>
      _write(_groupKey(uid, gid), {'accounts': data.accounts, 'secrets': data.secrets, 'saved_at': data.savedAt});

  Future<CachedGroupData?> loadGroupData(String uid, String gid) async {
    final map = _asMap(await _read(_groupKey(uid, gid)));
    if (map == null) return null;
    final accounts = map['accounts'];
    final secrets = map['secrets'];
    return CachedGroupData(
      accounts: accounts is List ? accounts.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [],
      secrets: secrets is Map ? secrets.map((k, v) => MapEntry('$k', '$v')) : {},
      savedAt: map['saved_at'] is int ? map['saved_at'] as int : 0,
    );
  }

  /// 登出時清掉這個使用者的全部快取
  Future<void> clear(String uid) async {
    try {
      final all = await secureStore.readAll();
      for (final key in all.keys.where((k) => k.startsWith('$_prefix$uid:'))) {
        await secureStore.delete(key: key);
      }
    } catch (_) {
      // 讀不到就沒有東西要清
    }
  }

  Map<String, dynamic>? _asMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;
}

class CachedGroupData {
  const CachedGroupData({required this.accounts, required this.secrets, required this.savedAt});

  final List<Map<String, dynamic>> accounts;
  // { 驗證碼 id: 資料庫裡的原始金鑰 }
  final Map<String, String> secrets;
  final int savedAt;
}

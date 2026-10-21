import '../../core/json.dart';

// profiles.vault：金鑰加密設定（null 代表未啟用），作用在使用者擁有且已開啟加密的群組
class VaultInfo {
  const VaultInfo({required this.v, required this.salt, required this.iterations, required this.check});

  final int v;
  // PBKDF2 的 salt（base64）
  final String salt;
  final int iterations;
  // 用來驗證密碼是否正確：加密後的固定字串
  final String check;

  static VaultInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = asMap(json);
    final salt = asString(map['salt']);
    final check = asString(map['check']);
    if (salt.isEmpty || check.isEmpty) return null;
    return VaultInfo(v: asInt(map['v'], 1), salt: salt, iterations: asInt(map['iterations'], 600000), check: check);
  }
}

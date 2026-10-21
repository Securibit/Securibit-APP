import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/vault/vault_crypto.dart';
import 'package:securibit/features/vault/vault_info.dart';

/*
 * 測試向量由網站自己的 src/lib/vault/crypto.ts 在 node 產生（tool/gen_vault_vector.sh），
 * 證明 App 解得開網站加密的金鑰，App 加密的格式也和網站相同。
 */
const passphrase = '正確的馬 battery staple';
const secret = 'JBSWY3DPEHPK3PXP';
final vault = VaultInfo.fromJson({
  'v': 1,
  'salt': 'LFyhBkLr6c+SV0KV3AoamA==',
  'iterations': 600000,
  'check': 'enc:v1:jiesZSbsHN+23qmf:N5Z5rC7HuOzTU97AnPcQSWsQgN/8pvEwxR4f5uA5OKNauVYq+Q==',
})!;
const cipher = 'enc:v1:CDD1l4lsiRMJPWzR:ttRxv3VBRdnnlJspFq0iaSNAU/xMK2tcg2LtcQfu+Fo=';

void main() {
  test('用密碼解開網站產生的 check 與金鑰', () async {
    final key = await unlockVault(vault, passphrase);
    expect(key, isNotNull);
    expect(await decryptText(key!, cipher), secret);

    // App 加密的結果自己解得回來，格式同網站
    final mine = await encryptText(key, secret);
    expect(mine, startsWith('enc:v1:'));
    final parts = mine.substring(7).split(':');
    expect(base64.decode(parts[0]).length, 12);
    expect(base64.decode(parts[1]).length, utf8.encode(secret).length + 16);
    expect(await decryptText(key, mine), secret);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('密碼錯誤回傳 null', () async {
    expect(await unlockVault(vault, 'wrong'), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('判斷是不是密文', () {
    expect(isEncrypted(cipher), isTrue);
    expect(isEncrypted(secret), isFalse);
  });
}

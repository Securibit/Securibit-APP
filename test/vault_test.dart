import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/vault/vault_info.dart';
import 'package:securibit/src/rust/api/secrets.dart';
import 'package:securibit/src/rust/api/vault.dart';

/*
 * 測試向量由網站自己的 src/lib/vault/crypto.ts 在 node 產生（tool/gen_vault_vector.sh），
 * 證明 Rust 安全核心解得開網站加密的金鑰，加密的格式也和網站相同。
 * 解開的金鑰一直留在 Rust：Dart 這邊只看得到「解鎖成功」，金鑰要透過 secrets* 放進記憶體再取出。
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

Future<VaultUnlockResult> unlock(String value, {String? salt}) =>
    vaultUnlock(salt: salt ?? vault.salt, iterations: vault.iterations, check: vault.check, passphrase: value);

// 把一份原始金鑰放進 Rust（同離線快取還原的路徑），再取出解開後的值
String? roundTrip(String scope, String raw) {
  secretsRestore(scope: scope, encrypted: true, cache: secretsSealLegacy(raw: {'a': raw}));
  return secretsReveal(scope: scope, id: 'a');
}

void main() {
  test('用密碼解開網站產生的 check 與金鑰', () async {
    expect(await unlock(passphrase), VaultUnlockResult.unlocked);
    expect(vaultIsUnlocked(), isTrue);
    expect(roundTrip('vault', cipher), secret);

    // App 加密的結果自己解得回來，格式同網站
    final mine = vaultEncrypt(text: secret)!;
    expect(mine, startsWith('enc:v1:'));
    final parts = mine.substring(7).split(':');
    expect(base64.decode(parts[0]).length, 12);
    expect(base64.decode(parts[1]).length, utf8.encode(secret).length + 16);
    expect(roundTrip('mine', mine), secret);

    // 鎖定：金鑰與加密群組的金鑰一起清掉
    final wrapped = vaultExportWrapped()!;
    expect(wrapped, isNot(contains(secret)));
    vaultLock();
    expect(vaultIsUnlocked(), isFalse);
    expect(secretsReveal(scope: 'vault', id: 'a'), isNull);
    expect(vaultEncrypt(text: secret), isNull);

    // 「在這台裝置記住」的包裝要能解開 check 才採用
    expect(vaultRestoreWrapped(check: 'enc:v1:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA==', wrapped: wrapped), isFalse);
    expect(vaultRestoreWrapped(check: vault.check, wrapped: wrapped), isTrue);
    expect(roundTrip('vault', cipher), secret);
    vaultLock();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('密碼錯誤、設定格式不對', () async {
    expect(await unlock('wrong'), VaultUnlockResult.wrongPassphrase);
    expect(await unlock(passphrase, salt: '@@'), VaultUnlockResult.badInfo);
    expect(vaultIsUnlocked(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('沒解鎖時加密的金鑰保留密文，畫面顯示金鑰錯誤', () {
    final metas = secretsRestore(scope: 'locked', encrypted: true, cache: secretsSealLegacy(raw: {'a': cipher}))!;
    expect(metas.single.valid, isFalse);
    expect(secretsReveal(scope: 'locked', id: 'a'), isNull);
    secretsClearScope(scope: 'locked');
  });

  test('App 鎖定時清掉全部金鑰，解鎖前不接受新的', () {
    final sealed = secretsSealLegacy(raw: {'a': secret});
    expect(sealed, startsWith('dev:v1:'));
    expect(sealed, isNot(contains(secret)));
    expect(secretsRestore(scope: 'plain', encrypted: false, cache: sealed)!.single.valid, isTrue);
    expect(secretsReveal(scope: 'plain', id: 'a'), secret);

    secretsSeal();
    expect(secretsIsSealed(), isTrue);
    expect(secretsReveal(scope: 'plain', id: 'a'), isNull);
    expect(secretsRestore(scope: 'plain', encrypted: false, cache: sealed), isNull);
    secretsUnseal();
    expect(secretsRestore(scope: 'plain', encrypted: false, cache: sealed), isNotNull);
    secretsClearAll();
    expect(secretsReveal(scope: 'plain', id: 'a'), isNull);
  });
}

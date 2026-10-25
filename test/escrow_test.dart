import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/vault/escrow_key.dart';
import 'package:securibit/features/vault/vault_controller.dart';
import 'package:securibit/features/vault/vault_info.dart';
import 'package:securibit/src/rust/api/vault.dart';

/*
 * 加密密碼的備援（esc:v1）：Dart 設定的團隊公鑰經 Rust 封起來的格式。
 * 能不能被團隊私鑰解開由 rust/core/src/escrow.rs 的測試與網站 scripts/escrow.mjs 互通確認
 */
void main() {
  test('用設定裡的公鑰封出 esc:v1 密文', () {
    final envelope = sealEscrow('00000000-0000-4000-8000-000000000001', '正確的馬 battery staple');
    expect(envelope, isNotNull);
    final parts = envelope!.split(':');
    expect(parts.length, 6);
    expect('${parts[0]}:${parts[1]}:', 'esc:v1:');
    expect(parts[2], EscrowKey.keyId);
    expect(base64.decode(parts[3]).length, 65);
    expect(base64.decode(parts[4]).length, 12);
    expect(base64.decode(parts[5]).length, utf8.encode('正確的馬 battery staple').length + 16);
  });

  test('公鑰和金鑰編號不一致時不產生', () {
    expect(
      () => escrowSeal(publicKey: EscrowKey.publicKey, keyId: '0000000000000000', userId: 'u', passphrase: 'p'),
      throwsA(anything),
    );
  });

  test('讀回的加密設定要 v = 1、次數 600,000～5,000,000', () {
    VaultInfo info(int v, int iterations) => VaultInfo(v: v, salt: 'AAAAAAAAAAAAAAAAAAAAAA==', iterations: iterations, check: 'enc:v1:x');
    expect(isSupportedVault(info(1, 600000)), isTrue);
    expect(isSupportedVault(info(1, 5000000)), isTrue);
    expect(isSupportedVault(info(2, 600000)), isFalse);
    expect(isSupportedVault(info(1, 599999)), isFalse);
    expect(isSupportedVault(info(1, 50000000)), isFalse);
  });

  test('Rust 也拒絕範圍外的次數，不推導', () async {
    final result = await vaultUnlock(salt: 'AAAAAAAAAAAAAAAAAAAAAA==', iterations: 100000000, check: 'enc:v1:x', passphrase: 'p');
    expect(result, VaultUnlockResult.unsupported);
  });
}

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'vault_info.dart';

/*
 * 金鑰加密，與網站 src/lib/vault/crypto.ts 逐位元組相容：
 * 使用者密碼 → PBKDF2-SHA256（600,000 次）→ AES-GCM 256。
 * 密文格式 enc:v1:<iv base64>:<密文＋16 位元組 tag base64>，iv 12 位元組。
 * PBKDF2 在 Android 用系統原生實作，其他平台在背景 isolate 計算，60 萬次也不會卡住畫面；
 * AES-GCM 在 iOS / macOS / Android 由 cryptography_flutter 自動改用系統原生實作。
 */

const vaultPrefix = 'enc:v1:';
const vaultIterations = 600000;
const vaultCheckText = 'securibit-vault-check';

final _aes = AesGcm.with256bits();
const _tagLength = 16;

bool isEncrypted(String value) => value.startsWith(vaultPrefix);

Pbkdf2 _pbkdf2(int iterations) {
  final mac = Hmac.sha256();
  if (Platform.isAndroid) {
    return FlutterPbkdf2(
      macAlgorithm: mac,
      iterations: iterations,
      bits: 256,
      fallback: BackgroundPbkdf2(macAlgorithm: mac, iterations: iterations, bits: 256),
    );
  }
  return BackgroundPbkdf2(macAlgorithm: mac, iterations: iterations, bits: 256);
}

// 密碼以 UTF-8 編碼（同 WebCrypto 的 TextEncoder）
Future<SecretKey> deriveVaultKey(String passphrase, List<int> salt, int iterations) =>
    _pbkdf2(iterations).deriveKeyFromPassword(password: passphrase, nonce: salt);

Future<String> encryptText(SecretKey key, String text) async {
  final box = await _aes.encrypt(utf8.encode(text), secretKey: key);
  final cipher = [...box.cipherText, ...box.mac.bytes];
  return '$vaultPrefix${base64.encode(box.nonce)}:${base64.encode(cipher)}';
}

/// 解密失敗（密碼不對、資料損毀）會丟出例外
Future<String> decryptText(SecretKey key, String value) async {
  final parts = value.substring(vaultPrefix.length).split(':');
  if (parts.length < 2) throw const FormatException('密文格式錯誤');
  final iv = base64.decode(parts[0]);
  final cipher = base64.decode(parts[1]);
  if (cipher.length < _tagLength) throw const FormatException('密文格式錯誤');
  final box = SecretBox(
    cipher.sublist(0, cipher.length - _tagLength),
    nonce: iv,
    mac: Mac(cipher.sublist(cipher.length - _tagLength)),
  );
  return utf8.decode(await _aes.decrypt(box, secretKey: key));
}

/// 確認金鑰能解開 check（從裝置讀回來的金鑰也用這個驗證）
Future<bool> verifyVaultKey(VaultInfo info, SecretKey key) async {
  try {
    return await decryptText(key, info.check) == vaultCheckText;
  } catch (_) {
    return false;
  }
}

/// 用密碼解鎖，密碼錯誤回傳 null
Future<SecretKey?> unlockVault(VaultInfo info, String passphrase) async {
  final key = await deriveVaultKey(passphrase, base64.decode(info.salt), info.iterations);
  return await verifyVaultKey(info, key) ? key : null;
}

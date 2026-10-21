import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart' show immutable;

// App 鎖定的方式
enum LockType {
  off('關閉', 0),
  pattern('九宮格圖形', 0),
  pin4('四位數密碼', 4),
  pin6('六位數密碼', 6);

  const LockType(this.label, this.pinLength);

  final String label;
  // 密碼位數；圖形是 0
  final int pinLength;

  bool get isPin => pinLength > 0;

  static LockType fromName(String? name) => LockType.values.firstWhere((t) => t.name == name, orElse: () => LockType.off);
}

// 圖形至少要連接的點數
const minPatternDots = 4;

/// 圖形轉成要雜湊的字串：點的編號 0–8（左上到右下）用 - 連起來
String encodePattern(List<int> dots) => dots.join('-');

/*
 * 圖形與密碼不存原文，只存加鹽的 PBKDF2-SHA256 雜湊。
 * 四位數密碼只有一萬種組合，次數再多也擋不住離線暴力破解，
 * 真正的保護是系統的安全儲存加上 App 裡的錯誤等待，所以次數取適中（2 萬次，手機上約 0.1～0.3 秒），讓解鎖不用等。
 */
const lockIterations = 20000;
const _saltLength = 16;
const _hashBits = 256;

@immutable
class LockHash {
  const LockHash({required this.salt, required this.iterations, required this.hash});

  final List<int> salt;
  final int iterations;
  final List<int> hash;

  Map<String, dynamic> toJson() => {'salt': base64.encode(salt), 'iterations': iterations, 'hash': base64.encode(hash)};

  static LockHash? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final iterations = json['iterations'];
      if (iterations is! int || iterations < 1) return null;
      return LockHash(
        salt: base64.decode(json['salt'] as String),
        iterations: iterations,
        hash: base64.decode(json['hash'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

// Android 用系統原生的 PBKDF2，其他平台在背景 isolate 計算，不會卡住解鎖畫面的動畫
Pbkdf2 _pbkdf2(int iterations) {
  final mac = Hmac.sha256();
  final background = BackgroundPbkdf2(macAlgorithm: mac, iterations: iterations, bits: _hashBits);
  if (Platform.isAndroid) {
    return FlutterPbkdf2(macAlgorithm: mac, iterations: iterations, bits: _hashBits, fallback: background);
  }
  return background;
}

Future<List<int>> _derive(String secret, List<int> salt, int iterations) async {
  final key = await _pbkdf2(iterations).deriveKeyFromPassword(password: secret, nonce: salt);
  return key.extractBytes();
}

/// 產生新的鹽並雜湊圖形或密碼
Future<LockHash> hashLockSecret(String secret, {int iterations = lockIterations, Random? random}) async {
  final rng = random ?? Random.secure();
  final salt = List<int>.generate(_saltLength, (_) => rng.nextInt(256));
  return LockHash(salt: salt, iterations: iterations, hash: await _derive(secret, salt, iterations));
}

/// 檢查輸入的圖形或密碼和存的雜湊是否相同
Future<bool> verifyLockSecret(String secret, LockHash stored) async {
  final hash = await _derive(secret, stored.salt, stored.iterations);
  return constantTimeEquals(hash, stored.hash);
}

/// 固定時間比對：不管哪一個位元組不同，花的時間都一樣
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

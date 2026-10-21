import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../../../src/rust/api/lock.dart' as core;

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
 * 圖形與密碼不存原文，只存加鹽的 PBKDF2-SHA256 雜湊，計算與固定時間比對在 Rust 安全核心（rust/core/src/lock.rs）。
 * 四位數密碼只有一萬種組合，次數再多也擋不住離線暴力破解，
 * 真正的保護是系統的安全儲存加上 App 裡的錯誤等待，所以次數取適中（2 萬次），讓解鎖不用等。
 * 存的格式（salt、iterations、hash 的 base64）和改用 Rust 之前相同，裝置上原本的設定照樣驗證得過。
 */
const lockIterations = 20000;

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

/// 產生新的鹽並雜湊圖形或密碼（在 Rust 的背景執行緒計算，不會卡住解鎖畫面的動畫）
Future<LockHash> hashLockSecret(String secret, {int iterations = lockIterations}) async {
  final hashed = await core.lockHash(secret: secret, iterations: iterations);
  return LockHash(salt: hashed.salt, iterations: hashed.iterations, hash: hashed.hash);
}

/// 檢查輸入的圖形或密碼和存的雜湊是否相同
Future<bool> verifyLockSecret(String secret, LockHash stored) =>
    core.lockVerify(secret: secret, salt: stored.salt, iterations: stored.iterations, hash: stored.hash);

/// 固定時間比對：不管哪一個位元組不同，花的時間都一樣
bool constantTimeEquals(List<int> a, List<int> b) => core.constantTimeEquals(a: a, b: b);

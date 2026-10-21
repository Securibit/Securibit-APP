import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/secure_store.dart';
import 'lock_policy.dart';
import 'lock_secret.dart';

/// 鎖定設定存放的地方；測試時換成記憶體
abstract class LockStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

// 系統的安全儲存（Keychain / Keystore / libsecret）
class SecureLockStorage implements LockStorage {
  const SecureLockStorage();

  @override
  Future<String?> read(String key) => secureStore.read(key: key);

  @override
  Future<void> write(String key, String value) => secureStore.write(key: key, value: value);

  @override
  Future<void> delete(String key) => secureStore.delete(key: key);
}

// 驗證結果：正確、錯誤（attempts 是錯完之後的狀態）、還在等待中
sealed class LockCheck {
  const LockCheck();
}

class LockCheckOk extends LockCheck {
  const LockCheckOk();
}

class LockCheckWrong extends LockCheck {
  const LockCheckWrong(this.attempts);

  final LockAttempts attempts;
}

class LockCheckWaiting extends LockCheck {
  const LockCheckWaiting(this.remaining);

  final Duration remaining;
}

/*
 * App 鎖定（圖形或密碼，可加上生物辨識）：設定和錯誤次數都存在安全儲存。
 * 圖形與密碼只存加鹽雜湊；生物辨識只能當作額外的解鎖方式，一定要先設好圖形或密碼。
 */
class AppLockController extends ChangeNotifier {
  AppLockController({LockStorage storage = const SecureLockStorage(), DateTime Function()? clock, this.iterations = lockIterations})
      : _storage = storage,
        _clock = clock ?? DateTime.now;

  static const _configKey = 'app-lock:config';
  static const _attemptsKey = 'app-lock:attempts';

  final LockStorage _storage;
  final DateTime Function() _clock;
  final int iterations;

  LockType type = LockType.off;
  bool biometric = false;
  LockTimeout timeout = LockTimeout.immediate;
  LockAttempts attempts = LockAttempts.none;
  // 安全儲存讀不到（例如 Linux 沒有 Secret Service）時不能設定鎖定
  bool available = true;

  // 目前畫面是不是鎖著、什麼時候離開 App（由 AppLockGate 維護，不通知）；
  // 選單列用來判斷能不能列出驗證碼：視窗藏起來超過設定的時間，就算還沒回到 App 也當作已鎖定
  bool screenLocked = false;
  DateTime? leftAt;

  LockHash? _hash;
  // 同時只驗證一次，避免連按繞過錯誤次數
  bool _checking = false;

  bool get enabled => type != LockType.off && _hash != null;

  Duration get waitRemaining => attempts.remaining(_clock());

  /// 現在是不是要先解鎖才能看驗證碼
  bool lockedAt(DateTime now) =>
      enabled && (screenLocked || shouldLockAfterBackground(backgroundedAt: leftAt, now: now, timeout: timeout));

  Future<void> load() async {
    try {
      final raw = await _storage.read(_configKey);
      final json = raw == null ? null : jsonDecode(raw);
      if (json is Map) {
        final hash = LockHash.fromJson(json['hash']);
        final stored = LockType.fromName(json['type'] as String?);
        if (hash != null && stored != LockType.off) {
          type = stored;
          _hash = hash;
          biometric = json['biometric'] == true;
          timeout = LockTimeout.fromName(json['timeout'] as String?);
        }
      }
      final rawAttempts = await _storage.read(_attemptsKey);
      attempts = LockAttempts.fromJson(rawAttempts == null ? null : jsonDecode(rawAttempts));
      available = true;
    } catch (_) {
      available = false;
    }
    notifyListeners();
  }

  Future<void> _saveConfig() async {
    final hash = _hash;
    if (type == LockType.off || hash == null) {
      await _storage.delete(_configKey);
      return;
    }
    await _storage.write(
      _configKey,
      jsonEncode({'type': type.name, 'hash': hash.toJson(), 'biometric': biometric, 'timeout': timeout.name}),
    );
  }

  Future<void> _saveAttempts() async {
    if (attempts.failures == 0) {
      await _storage.delete(_attemptsKey);
    } else {
      await _storage.write(_attemptsKey, jsonEncode(attempts.toJson()));
    }
  }

  /// 設定新的圖形或密碼（呼叫前要先確認過目前的）；回傳錯誤訊息，成功為 null
  Future<String?> setLock(LockType newType, String secret) async {
    if (newType == LockType.off) return disable();
    final (oldType, oldHash, oldBiometric) = (type, _hash, biometric);
    try {
      _hash = await hashLockSecret(secret, iterations: iterations);
      type = newType;
      // 新設定時生物辨識預設關閉，要另外打開
      if (oldType == LockType.off) biometric = false;
      await _saveConfig();
    } catch (_) {
      type = oldType;
      _hash = oldHash;
      biometric = oldBiometric;
      notifyListeners();
      return '無法存進這台裝置的安全儲存';
    }
    attempts = LockAttempts.none;
    await _saveAttempts().catchError((_) {});
    notifyListeners();
    return null;
  }

  /// 關閉鎖定（呼叫前要先確認過目前的）
  Future<String?> disable() async {
    try {
      await _storage.delete(_configKey);
    } catch (_) {
      return '無法存進這台裝置的安全儲存';
    }
    type = LockType.off;
    _hash = null;
    biometric = false;
    attempts = LockAttempts.none;
    await _saveAttempts().catchError((_) {});
    notifyListeners();
    return null;
  }

  Future<void> setBiometric(bool value) async {
    if (!enabled) return;
    biometric = value;
    notifyListeners();
    await _saveConfig().catchError((_) {});
  }

  Future<void> setTimeout(LockTimeout value) async {
    timeout = value;
    notifyListeners();
    if (enabled) await _saveConfig().catchError((_) {});
  }

  /// 檢查輸入的圖形或密碼；錯誤會累計次數並存起來
  Future<LockCheck> verify(String secret) async {
    final hash = _hash;
    if (hash == null) return const LockCheckOk();
    final waiting = attempts.remaining(_clock());
    if (waiting > Duration.zero) return LockCheckWaiting(waiting);
    if (_checking) return const LockCheckWaiting(Duration.zero);
    _checking = true;
    try {
      if (await verifyLockSecret(secret, hash)) {
        await resetAttempts();
        return const LockCheckOk();
      }
      attempts = attempts.registerFailure(_clock());
      notifyListeners();
      await _saveAttempts().catchError((_) {});
      return LockCheckWrong(attempts);
    } finally {
      _checking = false;
    }
  }

  /// 解鎖成功（包含生物辨識）後錯誤次數歸零
  Future<void> resetAttempts() async {
    if (attempts.failures == 0) return;
    attempts = LockAttempts.none;
    notifyListeners();
    await _saveAttempts().catchError((_) {});
  }

  /// 忘記密碼：清掉所有鎖定設定與錯誤次數
  Future<void> wipe() async {
    type = LockType.off;
    _hash = null;
    biometric = false;
    timeout = LockTimeout.immediate;
    attempts = LockAttempts.none;
    notifyListeners();
    try {
      await _storage.delete(_configKey);
      await _storage.delete(_attemptsKey);
    } catch (_) {
      // 稍後整個安全儲存會一起清掉
    }
  }
}

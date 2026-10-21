import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/settings/lock/app_lock_controller.dart';
import 'package:securibit/features/settings/lock/lock_policy.dart';
import 'package:securibit/features/settings/lock/lock_secret.dart';
import 'package:securibit/features/settings/lock/pattern_pad.dart';

// 記憶體裡的安全儲存，用來檢查錯誤次數有沒有存下來
class MemoryLockStorage implements LockStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  group('雜湊', () {
    test('正確的密碼通過，錯誤的不通過', () async {
      final hash = await hashLockSecret('482913');
      expect(hash.salt, hasLength(16));
      expect(hash.hash, hasLength(32));
      expect(hash.iterations, lockIterations);
      expect(await verifyLockSecret('482913', hash), isTrue);
      expect(await verifyLockSecret('482914', hash), isFalse);
      expect(await verifyLockSecret('', hash), isFalse);
    });

    test('每次的鹽都不同，存的不是原文', () async {
      final a = await hashLockSecret('1234', iterations: 1000);
      final b = await hashLockSecret('1234', iterations: 1000);
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
      expect(a.toJson().toString(), isNot(contains('1234')));
    });

    test('存成 JSON 再讀回來仍然驗證得過', () async {
      final hash = await hashLockSecret(encodePattern([0, 1, 2, 5, 8]), iterations: 1000);
      final restored = LockHash.fromJson(hash.toJson())!;
      expect(await verifyLockSecret('0-1-2-5-8', restored), isTrue);
      expect(await verifyLockSecret('0-1-2-5', restored), isFalse);
      expect(LockHash.fromJson({'salt': 'x'}), isNull);
      expect(LockHash.fromJson(null), isNull);
    });

    test('固定時間比對', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
      expect(constantTimeEquals([], []), isTrue);
    });
  });

  group('圖形', () {
    test('跨過中間沒選的點會自動補上', () {
      expect(patternConnect([0], 2), [1, 2]);
      expect(patternConnect([0], 8), [4, 8]);
      expect(patternConnect([6], 2), [4, 2]);
      expect(patternConnect([1], 7), [4, 7]);
      // 中間的點已經選過就不再補
      expect(patternConnect([4, 0], 8), [8]);
      // 騎士步沒有中間點
      expect(patternConnect([0], 5), [5]);
      // 已選過的點不能再選
      expect(patternConnect([0, 1], 0), isEmpty);
      expect(patternConnect([], 3), [3]);
    });
  });

  group('錯誤次數與等待', () {
    final now = DateTime(2026, 1, 1, 12);

    test('前 5 次不用等，之後越等越久', () {
      var attempts = LockAttempts.none;
      for (var i = 1; i <= 4; i++) {
        attempts = attempts.registerFailure(now);
        expect(attempts.isWaiting(now), isFalse, reason: '第 $i 次');
        expect(attempts.attemptsBeforeWait, 5 - i);
      }
      attempts = attempts.registerFailure(now);
      expect(attempts.failures, 5);
      expect(attempts.remaining(now), const Duration(seconds: 30));
      expect(attempts.isWaiting(now.add(const Duration(seconds: 29))), isTrue);
      expect(attempts.isWaiting(now.add(const Duration(seconds: 30))), isFalse);

      final expected = [
        const Duration(minutes: 1),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(minutes: 30),
        const Duration(hours: 1),
        const Duration(hours: 1),
      ];
      for (final wait in expected) {
        attempts = attempts.registerFailure(now);
        expect(attempts.remaining(now), wait);
      }
    });

    test('系統時間調回去最多只等這一階', () {
      final attempts = LockAttempts.none.registerFailure(now).registerFailure(now).registerFailure(now).registerFailure(now).registerFailure(now);
      final earlier = now.subtract(const Duration(days: 3));
      expect(attempts.remaining(earlier), const Duration(seconds: 30));
    });

    test('存成 JSON 再讀回來', () {
      final attempts = LockAttempts(failures: 6, lockedUntil: now);
      final restored = LockAttempts.fromJson(attempts.toJson());
      expect(restored.failures, 6);
      expect(restored.lockedUntil, now);
      expect(LockAttempts.fromJson(null).failures, 0);
      expect(LockAttempts.fromJson({'failures': 'x'}).failures, 0);
    });

    test('等待時間的文字', () {
      expect(formatLockWait(const Duration(seconds: 30)), '30 秒');
      expect(formatLockWait(const Duration(milliseconds: 28100)), '29 秒');
      expect(formatLockWait(const Duration(minutes: 1)), '1 分');
      expect(formatLockWait(const Duration(minutes: 4, seconds: 59)), '4 分 59 秒');
      expect(formatLockWait(const Duration(hours: 1)), '1 小時');
    });

    test('錯誤次數存在安全儲存，重開 App 不會歸零', () async {
      var clock = now;
      final storage = MemoryLockStorage();
      final lock = AppLockController(storage: storage, clock: () => clock, iterations: 1000);
      await lock.load();
      expect(await lock.setLock(LockType.pin4, '1234'), isNull);
      expect(lock.enabled, isTrue);

      for (var i = 0; i < 5; i++) {
        expect(await lock.verify('0000'), isA<LockCheckWrong>());
      }
      // 重開 App：讀回來還在等待中，正確的密碼也要等
      final reopened = AppLockController(storage: storage, clock: () => clock, iterations: 1000);
      await reopened.load();
      expect(reopened.type, LockType.pin4);
      expect(reopened.attempts.failures, 5);
      final waiting = await reopened.verify('1234');
      expect(waiting, isA<LockCheckWaiting>());
      expect((waiting as LockCheckWaiting).remaining, const Duration(seconds: 30));

      clock = now.add(const Duration(seconds: 31));
      final wrong = await reopened.verify('9999');
      expect((wrong as LockCheckWrong).attempts.remaining(clock), const Duration(minutes: 1));

      clock = clock.add(const Duration(minutes: 2));
      expect(await reopened.verify('1234'), isA<LockCheckOk>());
      expect(reopened.attempts.failures, 0);
      expect(storage.values.containsKey('app-lock:attempts'), isFalse);
    });

    test('忘記密碼會清掉設定與錯誤次數', () async {
      final storage = MemoryLockStorage();
      final lock = AppLockController(storage: storage, iterations: 1000);
      await lock.load();
      await lock.setLock(LockType.pattern, '0-1-2-5');
      await lock.setBiometric(true);
      await lock.verify('0-3-6-7');
      await lock.wipe();
      expect(lock.enabled, isFalse);
      expect(lock.biometric, isFalse);
      expect(storage.values, isEmpty);
    });
  });

  group('自動鎖定時間', () {
    final at = DateTime(2026, 1, 1, 12);

    test('沒有離開過就不鎖', () {
      expect(shouldLockAfterBackground(backgroundedAt: null, now: at, timeout: LockTimeout.immediate), isFalse);
    });

    test('立即：一離開就鎖', () {
      expect(shouldLockAfterBackground(backgroundedAt: at, now: at, timeout: LockTimeout.immediate), isTrue);
    });

    test('超過設定的時間才鎖', () {
      for (final timeout in [LockTimeout.oneMinute, LockTimeout.fiveMinutes, LockTimeout.fifteenMinutes]) {
        final justBefore = at.add(timeout.duration - const Duration(seconds: 1));
        expect(shouldLockAfterBackground(backgroundedAt: at, now: justBefore, timeout: timeout), isFalse, reason: timeout.label);
        expect(shouldLockAfterBackground(backgroundedAt: at, now: at.add(timeout.duration), timeout: timeout), isTrue, reason: timeout.label);
      }
    });

    test('系統時間被調回去時保守起見鎖定', () {
      final earlier = at.subtract(const Duration(minutes: 10));
      expect(shouldLockAfterBackground(backgroundedAt: at, now: earlier, timeout: LockTimeout.fifteenMinutes), isTrue);
    });
  });
}

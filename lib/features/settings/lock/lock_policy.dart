import 'dart:math';

import 'package:flutter/foundation.dart' show immutable;

/*
 * 錯誤次數與等待：前 5 次錯誤不用等，之後每錯一次等得更久（30 秒、1 分、5 分、15 分、30 分、1 小時）。
 * 錯誤次數和可以再試的時間都存在安全儲存，關掉 App 重開也不會歸零。
 */
const freeLockAttempts = 5;

const _backoff = [
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
];

/// 第 failures 次錯誤之後要等多久；還不用等時是 null
Duration? lockBackoffFor(int failures) {
  if (failures < freeLockAttempts) return null;
  return _backoff[min(failures - freeLockAttempts, _backoff.length - 1)];
}

@immutable
class LockAttempts {
  const LockAttempts({this.failures = 0, this.lockedUntil});

  static const none = LockAttempts();

  // 連續錯誤次數（解鎖成功才歸零）
  final int failures;
  // 在這個時間之前不能再試
  final DateTime? lockedUntil;

  /// 再錯一次之後的狀態
  LockAttempts registerFailure(DateTime now) {
    final next = failures + 1;
    final wait = lockBackoffFor(next);
    return LockAttempts(failures: next, lockedUntil: wait == null ? null : now.add(wait));
  }

  /// 還要等多久才能再試。系統時間被調回去時，最多只等這一階的時間，不會卡住好幾天
  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null || !now.isBefore(until)) return Duration.zero;
    final left = until.difference(now);
    final cap = lockBackoffFor(failures) ?? Duration.zero;
    return left > cap ? cap : left;
  }

  bool isWaiting(DateTime now) => remaining(now) > Duration.zero;

  /// 還能錯幾次才開始要等；已經要等時是 0
  int get attemptsBeforeWait => max(0, freeLockAttempts - failures);

  Map<String, dynamic> toJson() => {
        'failures': failures,
        if (lockedUntil != null) 'locked_until': lockedUntil!.millisecondsSinceEpoch,
      };

  static LockAttempts fromJson(Object? json) {
    if (json is! Map) return none;
    final failures = json['failures'];
    final until = json['locked_until'];
    return LockAttempts(
      failures: failures is int && failures > 0 ? failures : 0,
      lockedUntil: until is int ? DateTime.fromMillisecondsSinceEpoch(until) : null,
    );
  }
}

// 離開 App 多久之後要重新解鎖
enum LockTimeout {
  immediate('立即', Duration.zero),
  oneMinute('1 分鐘', Duration(minutes: 1)),
  fiveMinutes('5 分鐘', Duration(minutes: 5)),
  fifteenMinutes('15 分鐘', Duration(minutes: 15));

  const LockTimeout(this.label, this.duration);

  final String label;
  final Duration duration;

  static LockTimeout fromName(String? name) =>
      LockTimeout.values.firstWhere((t) => t.name == name, orElse: () => LockTimeout.immediate);
}

/// 回到 App 時要不要鎖定：在背景待了 timeout 以上就鎖；系統時間被調回去時保守起見也鎖
bool shouldLockAfterBackground({required DateTime? backgroundedAt, required DateTime now, required LockTimeout timeout}) {
  if (backgroundedAt == null) return false;
  if (timeout == LockTimeout.immediate) return true;
  if (now.isBefore(backgroundedAt)) return true;
  return now.difference(backgroundedAt) >= timeout.duration;
}

/// 等待時間的文字：28 秒、4 分 59 秒、1 小時
String formatLockWait(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes >= 60 && rest == 0 && minutes % 60 == 0) return '${minutes ~/ 60} 小時';
  return rest == 0 ? '$minutes 分' : '$minutes 分 $rest 秒';
}

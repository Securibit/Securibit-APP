import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_lock_controller.dart';
import 'lock_policy.dart';
import 'lock_secret.dart';

/// 圖形或密碼的名稱（「密碼錯誤」「圖形錯誤」）
String lockNoun(LockType type) => type.isPin ? '密碼' : '圖形';

/// 等待中的提示
String lockWaitMessage(Duration remaining) => '錯誤太多次，請等 ${formatLockWait(remaining)}後再試';

/// 驗證失敗後的提示；正確時是 null
String? lockCheckMessage(LockCheck result, LockType type, DateTime now) => switch (result) {
      LockCheckOk() => null,
      LockCheckWaiting(:final remaining) => lockWaitMessage(remaining),
      LockCheckWrong(:final attempts) when attempts.isWaiting(now) => lockWaitMessage(attempts.remaining(now)),
      LockCheckWrong(:final attempts) when attempts.attemptsBeforeWait <= 2 =>
        '${lockNoun(type)}錯誤，再錯 ${attempts.attemptsBeforeWait} 次就要等待',
      LockCheckWrong() => '${lockNoun(type)}錯誤',
    };

/*
 * 錯誤太多次的倒數：等待期間每秒更新提示，時間到就恢復可以輸入。
 * 用在鎖定畫面與設定流程（變更、關閉前要先輸入目前的圖形或密碼）。
 */
mixin LockWaitTicker<T extends StatefulWidget> on State<T> {
  AppLockController get lock;

  Timer? _waitTimer;

  bool get waiting => lock.waitRemaining > Duration.zero;

  /// 等待中就開始倒數（驗證失敗後、畫面打開時呼叫）
  void syncWait() {
    _waitTimer?.cancel();
    if (!waiting) return;
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (!waiting) timer.cancel();
      setState(() {});
    });
  }

  /// 等待中的提示；沒有在等時是 null
  String? get waitMessage => waiting ? lockWaitMessage(lock.waitRemaining) : null;

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

/*
 * 全 App 共用的秒針：每秒對齊整秒更新一次目前時間（毫秒）。
 * 只有驗證碼與倒數圈用 ValueListenableBuilder 監聽它，整頁不會跟著每秒重建。
 * 每次都讀時鐘，不用累加（App 在背景時計時器會變慢，累加會漂移）。
 */
class SecondTicker extends ValueNotifier<int> {
  SecondTicker._() : super(DateTime.now().millisecondsSinceEpoch) {
    _schedule();
  }

  // 全 App 只有一個秒針
  static final shared = SecondTicker._();

  Timer? _timer;

  void _schedule() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer(Duration(milliseconds: 1000 - now % 1000 + 5), () {
      value = DateTime.now().millisecondsSinceEpoch;
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

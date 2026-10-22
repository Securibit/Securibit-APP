import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/rpc.dart';

/*
 * 跟資料庫即時同步（網站 supabase/migrations/0018_realtime.sql）：用 Realtime 訂閱自己在 sync_signals 的列。
 * 群組、驗證碼的資料表不開放直接讀取（一律走 RPC），所以由資料庫的觸發器把「哪裡變了」寫成訊號，
 * 訊號只有 topic 與時間、沒有任何內容；收到後照原本的 RPC 重新讀取，解密、權限與排序都照舊。
 * 短時間內連續的訊號合成一次通知（SyncDebouncer）。斷線重連後補一次全部（斷線期間的訊號收不到）。
 */
class LiveSync {
  LiveSync({required this.onSignals, required this.onReconnected});

  final void Function(SyncBatch batch) onSignals;
  final void Function() onReconnected;

  static const _table = 'sync_signals';

  late final _debouncer = SyncDebouncer(onFlush: onSignals);
  RealtimeChannel? _channel;
  String? _uid;
  bool _subscribed = false;
  // 每次訂閱用不同的 channel 名稱，避免和還在離開中的舊 channel 撞名
  int _seq = 0;

  /// 開始訂閱這位使用者的訊號；已經在訂閱同一位就不重來（換帳號時先取消舊的）
  void start(String uid) {
    if (_uid == uid && _channel != null) return;
    stop();
    _uid = uid;
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid);
    final channel = supabase.channel('sync:$uid:${_seq++}');
    _channel = channel;
    // 只訂閱 INSERT / UPDATE：DELETE 事件不套用 RLS，資料庫也不會為了通知而刪列
    for (final event in const [PostgresChangeEvent.insert, PostgresChangeEvent.update]) {
      channel.onPostgresChanges(
        event: event,
        schema: 'public',
        table: _table,
        filter: filter,
        callback: (payload) {
          if (!identical(_channel, channel)) return;
          final topic = payload.newRecord['topic'];
          if (topic is String) _debouncer.add(topic);
        },
      );
    }
    channel.subscribe((status, _) {
      if (!identical(_channel, channel) || status != RealtimeSubscribeStatus.subscribed) return;
      // 第一次訂閱時剛讀過資料；之後再收到 subscribed 是斷線重連
      if (_subscribed) onReconnected();
      _subscribed = true;
    });
  }

  /// 登出、換帳號時取消訂閱，還沒送出的訊號丟掉
  void stop() {
    _debouncer.cancel();
    final channel = _channel;
    _channel = null;
    _uid = null;
    _subscribed = false;
    if (channel != null) unawaited(_remove(channel));
  }

  static Future<void> _remove(RealtimeChannel channel) async {
    try {
      await supabase.removeChannel(channel);
    } catch (_) {
      // 已經斷線也沒關係，channel 一樣會關掉
    }
  }
}

/// 累積起來的訊號（topic 見 0018_realtime.sql）
class SyncBatch {
  bool groups = false;
  bool invitations = false;
  // { 群組 id: 金鑰也變了 }
  final Map<String, bool> codes = {};

  bool get isEmpty => !groups && !invitations && codes.isEmpty;

  /// 加入一個 topic；不認得的回傳 false
  bool add(String topic) {
    switch (topic) {
      case 'groups':
        groups = true;
        return true;
      case 'invitations':
        invitations = true;
        return true;
    }
    final split = topic.indexOf(':');
    if (split <= 0 || split == topic.length - 1) return false;
    final gid = topic.substring(split + 1);
    switch (topic.substring(0, split)) {
      case 'codes':
        codes[gid] = codes[gid] ?? false;
        return true;
      case 'secrets':
        codes[gid] = true;
        return true;
    }
    return false;
  }
}

/// 訊號停了 delay 才通知一次；一直有訊號時最多等 maxWait
class SyncDebouncer {
  SyncDebouncer({required this.onFlush, this.delay = const Duration(milliseconds: 400), this.maxWait = const Duration(seconds: 2)});

  final void Function(SyncBatch batch) onFlush;
  final Duration delay;
  final Duration maxWait;

  SyncBatch _batch = SyncBatch();
  Timer? _timer;
  DateTime? _firstAt;

  void add(String topic) {
    if (!_batch.add(topic)) return;
    final now = DateTime.now();
    final first = _firstAt ??= now;
    final left = maxWait - now.difference(first);
    _timer?.cancel();
    _timer = Timer(left < delay ? (left.isNegative ? Duration.zero : left) : delay, _flush);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _firstAt = null;
    _batch = SyncBatch();
  }

  void _flush() {
    final batch = _batch;
    cancel();
    if (!batch.isEmpty) onFlush(batch);
  }
}

/// 要重新讀取某個群組的驗證碼（GroupsController 發出，CodesController、選單列接收）
class CodesSignal {
  const CodesSignal(this.groupId, {this.secrets = false, this.confirmed = true});

  final String groupId;
  // 金鑰變了：要重新讀金鑰（會記一筆「查看金鑰」）
  final bool secrets;
  // 資料庫確定有變（即時通知）；false 是輪詢、回到前景時的檢查，不一定有變
  final bool confirmed;
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import 'notification_models.dart';
import 'notifications_repository.dart' as repo;

/// 收件匣的一個分頁（全部或某一類）
class NotificationPage {
  List<AppNotification> items = const [];
  bool loaded = false;
  bool loading = false;
  // 沒有更舊的了
  bool done = false;
  String? error;
}

/// 通知的資料來源（測試換成假的）
abstract class NotificationsSource {
  Future<Result<List<AppNotification>>> list({NotificationCategory? category, int? before, int limit});
  Future<Result<UnreadCounts>> counts();
  Future<Result<void>> markRead({List<int>? ids, NotificationCategory? category});
}

class RpcNotificationsSource implements NotificationsSource {
  const RpcNotificationsSource();

  @override
  Future<Result<List<AppNotification>>> list({NotificationCategory? category, int? before, int limit = repo.notificationPageSize}) =>
      repo.loadNotifications(category: category, before: before, limit: limit);

  @override
  Future<Result<UnreadCounts>> counts() => repo.loadUnreadCounts();

  @override
  Future<Result<void>> markRead({List<int>? ids, NotificationCategory? category}) => repo.markNotificationsRead(ids: ids, category: category);
}

/*
 * 鈴鐺與收件匣（同網站 Navbar 的鈴鐺）：未讀數、四個分頁（全部、系統、帳戶、功能）、標成已讀。
 * - 登入後讀未讀數；收到 sync_signals 的 notifications（GroupsController 轉過來）或背景同步時重新讀
 * - 分頁打開過才讀，往下捲載入更舊的（notifications_list 的 p_before）
 * - 已讀的保留、變淡；點一則標成已讀並打開 link
 * - 新的通知（id 比上次看過的大）交給 onNew（桌面跳系統通知，見 desktop_notifier.dart）
 * 失敗時保留原本的資料，不打斷使用者。
 */
class NotificationsController extends ChangeNotifier {
  NotificationsController({NotificationsSource? source, DateTime Function()? clock})
      : _source = source ?? const RpcNotificationsSource(),
        _clock = clock ?? DateTime.now;

  final NotificationsSource _source;
  final DateTime Function() _clock;

  String? uid;
  UnreadCounts counts = UnreadCounts.zero;
  final Map<NotificationCategory?, NotificationPage> _pages = {};
  // 看過的最新一則（桌面用來找出新的通知）
  int? latestId;
  int _seq = 0;
  bool _refreshing = false;
  bool _again = false;

  /// 有新的通知（登入後第一次讀到的不算，那些給 onFirst）
  void Function(List<AppNotification> fresh)? onNew;

  /// 登入後第一次讀到的最新一頁（桌面開 App 時把上次之後的未讀合併成一則「你有 N 則新通知」）
  void Function(String uid, List<AppNotification> latest)? onFirst;

  NotificationPage page(NotificationCategory? category) => _pages.putIfAbsent(category, NotificationPage.new);

  int get unread => counts.total;

  /// 登入後開始
  Future<void> start(String userId) async {
    if (uid == userId) return;
    clear();
    uid = userId;
    final seq = _seq;
    final results = await Future.wait([_source.counts(), _source.list(limit: repo.notificationPageSize)]);
    if (seq != _seq) return;
    if (results[0] case Ok(:final data)) counts = data as UnreadCounts;
    if (results[1] case Ok(:final data)) {
      final items = data as List<AppNotification>;
      _apply(null, items, replace: true);
      latestId = _maxId(items);
      onFirst?.call(userId, items);
    }
    notifyListeners();
  }

  /// 登出
  void clear() {
    _seq++;
    uid = null;
    counts = UnreadCounts.zero;
    _pages.clear();
    latestId = null;
    notifyListeners();
  }

  /// 收到即時通知或背景同步：重新讀未讀數與讀過的分頁的第一頁，找出新的通知
  Future<void> refresh() async {
    if (uid == null) return;
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _again = false;
        await _refresh();
      } while (_again && uid != null);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refresh() async {
    final seq = _seq;
    final categories = {null, ..._pages.keys.where((c) => _pages[c]!.loaded)};
    final countsFuture = _source.counts();
    final lists = {for (final c in categories) c: _source.list(category: c, limit: repo.notificationPageSize)};
    final countResult = await countsFuture;
    if (seq != _seq) return;
    if (countResult case Ok(:final data)) counts = data;
    for (final entry in lists.entries) {
      final result = await entry.value;
      if (seq != _seq) return;
      if (result case Ok(:final data)) {
        if (entry.key == null) _detectNew(data);
        _apply(entry.key, data, replace: false);
      }
    }
    notifyListeners();
  }

  void _detectNew(List<AppNotification> items) {
    final before = latestId;
    final max = _maxId(items);
    if (max != null && (before == null || max > before)) latestId = max;
    if (before == null) return;
    final fresh = items.where((n) => n.id > before && !n.read).toList();
    if (fresh.isNotEmpty) onNew?.call(fresh);
  }

  static int? _maxId(List<AppNotification> items) => items.isEmpty ? null : items.map((n) => n.id).reduce((a, b) => a > b ? a : b);

  // replace：第一次讀（換掉）；否則把最新的一頁合併進已經有的（保留已經載入的舊通知）
  void _apply(NotificationCategory? category, List<AppNotification> fresh, {required bool replace}) {
    final page = this.page(category);
    page.error = null;
    if (replace || !page.loaded) {
      page.items = fresh;
      page.done = fresh.length < repo.notificationPageSize;
    } else {
      final ids = {for (final n in fresh) n.id};
      final oldest = fresh.isEmpty ? null : fresh.last.id;
      // 第一頁範圍內的用新的（合併的通知會更新內容與時間），更舊的留著
      final older = page.items.where((n) => !ids.contains(n.id) && (oldest == null || n.id < oldest));
      page.items = [...fresh, ...older];
    }
    page.loaded = true;
  }

  /// 打開分頁時讀第一頁（讀過就不重讀）
  Future<void> open(NotificationCategory? category) async {
    final page = this.page(category);
    if (page.loaded || page.loading) return;
    await _load(category, before: null);
  }

  /// 往下捲到底：載入更舊的
  Future<void> loadMore(NotificationCategory? category) async {
    final page = this.page(category);
    if (!page.loaded || page.loading || page.done || page.items.isEmpty) return;
    await _load(category, before: page.items.last.id);
  }

  Future<void> _load(NotificationCategory? category, {required int? before}) async {
    final seq = _seq;
    final page = this.page(category);
    page.loading = true;
    page.error = null;
    notifyListeners();
    final result = await _source.list(category: category, before: before, limit: repo.notificationPageSize);
    if (seq != _seq) return;
    page.loading = false;
    switch (result) {
      case Ok(:final data):
        if (before == null) {
          _apply(category, data, replace: true);
          if (category == null) {
            final max = _maxId(data);
            if (max != null && (latestId == null || max > latestId!)) latestId = max;
          }
        } else {
          final ids = {for (final n in page.items) n.id};
          page.items = [...page.items, ...data.where((n) => !ids.contains(n.id))];
          page.done = data.length < repo.notificationPageSize;
        }
      case Err(:final message):
        page.error = message;
    }
    notifyListeners();
  }

  /// 標成已讀（點了一則）；畫面先變，失敗時下次同步會還原
  Future<void> markRead(AppNotification item) async {
    if (item.read) return;
    final marked = _markLocally((n) => n.id == item.id);
    // 這一則還沒載入到任何分頁時也要減
    counts = counts.minus(marked.isEmpty ? [item] : marked);
    notifyListeners();
    await _source.markRead(ids: [item.id]);
  }

  /// 這一頁（category 是 null 時為全部）全部標成已讀，包括還沒載入的
  Future<Result<void>> markAllRead(NotificationCategory? category) async {
    _markLocally((n) => category == null || n.category == category);
    counts = switch (category) {
      null => UnreadCounts.zero,
      NotificationCategory.system => UnreadCounts(total: counts.total - counts.system, account: counts.account, feature: counts.feature),
      NotificationCategory.account => UnreadCounts(total: counts.total - counts.account, system: counts.system, feature: counts.feature),
      NotificationCategory.feature => UnreadCounts(total: counts.total - counts.feature, system: counts.system, account: counts.account),
    };
    notifyListeners();
    final result = await _source.markRead(category: category);
    if (result is Err) unawaited(refresh());
    return result;
  }

  // 已載入的通知裡符合的標成已讀；回傳原本未讀的那幾則（同一則在不同分頁只算一次）
  List<AppNotification> _markLocally(bool Function(AppNotification n) test) {
    final now = _clock();
    final marked = <int, AppNotification>{};
    for (final page in _pages.values) {
      page.items = [
        for (final n in page.items)
          if (!n.read && test(n)) _mark(n, now, marked) else n,
      ];
    }
    return marked.values.toList();
  }

  static AppNotification _mark(AppNotification n, DateTime now, Map<int, AppNotification> marked) {
    marked[n.id] = n;
    return n.markRead(now);
  }
}

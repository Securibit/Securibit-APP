import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/result.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/notifications/desktop_notifier.dart';
import 'package:securibit/features/notifications/notification_inbox.dart';
import 'package:securibit/features/notifications/notification_link.dart';
import 'package:securibit/features/notifications/notification_models.dart';
import 'package:securibit/features/notifications/notification_settings_page.dart';
import 'package:securibit/features/notifications/notifications_controller.dart';
import 'package:securibit/features/sync/live_sync.dart';

// 通知：分類與開關的預設值、通知列的解析、連結、收件匣的分頁與已讀、桌面系統通知要跳哪些、通知設定頁

Map<String, dynamic> _row(int id, {String category = 'feature', String type = 'group_invite', String? read, String push = 'sent', String? link, String? at}) => {
      'id': id,
      'category': category,
      'type': type,
      'title': '通知 $id',
      'body': '內容 $id',
      'link': link,
      'data': {'group_id': 'g'},
      'created_at': at ?? '2026-10-26T01:00:00Z',
      'read_at': read,
      'push_state': push,
    };

AppNotification _n(int id, {String category = 'feature', bool read = false, String push = 'sent', String type = 'group_invite'}) =>
    AppNotification.fromJson(_row(id, category: category, type: type, read: read ? '2026-10-26T02:00:00Z' : null, push: push))!;

/// 假的資料來源：items 由新到舊（id 大的在前），依 category 與 before 切頁
class FakeSource implements NotificationsSource {
  FakeSource(this.items, {UnreadCounts? counts}) : _counts = counts;

  List<AppNotification> items;
  final UnreadCounts? _counts;
  final List<({List<int>? ids, NotificationCategory? category})> marked = [];
  bool failList = false;

  @override
  Future<Result<UnreadCounts>> counts() async {
    final c = _counts;
    if (c != null) return Ok(c);
    int count(NotificationCategory cat) => items.where((n) => !n.read && n.category == cat).length;
    final s = count(NotificationCategory.system), a = count(NotificationCategory.account), f = count(NotificationCategory.feature);
    return Ok(UnreadCounts(total: s + a + f, system: s, account: a, feature: f));
  }

  @override
  Future<Result<List<AppNotification>>> list({NotificationCategory? category, int? before, int limit = 30}) async {
    if (failList) return const Err('無法連線到伺服器，請檢查網路連線', offline: true);
    final rows = items.where((n) => (category == null || n.category == category) && (before == null || n.id < before)).take(limit).toList();
    return Ok(rows);
  }

  @override
  Future<Result<void>> markRead({List<int>? ids, NotificationCategory? category}) async {
    marked.add((ids: ids, category: category));
    return const Ok(null);
  }
}

void main() {
  group('通知種類與開關', () {
    test('19 種，順序同資料庫：系統 4、帳戶 5、功能 10', () {
      expect(notificationTypes.length, 19);
      expect(notificationTypes.first.type, 'announce_important');
      expect(notificationTypes.last.type, 'codes_changed');
      int count(NotificationCategory c) => notificationTypes.where((d) => d.category == c).length;
      expect(count(NotificationCategory.system), 4);
      expect(count(NotificationCategory.account), 5);
      expect(count(NotificationCategory.feature), 10);
      expect(notificationTypes.map((d) => d.type).toSet().length, 19);
    });

    test('預設：只有「群組驗證碼有變動」是關的；只有重要公告不能關', () {
      const prefs = NotificationPrefs();
      for (final def in notificationTypes) {
        expect(prefs.enabled(def.type), def.type != 'codes_changed', reason: def.type);
      }
      expect(notificationTypes.where((d) => d.locked).map((d) => d.type), ['announce_important']);
    });

    test('重要公告不能關，不認得的種類不動', () {
      final prefs = const NotificationPrefs().set('announce_important', false).set('unknown', false);
      expect(prefs.enabled('announce_important'), isTrue);
      expect(prefs.overrides, isEmpty);
    });

    test('改回預設值時不留在 overrides', () {
      final off = const NotificationPrefs().set('new_login', false);
      expect(off.enabled('new_login'), isFalse);
      expect(off.overrides, {'new_login': false});
      expect(off.set('new_login', true).overrides, isEmpty);
      final codes = const NotificationPrefs().set('codes_changed', true);
      expect(codes.overrides, {'codes_changed': true});
    });

    test('解析 notification_prefs_get 的陣列；資料庫說重要公告關掉也不理', () {
      final prefs = NotificationPrefs.fromJson([
        {'type': 'announce_important', 'category': 'system', 'enabled': false, 'default': true, 'locked': true},
        {'type': 'announce_promo', 'category': 'system', 'enabled': false, 'default': true, 'locked': false},
        {'type': 'codes_changed', 'category': 'feature', 'enabled': false, 'default': false, 'locked': false},
        {'type': 'member_added', 'category': 'feature', 'enabled': 'no', 'default': true, 'locked': false},
      ]);
      expect(prefs.enabled('announce_important'), isTrue);
      expect(prefs.enabled('announce_promo'), isFalse);
      expect(prefs.enabled('codes_changed'), isFalse);
      expect(prefs.enabled('member_added'), isTrue);
      expect(prefs.overrides, {'announce_promo': false});
    });
  });

  group('通知列', () {
    test('解析 notifications_list 的一筆', () {
      final n = AppNotification.fromJson(_row(7, category: 'account', type: 'new_login', link: '/me/activity', push: 'skipped'))!;
      expect(n.id, 7);
      expect(n.category, NotificationCategory.account);
      expect(n.title, '通知 7');
      expect(n.link, '/me/activity');
      expect(n.read, isFalse);
      expect(n.skipped, isTrue);
    });

    test('沒有 id 或時間的不要；不認得的類別依 type 推回來', () {
      expect(AppNotification.fromJson({'id': 1}), isNull);
      final n = AppNotification.fromJson({..._row(2), 'category': 'weird', 'type': 'new_login'})!;
      expect(n.category, NotificationCategory.account);
    });

    test('連結只接受站內路徑', () {
      expect(safeNotificationLink('/groups/abc'), '/groups/abc');
      expect(safeNotificationLink('/'), '/');
      expect(safeNotificationLink('//evil.example'), isNull);
      expect(safeNotificationLink('/a//b'), isNull);
      expect(safeNotificationLink('/\\evil'), isNull);
      expect(safeNotificationLink('https://evil.example'), isNull);
      expect(safeNotificationLink('/a b'), isNull);
      expect(safeNotificationLink('/a\nb'), isNull);
      expect(safeNotificationLink(''), isNull);
      expect(safeNotificationLink(null), isNull);
    });

    test('未讀數', () {
      final counts = UnreadCounts.fromJson({'total': 3, 'system': 1, 'account': 0, 'feature': 2});
      expect(counts.of(null), 3);
      expect(counts.of(NotificationCategory.feature), 2);
      expect(UnreadCounts.fromJson({'system': 1, 'feature': 1}).total, 2);
      final after = counts.minus([_n(1), _n(2, read: true), _n(3, category: 'system')]);
      expect(after, const UnreadCounts(total: 1, system: 0, account: 0, feature: 1));
      expect(const UnreadCounts().minus([_n(1)]), UnreadCounts.zero);
    });

    test('時間的寫法同網站', () {
      final now = DateTime(2026, 10, 26, 12);
      expect(formatNotificationTime(now.subtract(const Duration(seconds: 30)), now), '剛剛');
      expect(formatNotificationTime(now.subtract(const Duration(minutes: 5)), now), '5 分鐘前');
      expect(formatNotificationTime(now.subtract(const Duration(hours: 3)), now), '3 小時前');
      expect(formatNotificationTime(now.subtract(const Duration(days: 2)), now), '2 天前');
      expect(formatNotificationTime(DateTime(2026, 3, 4), now), '3月4日');
      expect(formatNotificationTime(DateTime(2025, 3, 4), now), '2025年3月4日');
      // 時鐘不準（通知比現在晚）也是剛剛
      expect(formatNotificationTime(now.add(const Duration(minutes: 2)), now), '剛剛');
    });
  });

  group('通知的連結在 App 裡打開哪裡', () {
    test('資料庫會產生的路徑', () {
      expect(notificationTarget(null), const InboxTarget());
      expect(notificationTarget('/'), const HomeTarget());
      expect(notificationTarget('/groups'), const GroupTarget(null));
      expect(notificationTarget('/groups/1b2c-3d'), const GroupTarget('1b2c-3d'));
      expect(notificationTarget('/me/update_info'), const PageTarget(AppPage.settings));
      expect(notificationTarget('/me/activity'), const PageTarget(AppPage.activity));
    });

    test('公告可能填的其他路徑', () {
      expect(notificationTarget('/invite/ABCD1234'), const InviteTarget('ABCD1234'));
      expect(notificationTarget('/u/someone'), const UserTarget('someone'));
      expect(notificationTarget('/admin/users'), const PageTarget(AppPage.admin));
      expect(notificationTarget('/download?os=mac'), const WebTarget('/download?os=mac'));
      expect(notificationTarget('/privacy'), const WebTarget('/privacy'));
      // 不是站內路徑就只打開收件匣
      expect(notificationTarget('https://evil.example/invite/x'), const InboxTarget());
      expect(notificationTarget('/invite/'), const InboxTarget());
    });
  });

  group('收件匣', () {
    test('登入後讀未讀數與第一頁，第一次讀到的交給 onFirst', () async {
      final source = FakeSource([_n(3), _n(2, category: 'system'), _n(1, read: true)]);
      final controller = NotificationsController(source: source);
      List<AppNotification>? first;
      controller.onFirst = (uid, items) => first = items;
      await controller.start('u1');
      expect(controller.unread, 2);
      expect(controller.page(null).items.map((n) => n.id), [3, 2, 1]);
      expect(controller.page(null).done, isTrue);
      expect(first?.length, 3);
      expect(controller.latestId, 3);
    });

    test('分頁：打開類別才讀，往下捲載入更舊的', () async {
      final items = [for (var id = 70; id >= 1; id--) _n(id, category: id.isEven ? 'feature' : 'account')];
      final source = FakeSource(items);
      final controller = NotificationsController(source: source);
      await controller.start('u1');
      expect(controller.page(null).items.length, 30);
      expect(controller.page(null).done, isFalse);
      await controller.loadMore(null);
      expect(controller.page(null).items.length, 60);
      await controller.loadMore(null);
      expect(controller.page(null).items.length, 70);
      expect(controller.page(null).done, isTrue);

      expect(controller.page(NotificationCategory.account).loaded, isFalse);
      await controller.open(NotificationCategory.account);
      final account = controller.page(NotificationCategory.account).items;
      expect(account.length, 30);
      expect(account.every((n) => n.category == NotificationCategory.account), isTrue);
    });

    test('點一則標成已讀：所有分頁一起變、數字減一', () async {
      final source = FakeSource([_n(2), _n(1, category: 'system')]);
      final controller = NotificationsController(source: source);
      await controller.start('u1');
      await controller.open(NotificationCategory.feature);
      await controller.markRead(controller.page(null).items.first);
      expect(controller.page(null).items.first.read, isTrue);
      expect(controller.page(NotificationCategory.feature).items.first.read, isTrue);
      expect(controller.counts, const UnreadCounts(total: 1, system: 1));
      expect(source.marked.single.ids, [2]);
    });

    test('全部標為已讀只標這一類（包括還沒載入的）', () async {
      final source = FakeSource([_n(3), _n(2, category: 'system')], counts: const UnreadCounts(total: 10, system: 4, account: 1, feature: 5));
      final controller = NotificationsController(source: source);
      await controller.start('u1');
      await controller.markAllRead(NotificationCategory.feature);
      expect(controller.counts, const UnreadCounts(total: 5, system: 4, account: 1));
      expect(controller.page(null).items.firstWhere((n) => n.id == 3).read, isTrue);
      expect(controller.page(null).items.firstWhere((n) => n.id == 2).read, isFalse);
      expect(source.marked.single.category, NotificationCategory.feature);
      await controller.markAllRead(null);
      expect(controller.counts, UnreadCounts.zero);
    });

    test('收到即時通知：新的交給 onNew，已經載入的舊通知留著', () async {
      final source = FakeSource([for (var id = 40; id >= 1; id--) _n(id)]);
      final controller = NotificationsController(source: source);
      await controller.start('u1');
      await controller.loadMore(null);
      expect(controller.page(null).items.length, 40);
      List<AppNotification>? fresh;
      controller.onNew = (items) => fresh = items;
      source.items = [_n(42), _n(41, read: true), ...source.items];
      await controller.refresh();
      expect(fresh?.map((n) => n.id), [42]);
      expect(controller.latestId, 42);
      expect(controller.page(null).items.length, 42);
      expect(controller.page(null).items.first.id, 42);
      // 沒有新的就不叫
      fresh = null;
      await controller.refresh();
      expect(fresh, isNull);
    });

    test('讀不到時保留原本的資料；登出清掉', () async {
      final source = FakeSource([_n(1)]);
      final controller = NotificationsController(source: source);
      await controller.start('u1');
      source.failList = true;
      await controller.refresh();
      expect(controller.page(null).items.length, 1);
      controller.clear();
      expect(controller.uid, isNull);
      expect(controller.unread, 0);
      expect(controller.page(null).items, isEmpty);
    });

    test('sync_signals 的 notifications topic', () {
      final batch = SyncBatch();
      expect(batch.add('notifications'), isTrue);
      expect(batch.notifications, isTrue);
      expect(batch.isEmpty, isFalse);
    });
  });

  group('桌面系統通知', () {
    test('關掉的（skipped）、已讀的、看過的不跳', () {
      final alerts = desktopAlerts([_n(5), _n(4, push: 'skipped'), _n(3, read: true), _n(2)], after: 2);
      expect(alerts.map((a) => a.id), ['n5']);
      expect(alerts.single.title, '通知 5');
    });

    test('太多則合併成一則；開 App 時一定合併', () {
      final many = [for (var id = 10; id >= 6; id--) _n(id)];
      final alerts = desktopAlerts(many);
      expect(alerts.single.title, '你有 5 則新通知');
      expect(alerts.single.link, isNull);
      expect(desktopAlerts(many.take(2).toList()).length, 2);
      expect(desktopAlerts(many.take(2).toList(), summary: true).single.title, '你有 2 則新通知');
      // 只有一則就直接顯示那一則
      expect(desktopAlerts([_n(1)], summary: true).single.title, '通知 1');
      expect(desktopAlerts([_n(1, push: 'skipped')], summary: true), isEmpty);
    });
  });

  group('通知設定頁', () {
    Future<List<Map<String, bool>>> pump(WidgetTester tester, {bool failSave = false}) async {
      final saved = <Map<String, bool>>[];
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: NotificationSettingsPage(
          inDialog: false,
          load: () async => const Ok(NotificationPrefs({'announce_promo': false})),
          save: (changes) async {
            saved.add(changes);
            if (failSave) return const Err('發送太頻繁');
            var prefs = const NotificationPrefs({'announce_promo': false});
            changes.forEach((type, on) => prefs = prefs.set(type, on));
            return Ok(prefs);
          },
        ),
      ));
      await tester.pumpAndSettle();
      return saved;
    }

    // 名稱所在那一列的開關（由近到遠找第一個含開關的 Row）
    Switch switchOf(WidgetTester tester, String label) {
      final rows = find.ancestor(of: find.text(label), matching: find.byType(Row)).evaluate();
      for (final row in rows) {
        final found = find.descendant(of: find.byWidget(row.widget), matching: find.byType(Switch));
        if (found.evaluate().length == 1) return tester.widget<Switch>(found);
      }
      throw StateError('找不到「$label」的開關');
    }

    testWidgets('三組開關；重要公告鎖住；改了就只送那一種', (tester) async {
      final saved = await pump(tester);
      expect(find.text('系統'), findsOneWidget);
      expect(find.text('帳戶'), findsOneWidget);
      expect(find.text('功能'), findsOneWidget);
      expect(find.textContaining('鈴鐺裡還是看得到'), findsOneWidget);

      final important = switchOf(tester, '重要公告');
      expect(important.value, isTrue);
      expect(important.onChanged, isNull);
      expect(switchOf(tester, '推廣').value, isFalse);
      expect(switchOf(tester, '群組驗證碼有變動').value, isFalse);

      switchOf(tester, '新的登入').onChanged!(false);
      await tester.pumpAndSettle();
      expect(saved, [
        {'new_login': false},
      ]);
      expect(switchOf(tester, '新的登入').value, isFalse);
    });

    testWidgets('存不進去時改回來並說明', (tester) async {
      await pump(tester, failSave: true);
      switchOf(tester, '群組邀請').onChanged!(false);
      await tester.pumpAndSettle();
      expect(find.text('無法儲存通知設定'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(switchOf(tester, '群組邀請').value, isTrue);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/web_pages.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/sliding_selection.dart';
import '../admin/admin_page.dart';
import '../../core/widgets/avatar.dart';
import '../groups/group_models.dart';
import '../groups/groups_controller.dart';
import '../groups/manage/group_entry.dart';
import '../profile/profile_entry.dart';
import '../settings/settings_view.dart';
import 'notification_link.dart';
import 'notification_models.dart';
import 'notification_settings_page.dart';
import 'notifications_controller.dart';

/// 鈴鐺：有未讀時右上角帶紅色數字（同網站），點了打開收件匣
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = context.select<NotificationsController, int>((n) => n.unread);
    return IconButton(
      tooltip: count > 0 ? '通知，$count 則未讀' : '通知',
      onPressed: () => openInbox(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: colors.alarm,
        textColor: Colors.white,
        child: Icon(Icons.notifications_rounded, color: colors.ink),
      ),
    );
  }
}

// 收件匣已經開著（點系統通知、鈴鐺不會再開一個）
bool _inboxOpen = false;

/// 收件匣：寬視窗用對話框（同設定），窄螢幕整頁
Future<void> openInbox(BuildContext context) async {
  if (_inboxOpen) return;
  _inboxOpen = true;
  try {
    if (MediaQuery.sizeOf(context).width >= 720) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720), child: const NotificationInbox()),
        ),
      );
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationInbox()));
    }
  } finally {
    _inboxOpen = false;
  }
}

/// 打開通知的 link 對應的畫面（收件匣點一則、點系統通知、點推播）
Future<void> openNotificationLink(BuildContext context, String? link) async {
  final target = notificationTarget(link);
  switch (target) {
    case InboxTarget():
      await openInbox(context);
    case HomeTarget():
      final groups = context.read<GroupsController>();
      final mine = groups.groups?.where((g) => g.isDefault).firstOrNull;
      if (mine != null) groups.select(mine.id);
    case InviteTarget(:final code):
      await openJoinByInvite(context, code: code);
    case GroupTarget(:final groupId):
      final groups = context.read<GroupsController>();
      // 群組列表（收到的邀請）：收件匣最上面就有邀請可以接受或拒絕
      if (groupId == null) {
        await openInbox(context);
        return;
      }
      if (groups.groups?.any((g) => g.id == groupId) ?? false) {
        groups.select(groupId);
      } else {
        // 被移出、群組被刪掉
        showToast(context, '你已經不在這個群組，或群組已被刪除');
      }
    case UserTarget(:final userId):
      await openUserProfile(context, userId);
    case PageTarget(page: AppPage.settings):
      await openSettings(context);
    case PageTarget(page: AppPage.activity):
      await openActivity(context);
    case PageTarget(page: AppPage.admin):
      await openAdmin(context);
    case WebTarget(:final path):
      try {
        await openWebPage(path);
      } catch (_) {
        // 打不開瀏覽器就算了
      }
  }
}

/// 時間（同網站的 relativeTime）：剛剛、5 分鐘前、3 小時前、2 天前，一週以上顯示日期
String formatNotificationTime(DateTime time, DateTime now) {
  final diff = now.difference(time);
  final seconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
  if (seconds < 60) return '剛剛';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分鐘前';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours 小時前';
  final days = hours ~/ 24;
  if (days < 7) return '$days 天前';
  return time.year == now.year ? '${time.month}月${time.day}日' : '${time.year}年${time.month}月${time.day}日';
}

/*
 * 收件匣（同網站鈴鐺的面板）：分頁「全部、系統、帳戶、功能」，每個分頁帶未讀數；
 * 「全部」與「功能」的最上面列出還沒處理的群組邀請，可以直接接受或拒絕；
 * 已讀的保留、變淡；「全部標為已讀」標這個分頁的全部；點一則標成已讀並打開 link；往下捲載入更多；
 * 最下面是「通知設定」。
 */
class NotificationInbox extends StatefulWidget {
  const NotificationInbox({super.key});

  @override
  State<NotificationInbox> createState() => _NotificationInboxState();
}

const _tabs = <NotificationCategory?>[null, NotificationCategory.system, NotificationCategory.account, NotificationCategory.feature];

class _NotificationInboxState extends State<NotificationInbox> {
  late final NotificationsController _notifications = context.read<NotificationsController>();
  NotificationCategory? _tab;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_notifications.open(_tab));
    // 打開時順便更新一次
    unawaited(_notifications.refresh());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) unawaited(_notifications.loadMore(_tab));
  }

  void _select(NotificationCategory? tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_notifications.open(tab));
  }

  Future<void> _markAll() async {
    final result = await _notifications.markAllRead(_tab);
    if (!mounted) return;
    if (result case Err(:final message)) await showErrorDialog(context, '標為已讀失敗', message);
  }

  Future<void> _open(AppNotification item) async {
    unawaited(_notifications.markRead(item));
    final target = notificationTarget(item.link);
    // 沒有連結、或連到群組列表（邀請就在最上面）：留在收件匣
    if (target is InboxTarget || target == const GroupTarget(null)) return;
    await _leaveAndOpen((home) => openNotificationLink(home, item.link));
  }

  // 先關掉收件匣，回到原本的畫面再打開
  Future<void> _leaveAndOpen(Future<void> Function(BuildContext home) open) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await WidgetsBinding.instance.endOfFrame;
    final home = navigator.context;
    if (home.mounted) await open(home);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notifications = context.watch<NotificationsController>();
    final invitations = context.select<GroupsController, List<Invitation>>((g) => g.invitations);
    final page = notifications.page(_tab);
    final unread = notifications.counts.of(_tab);
    final now = DateTime.now();
    final showInvitations = invitations.isNotEmpty && (_tab == null || _tab == NotificationCategory.feature);

    final rows = <Widget>[
      if (showInvitations)
        for (final invitation in invitations) _InvitationRow(key: ValueKey('i${invitation.id}'), invitation: invitation, onAccepted: _leaveAndOpen),
      if (!page.loaded && page.error == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator.adaptive()))
      else if (!page.loaded)
        _Message(
          title: '無法載入通知',
          message: page.error!,
          action: TextButton(onPressed: () => unawaited(_notifications.open(_tab)), child: const Text('重試')),
        )
      else if (page.items.isEmpty && !showInvitations)
        const _Message(title: '沒有通知')
      else ...[
        for (final item in page.items)
          NotificationTile(key: ValueKey(item.id), item: item, time: formatNotificationTime(item.createdAt, now), onTap: () => _open(item)),
        if (!page.done)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: page.error != null
                  ? TextButton(onPressed: () => unawaited(_notifications.loadMore(_tab)), child: const Text('載入失敗，重試'))
                  : const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          TextButton(onPressed: unread > 0 ? _markAll : null, child: const Text('全部標為已讀')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SlidingSelection(
                direction: Axis.horizontal,
                selectedIndex: _tabs.indexOf(_tab),
                color: colors.surface1,
                spacing: 2,
                children: [
                  for (final tab in _tabs)
                    _InboxTab(
                      label: tab?.label ?? '全部',
                      count: notifications.counts.of(tab),
                      selected: tab == _tab,
                      onTap: () => _select(tab),
                    ),
                ],
              ),
            ),
            Divider(height: 0.5, color: colors.line.withValues(alpha: 0.6)),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: _notifications.refresh,
                child: ListView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: rows,
                ),
              ),
            ),
            Divider(height: 0.5, color: colors.line.withValues(alpha: 0.6)),
            TextButton(
              onPressed: () => _leaveAndOpen(openNotificationSettings),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: const RoundedRectangleBorder(),
                textStyle: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600),
              ),
              child: const Text('通知設定'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxTab extends StatelessWidget {
  const _InboxTab({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.ink : colors.inkMuted;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: color)),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w700, color: colors.alarm),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 收件匣的一則：未讀的標題粗、右邊有綠點；已讀的整則變淡
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.time, required this.onTap});

  final AppNotification item;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final important = item.type == 'announce_important';
    final icon = important
        ? Icons.error_rounded
        : switch (item.category) {
            NotificationCategory.system => Icons.campaign_rounded,
            NotificationCategory.account => Icons.admin_panel_settings_rounded,
            NotificationCategory.feature => Icons.groups_rounded,
          };
    return Opacity(
      opacity: item.read ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: colors.surface1, shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: important ? colors.alarm : colors.inkMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(fontSize: AppText.body, fontWeight: item.read ? FontWeight.w500 : FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(time, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                          ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!item.read) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.brand, shape: BoxShape.circle)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 還沒處理的群組邀請（同網站鈴鐺面板最上面）：接受後切到那個群組
class _InvitationRow extends StatefulWidget {
  const _InvitationRow({super.key, required this.invitation, required this.onAccepted});

  final Invitation invitation;
  final Future<void> Function(Future<void> Function(BuildContext home) open) onAccepted;

  @override
  State<_InvitationRow> createState() => _InvitationRowState();
}

class _InvitationRowState extends State<_InvitationRow> {
  bool _pending = false;

  Future<void> _respond(bool accept) async {
    setState(() => _pending = true);
    final groups = context.read<GroupsController>();
    final invitation = widget.invitation;
    final error = await groups.respond(invitation, accept: accept);
    if (!mounted) return;
    setState(() => _pending = false);
    if (error != null) {
      await showErrorDialog(context, accept ? '接受邀請失敗' : '拒絕邀請失敗', error);
      return;
    }
    if (!accept) {
      showToast(context, '已拒絕邀請');
      return;
    }
    // respond 已經切到那個群組
    await widget.onAccepted((home) async => showToast(home, '已加入「${invitation.groupName}」'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final invitation = widget.invitation;
    final by = invitation.invitedBy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: by?.displayName ?? '?', photoUrl: by?.photoUrl, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: by?.displayName ?? '已刪除的使用者', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' 邀請你加入'),
                    TextSpan(text: '「${invitation.groupName}」', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  style: const TextStyle(fontSize: AppText.body),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(onPressed: _pending ? null : () => _respond(true), child: const Text('接受')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _pending ? null : () => _respond(false),
                      style: TextButton.styleFrom(foregroundColor: colors.alarm),
                      child: const Text('拒絕'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.message, this.action});

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded, size: 36, color: colors.inkMuted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: colors.inkMuted)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
          ],
          ?action,
        ],
      ),
    );
  }
}

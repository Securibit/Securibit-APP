import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../admin/permission_defs.dart';
import '../admin/site_access.dart';
import 'group_models.dart';
import 'groups_controller.dart';
import 'manage/group_entry.dart';
import 'manage/group_rules.dart';

/*
 * 群組列的動作（側欄、手機的群組分頁）：桌面右鍵或「…」跳出選單，手機長按從下面滑出面板。
 * 「＋」：新增群組（要有全站「建立群組」）、用邀請加入
 */

enum _GroupAction { manage, invite, settings, up, down }

/// 群組的動作選單；position 有給（桌面右鍵、按「…」）用跳出選單，沒給（手機長按）用底部面板
Future<void> showGroupActions(BuildContext context, GroupSummary group, {Offset? position}) async {
  final controller = context.read<GroupsController>();
  final list = controller.groups ?? const <GroupSummary>[];
  final index = list.indexWhere((g) => g.id == group.id);
  final items = <(_GroupAction, String, IconData, bool)>[
    (_GroupAction.manage, '管理群組', Icons.tune_rounded, true),
    if (canSeeInvites(group.permissions, encrypted: group.encrypted)) (_GroupAction.invite, '邀請成員', Icons.person_add_alt_1_rounded, true),
    (_GroupAction.settings, '群組設定', Icons.settings_rounded, true),
    if (list.length > 1) ...[
      (_GroupAction.up, '上移', Icons.arrow_upward_rounded, index > 0),
      (_GroupAction.down, '下移', Icons.arrow_downward_rounded, index >= 0 && index < list.length - 1),
    ],
  ];

  final _GroupAction? action;
  if (position != null) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    action = await showMenu<_GroupAction>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (final (value, label, icon, enabled) in items)
          PopupMenuItem(value: value, enabled: enabled, child: _MenuRow(label: label, icon: icon, enabled: enabled)),
      ],
    );
  } else {
    action = await showModalBottomSheet<_GroupAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
            ),
            for (final (value, label, icon, enabled) in items)
              ListTile(
                enabled: enabled,
                leading: Icon(icon),
                title: Text(label, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.of(context).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  if (action == null || !context.mounted) return;

  switch (action) {
    case _GroupAction.manage:
      await openGroupManage(context, group.id);
    case _GroupAction.invite:
      await openGroupManage(context, group.id, tab: GroupManageTab.invites.name);
    case _GroupAction.settings:
      await openGroupManage(context, group.id, tab: GroupManageTab.settings.name);
    case _GroupAction.up || _GroupAction.down:
      final error = await controller.move(group.id, action == _GroupAction.up ? -1 : 1);
      if (error != null && context.mounted) await showErrorDialog(context, '排序失敗', error);
  }
}

enum _AddAction { create, join }

/// 「＋」：有「建立群組」時跳出選單（新增群組、用邀請加入），沒有就直接開「用邀請加入」
Future<void> showAddGroupMenu(BuildContext context, {Offset? position, VoidCallback? beforeOpen}) async {
  final canCreate = SiteAccessController.shared.can(SitePermission.createGroups);
  _AddAction? action = _AddAction.join;
  if (canCreate) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = position ?? (box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay));
    action = await showMenu<_AddAction>(
      context: context,
      position: RelativeRect.fromRect(anchor & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: _AddAction.create, child: _MenuRow(label: '新增群組', icon: Icons.add_rounded)),
        PopupMenuItem(value: _AddAction.join, child: _MenuRow(label: '用邀請加入', icon: Icons.link_rounded)),
      ],
    );
  }
  if (action == null || !context.mounted) return;
  beforeOpen?.call();
  switch (action) {
    case _AddAction.create:
      unawaited(openCreateGroup(context));
    case _AddAction.join:
      unawaited(openJoinByInvite(context));
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, required this.icon, this.enabled = true});

  final String label;
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.inkMuted),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: AppText.body, color: enabled ? colors.ink : colors.inkMuted)),
      ],
    );
  }
}

/// 「＋」按鈕（側欄的群組標題旁、手機分頁列最後）
class AddGroupButton extends StatelessWidget {
  const AddGroupButton({super.key, this.beforeOpen, this.size = 20});

  // 打開表單前（手機要先關掉 Drawer）
  final VoidCallback? beforeOpen;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) {
        final canCreate = SiteAccessController.shared.can(SitePermission.createGroups);
        return Builder(
          builder: (context) => IconButton(
            tooltip: canCreate ? '新增群組' : '用邀請加入群組',
            visualDensity: VisualDensity.compact,
            onPressed: () => showAddGroupMenu(context, beforeOpen: beforeOpen),
            icon: Icon(Icons.add_rounded, size: size, color: context.colors.ink),
          ),
        );
      },
    );
  }
}

/// 未處理數字的小圓點（側欄的「邀請」、選單鍵）
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: colors.brand, borderRadius: BorderRadius.circular(999)),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w700, color: colors.accentInk),
      ),
    );
  }
}

/// 選單鍵（打開側欄）；有未處理的邀請時右上角帶數字
class MenuButtonWithBadge extends StatelessWidget {
  const MenuButtonWithBadge({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final count = context.select<GroupsController, int>((g) => g.pendingInvitations);
    return IconButton(
      tooltip: count > 0 ? '群組（$count 個邀請）' : '群組',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: context.colors.brand,
        textColor: context.colors.accentInk,
        child: Icon(Icons.menu_rounded, color: context.colors.ink),
      ),
    );
  }
}

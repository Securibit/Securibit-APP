import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pill.dart';
import '../../admin/admin_models.dart';
import '../../admin/hierarchy.dart';
import '../../admin/permission_defs.dart';
import '../../admin/roles/role_editor.dart';
import '../../admin/roles/roles_manager.dart';
import '../../admin/site_access.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../../admin/widgets/log_rows.dart';
import '../../admin/widgets/paged_list.dart';
import '../../auth/auth_controller.dart';
import '../../profile/profile_entry.dart';
import '../groups_controller.dart';
import '../groups_repository.dart' as repo;
import 'group_bans_tab.dart';
import 'group_invites_tab.dart';
import 'group_members_tab.dart';
import 'group_rules.dart';
import 'group_settings_tab.dart';
import 'group_tab_context.dart';

/*
 * 群組管理（同網站 src/app/groups/[id]/_components/GroupView.tsx）：成員、身分組、邀請、封鎖名單、設定、紀錄，依權限顯示。
 * 前台（側欄「管理群組」）與後台（adminMode）共用；驗證碼在主畫面，不在這裡。
 * 全站「管理所有群組」在群組裡有全部權限，不受階層限制；直接新增成員只在後台（前台一律走邀請）。
 */
class GroupView extends StatefulWidget {
  const GroupView({
    super.key,
    required this.groupId,
    this.adminMode = false,
    this.initialTab,
    this.onChanged,
    this.onExit,
    this.onOpenUser,
  });

  final String groupId;
  final bool adminMode;
  final GroupManageTab? initialTab;
  // 群組資料改了（後台的清單要重新整理）
  final VoidCallback? onChanged;
  // 離開或刪除群組之後
  final VoidCallback? onExit;
  // 只在後台使用：點成員開哪一頁（null 時不能點）；前台一律開個人頁
  final void Function(String userId)? onOpenUser;

  @override
  State<GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends State<GroupView> {
  AdminGroupDetail? _detail;
  String? _error;
  late GroupManageTab _tab = widget.initialTab ?? GroupManageTab.members;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 重新載入，回傳最新的資料（失敗時保留原本的並回傳 null）
  Future<AdminGroupDetail?> _load() async {
    final result = await repo.loadGroupDetail(widget.groupId);
    if (!mounted) return null;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _detail = data;
          _error = null;
        });
        return data;
      case Err(:final message):
        if (_detail == null) {
          setState(() => _error = message);
        } else {
          await showErrorDialog(context, '無法開啟群組', message);
        }
        return null;
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
    // 自己所在的群組（名稱、成員數、預設）在主畫面也要更新
    if (mounted) unawaited(context.read<GroupsController>().reload());
  }

  void _exit() {
    unawaited(context.read<GroupsController>().reload());
    widget.onExit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (detail == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: EmptyState(title: '無法開啟群組', message: _error, actionLabel: '重試', onAction: _load),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) => _content(context, detail),
    );
  }

  Widget _content(BuildContext context, AdminGroupDetail detail) {
    final access = SiteAccessController.shared;
    final myUid = context.select<AuthController, String?>((a) => a.profile?.uid);
    // 擁有者、全站管理員 / 管理所有群組：不受階層限制
    final actor = Actor(
      unrestricted: detail.isOwner || access.can(SitePermission.administrator) || access.can(SitePermission.manageGroups),
      topPosition: detail.topPosition,
    );
    final tabs = visibleTabs(detail);
    final tab = activeTab(detail, _tab);
    final tabContext = GroupTabContext(
      detail: detail,
      actor: actor,
      myUid: myUid,
      adminMode: widget.adminMode,
      onChanged: _changed,
      onExit: _exit,
      onOpenUser: widget.adminMode ? widget.onOpenUser : (id) => openUserProfile(context, id),
    );

    final tabBody = switch (tab) {
      GroupManageTab.members => GroupMembersTab(tab: tabContext),
      GroupManageTab.roles => _RolesTab(tab: tabContext, load: _load),
      GroupManageTab.invites => GroupInvitesTab(tab: tabContext),
      GroupManageTab.bans => GroupBansTab(tab: tabContext),
      GroupManageTab.settings => GroupSettingsTab(tab: tabContext),
      GroupManageTab.audit => _AuditTab(tab: tabContext),
    };

    return AdminScrollBody(
      onRefresh: () async => _load(),
      children: [
        DetailTitle(title: detail.group.name, subtitle: detail.group.description),
        _identity(context, detail, myUid),
        const SizedBox(height: 16),
        // 選中的反白底色會滑到新點的分頁
        PillBar(
          labels: [
            for (final t in tabs) t == GroupManageTab.members ? '${t.label} ${detail.members.length}' : t.label,
          ],
          selectedIndex: tabs.indexOf(tab),
          onSelect: (i) => setState(() => _tab = tabs[i]),
        ),
        const SizedBox(height: 20),
        KeyedSubtree(key: ValueKey(tab), child: tabBody),
      ],
    );
  }

  // 我的身分：擁有者、身分組，或非成員時「以全站管理權限檢視」
  Widget _identity(BuildContext context, AdminGroupDetail detail, String? myUid) {
    final me = detail.members.where((m) => m.id == myUid).firstOrNull;
    final myRoles = sortRoles(detail.roles).where((r) => !r.isDefault && (me?.roleIds.contains(r.id) ?? false)).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 2),
          child: Text('我的身分', style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted)),
        ),
        if (detail.isOwner) const Tag('擁有者'),
        for (final role in myRoles) RoleChip(name: role.name, color: role.color),
        if (me != null && !detail.isOwner && myRoles.isEmpty) const Tag('@everyone'),
        if (me == null) const Tag('非成員，以全站管理權限檢視'),
        if (detail.isDefault) const Tag('我的預設群組', accent: true),
        if (detail.group.encrypted) const Tag('已加密', icon: Icons.lock_rounded),
      ],
    );
  }
}

// ---------- 身分組 ----------

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.tab, required this.load});

  final GroupTabContext tab;
  final Future<AdminGroupDetail?> Function() load;

  @override
  Widget build(BuildContext context) {
    final detail = tab.detail;
    final gid = tab.groupId;
    final canManage = hasPermission(detail.permissions, GroupPermission.manageRoles);
    return RolesManager(
      roles: detail.roles,
      split: false,
      intro: canManage
          ? null
          : const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: MutedText('你沒有「管理身分組」權限，只能查看')),
      config: RoleEditorConfig(
        definitions: groupPermissionDefs,
        actor: tab.actor,
        actorPermissions: detail.permissions,
        canManage: canManage,
        onUpdate: repo.updateGroupRole,
        onDelete: repo.deleteGroupRole,
        onChanged: () async {
          final latest = await load();
          if (context.mounted) unawaited(context.read<GroupsController>().reload());
          return latest?.roles;
        },
      ),
      onCreate: (input) => repo.createGroupRole(gid, input),
      onReorder: (ids) => repo.reorderGroupRoles(gid, ids),
    );
  }
}

// ---------- 紀錄 ----------

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.tab});

  final GroupTabContext tab;

  @override
  Widget build(BuildContext context) {
    final groupId = tab.groupId;
    final open = tab.onOpenUser;
    return PagedList<AuditLog>(
      key: ValueKey('group-audit-$groupId'),
      load: (before) => repo.loadGroupAuditLog(groupId, before),
      pageSize: repo.auditPageSize,
      idOf: (log) => log.id,
      emptyText: '還沒有任何紀錄',
      errorTitle: '載入操作紀錄失敗',
      itemBuilder: (context, log, _) => AuditLogRow(log: log, onOpenActor: open == null ? null : (actor) => open(actor.id)),
    );
  }
}

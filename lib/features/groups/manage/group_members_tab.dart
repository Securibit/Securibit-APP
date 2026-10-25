import 'package:flutter/material.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../admin/admin_format.dart';
import '../../admin/admin_models.dart';
import '../../admin/admin_repository.dart' as admin_repo;
import '../../admin/hierarchy.dart';
import '../../admin/permission_defs.dart';
import '../../admin/roles/role_assign_form.dart';
import '../../admin/site_access.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../groups_repository.dart' as repo;
import 'group_bans_tab.dart';
import 'group_rules.dart';
import 'group_tab_context.dart';

enum _MemberAction { roles, transfer, kick, ban }

/*
 * 成員分頁（同網站 GroupMembers）：清單、指派身分組、轉移擁有權、移出群組、封鎖；
 * 能不能管理照身分組階層（hierarchy.dart）。全站管理員在後台可以直接新增成員，前台一律走邀請
 */
class GroupMembersTab extends StatefulWidget {
  const GroupMembersTab({super.key, required this.tab});

  final GroupTabContext tab;

  @override
  State<GroupMembersTab> createState() => _GroupMembersTabState();
}

class _GroupMembersTabState extends State<GroupMembersTab> {
  final _target = TextEditingController();
  bool _adding = false;

  AdminGroupDetail get _detail => widget.tab.detail;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final target = _target.text.trim();
    if (target.isEmpty || _adding) return;
    setState(() => _adding = true);
    final result = await admin_repo.addGroupMember(_detail.group.id, target);
    if (!mounted) return;
    setState(() => _adding = false);
    switch (result) {
      case Err(:final message):
        await showErrorDialog(context, '新增成員失敗', message);
      case Ok(:final data):
        showToast(context, '已加入 ${data.name ?? target}');
        _target.clear();
        await widget.tab.onChanged();
    }
  }

  Future<void> _onAction(GroupMember member, _MemberAction action) async {
    final name = member.person.displayName;
    switch (action) {
      case _MemberAction.roles:
        final saved = await showAdminForm<bool>(
          context,
          RoleAssignForm(
            title: '指派身分組給 $name',
            roles: _detail.roles,
            selected: member.roleIds,
            actor: widget.tab.actor,
            actorPermissions: _detail.permissions,
            onSave: (ids) => repo.setMemberRoles(_detail.group.id, member.id, ids),
          ),
        );
        if (saved == true && mounted) await widget.tab.onChanged();
      case _MemberAction.kick:
        final ok = await confirmDialog(
          context,
          title: '移出群組',
          message: '確定要將 $name 移出群組嗎？對方之後要重新受邀才能再加入',
          confirmLabel: '移出',
          danger: true,
        );
        if (!ok || !mounted) return;
        final result = await repo.kickMember(_detail.group.id, member.id);
        if (!mounted) return;
        if (result case Err(:final message)) {
          await showErrorDialog(context, '移除成員失敗', message);
          return;
        }
        showToast(context, '已將 $name 移出群組');
        await widget.tab.onChanged();
      case _MemberAction.ban:
        final saved = await showAdminForm<bool>(context, BanForm(groupId: _detail.group.id, member: member));
        if (saved == true && mounted) await widget.tab.onChanged();
      case _MemberAction.transfer:
        final blocked = transferBlockedReason(_detail);
        if (blocked != null) {
          await showErrorDialog(context, '無法轉移擁有權', blocked);
          return;
        }
        final ok = await confirmDialog(
          context,
          title: '轉移擁有權',
          message: '確定要把群組擁有權轉移給 $name 嗎？轉移後你會變成一般成員（保留目前的身分組），不能再刪除群組或轉移擁有權，也可能失去部分權限。這個動作只有新的擁有者能再轉回來',
          confirmLabel: '轉移',
          danger: true,
        );
        if (!ok || !mounted) return;
        final result = await repo.transferGroup(_detail.group.id, member.id);
        if (!mounted) return;
        if (result case Err(:final message)) {
          await showErrorDialog(context, '轉移擁有權失敗', message);
          return;
        }
        showToast(context, '已將擁有權轉移給 $name');
        await widget.tab.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final access = SiteAccessController.shared;
    final canAssign = hasPermission(_detail.permissions, GroupPermission.manageRoles);
    final canKick = hasPermission(_detail.permissions, GroupPermission.kickMembers);
    final canBan = canManageBans(_detail.permissions);
    // 直接加入只在後台：全站「管理所有群組」；加密的群組只能有擁有者一人
    final canAdd = widget.tab.adminMode && access.can(SitePermission.manageGroups) && !_detail.group.encrypted;
    final openUser = widget.tab.onOpenUser;
    final roles = sortRoles(_detail.roles);
    final members = sortMembers(_detail.members);

    final rows = <Widget>[];
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      final manageable = canManageMember(widget.tab.actor, topPosition: member.topPosition, isOwner: member.isOwner);
      final isSelf = member.id == widget.tab.myUid;
      final memberRoles = roles.where((r) => !r.isDefault && member.roleIds.contains(r.id)).toList();
      final actions = <MenuAction<_MemberAction>>[
        if (canAssign && manageable) const MenuAction(_MemberAction.roles, '指派身分組', Icons.sell_rounded),
        if (_detail.isOwner && !member.isOwner) const MenuAction(_MemberAction.transfer, '轉移擁有權', Icons.swap_horiz_rounded),
        if (canKick && manageable && !isSelf) const MenuAction(_MemberAction.kick, '移出群組', Icons.person_remove_rounded, danger: true),
        if (canBan && manageable && !isSelf && !member.isOwner) const MenuAction(_MemberAction.ban, '封鎖', Icons.block_rounded, danger: true),
      ];
      if (i > 0) rows.add(Divider(indent: 64, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(InkWell(
        // 點頭像或名稱開對方的個人頁
        onTap: openUser == null ? null : () => openUser(member.id),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, actions.isEmpty ? 16 : 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PersonChip(person: member.person),
                    if (member.isOwner || isSelf || memberRoles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 48, top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (member.isOwner) const Tag('擁有者', accent: true),
                            if (isSelf) const Tag('你'),
                            for (final role in memberRoles) RoleChip(name: role.name, color: role.color),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Text('加入於 ${formatDateTime(member.joinedAt)}', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) MoreMenuButton<_MemberAction>(actions: actions, onSelected: (a) => _onAction(member, a)),
            ],
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canAdd) ...[
          const SectionHeader('新增成員'),
          SoftCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      hintText: '電子郵件、@ID 或使用者 ID',
                      isDense: true,
                      filled: true,
                      fillColor: colors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _adding || _target.text.trim().isEmpty ? null : _add,
                  child: _adding
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('加入'),
                ),
              ],
            ),
          ),
          const FootNote('直接加入、不用對方接受；加入後只有 @everyone 的權限。對方要是已驗證電子郵件的使用者'),
          const SizedBox(height: 24),
        ],
        SectionHeader('共 ${members.length} 位成員'),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
        ),
        if (!widget.tab.adminMode && canSeeInvites(_detail.permissions, encrypted: _detail.group.encrypted))
          const FootNote('要加入新成員，請到「邀請」分頁建立邀請連結，或用電子郵件、@ID 邀請'),
      ],
    );
  }
}

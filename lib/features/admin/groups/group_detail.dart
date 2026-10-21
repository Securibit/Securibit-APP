import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/pill.dart';
import '../../auth/auth_controller.dart';
import '../../groups/groups_controller.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../admin_repository.dart' as repo;
import '../hierarchy.dart';
import '../permission_defs.dart';
import '../roles/role_assign_form.dart';
import '../roles/role_editor.dart';
import '../roles/roles_manager.dart';
import '../site_access.dart';
import '../users/user_detail.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/log_rows.dart';
import '../widgets/paged_list.dart';
import 'group_forms.dart';

enum _Tab { members, roles, settings, audit }

/*
 * 後台的群組管理（同網站 /admin/groups/[id] 的 GroupView adminMode）：成員、身分組、設定、紀錄。
 * 全站「管理所有群組」在群組裡有全部權限，不受階層限制；直接新增成員只在這裡（前台一律走邀請）。
 */
class AdminGroupDetailView extends StatefulWidget {
  const AdminGroupDetailView({super.key, required this.groupId, this.onChanged, this.onDeleted});

  final String groupId;
  // 群組資料改了（清單要重新整理）
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;

  @override
  State<AdminGroupDetailView> createState() => _AdminGroupDetailViewState();
}

class _AdminGroupDetailViewState extends State<AdminGroupDetailView> {
  AdminGroupDetail? _detail;
  String? _error;
  _Tab _tab = _Tab.members;

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
    // 自己所在的群組（名稱、成員數）在主畫面也要更新
    if (mounted) unawaited(context.read<GroupsController>().reload());
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
    final showAudit = hasPermission(detail.permissions, GroupPermission.viewAuditLog);
    final tab = _tab == _Tab.audit && !showAudit ? _Tab.members : _tab;

    final tabBody = switch (tab) {
      _Tab.members => _MembersTab(detail: detail, actor: actor, myUid: myUid, onChanged: _changed),
      _Tab.roles => _RolesTab(detail: detail, actor: actor, onChanged: _changed, load: _load),
      _Tab.settings => _SettingsTab(detail: detail, onChanged: _changed, onDeleted: widget.onDeleted),
      _Tab.audit => _AuditTab(groupId: detail.group.id),
    };

    return AdminScrollBody(
      onRefresh: () async => _load(),
      children: [
        DetailTitle(title: detail.group.name, subtitle: detail.group.description),
        _identity(context, detail, myUid),
        const SizedBox(height: 16),
        Builder(builder: (context) {
          final tabs = [
            (_Tab.members, '成員 ${detail.members.length}'),
            (_Tab.roles, '身分組'),
            (_Tab.settings, '設定'),
            if (showAudit) (_Tab.audit, '紀錄'),
          ];
          // 選中的反白底色會滑到新點的分頁
          return PillBar(
            labels: [for (final (_, label) in tabs) label],
            selectedIndex: tabs.indexWhere((t) => t.$1 == tab),
            onSelect: (i) => setState(() => _tab = tabs[i].$1),
          );
        }),
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

// ---------- 成員 ----------

enum _MemberAction { roles, transfer, kick }

class _MembersTab extends StatefulWidget {
  const _MembersTab({required this.detail, required this.actor, required this.myUid, required this.onChanged});

  final AdminGroupDetail detail;
  final Actor actor;
  final String? myUid;
  final Future<void> Function() onChanged;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  final _target = TextEditingController();
  bool _adding = false;

  AdminGroupDetail get _detail => widget.detail;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final target = _target.text.trim();
    if (target.isEmpty || _adding) return;
    setState(() => _adding = true);
    final result = await repo.addGroupMember(_detail.group.id, target);
    if (!mounted) return;
    setState(() => _adding = false);
    switch (result) {
      case Err(:final message):
        await showErrorDialog(context, '新增成員失敗', message);
      case Ok(:final data):
        showToast(context, '已加入 ${data.name ?? target}');
        _target.clear();
        await widget.onChanged();
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
            actor: widget.actor,
            actorPermissions: _detail.permissions,
            onSave: (ids) => repo.setMemberRoles(_detail.group.id, member.id, ids),
          ),
        );
        if (saved == true && mounted) await widget.onChanged();
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
        await widget.onChanged();
      case _MemberAction.transfer:
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
        await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final access = SiteAccessController.shared;
    final canAssign = hasPermission(_detail.permissions, GroupPermission.manageRoles);
    final canKick = hasPermission(_detail.permissions, GroupPermission.kickMembers);
    // 直接加入只在後台：全站「管理所有群組」；加密的群組只能有擁有者一人
    final canAdd = access.can(SitePermission.manageGroups) && !_detail.group.encrypted;
    final canOpenUser = access.can(SitePermission.viewUsers);
    final roles = sortRoles(_detail.roles);

    // 擁有者最前面，其餘依最高身分組、再依名稱
    final members = [..._detail.members]..sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        final byTop = b.topPosition - a.topPosition;
        return byTop != 0 ? byTop : a.person.displayName.compareTo(b.person.displayName);
      });

    final rows = <Widget>[];
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      final manageable = canManageMember(widget.actor, topPosition: member.topPosition, isOwner: member.isOwner);
      final isSelf = member.id == widget.myUid;
      final memberRoles = roles.where((r) => !r.isDefault && member.roleIds.contains(r.id)).toList();
      final actions = <MenuAction<_MemberAction>>[
        if (canAssign && manageable) const MenuAction(_MemberAction.roles, '指派身分組', Icons.sell_rounded),
        if (_detail.isOwner && !member.isOwner) const MenuAction(_MemberAction.transfer, '轉移擁有權', Icons.swap_horiz_rounded),
        if (canKick && manageable && !isSelf) const MenuAction(_MemberAction.kick, '移出群組', Icons.person_remove_rounded, danger: true),
      ];
      if (i > 0) rows.add(Divider(indent: 64, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(InkWell(
        onTap: canOpenUser ? () => pushAdminPage<void>(context, UserDetailView(userId: member.id)) : null,
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
      ],
    );
  }
}

// ---------- 身分組 ----------

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.detail, required this.actor, required this.onChanged, required this.load});

  final AdminGroupDetail detail;
  final Actor actor;
  final Future<void> Function() onChanged;
  final Future<AdminGroupDetail?> Function() load;

  @override
  Widget build(BuildContext context) {
    final gid = detail.group.id;
    final canManage = hasPermission(detail.permissions, GroupPermission.manageRoles);
    return RolesManager(
      roles: detail.roles,
      split: false,
      intro: canManage
          ? null
          : const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: MutedText('你沒有「管理身分組」權限，只能查看')),
      config: RoleEditorConfig(
        definitions: groupPermissionDefs,
        actor: actor,
        actorPermissions: detail.permissions,
        canManage: canManage,
        onUpdate: repo.updateGroupRole,
        onDelete: repo.deleteGroupRole,
        onChanged: () async {
          final latest = await load();
          return latest?.roles;
        },
      ),
      onCreate: (input) => repo.createGroupRole(gid, input),
      onReorder: (ids) => repo.reorderGroupRoles(gid, ids),
    );
  }
}

// ---------- 設定 ----------

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.detail, required this.onChanged, required this.onDeleted});

  final AdminGroupDetail detail;
  final Future<void> Function() onChanged;
  final VoidCallback? onDeleted;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final _name = TextEditingController(text: widget.detail.group.name);
  late final _description = TextEditingController(text: widget.detail.group.description);
  String? _nameError;
  bool _saving = false;

  GroupInfo get _group => widget.detail.group;

  bool get _dirty => _name.text.trim() != _group.name || _description.text.trim() != _group.description;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '請輸入群組名稱');
      return;
    }
    setState(() => _saving = true);
    final result = await repo.updateGroup(_group.id, _name.text, _description.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '儲存群組設定失敗', message);
      return;
    }
    showToast(context, '已儲存');
    await widget.onChanged();
  }

  Future<void> _delete() async {
    final deleted = await showAdminForm<bool>(context, GroupDeleteForm(groupId: _group.id, groupName: _group.name));
    if (deleted != true || !mounted) return;
    unawaited(context.read<GroupsController>().reload());
    widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final access = SiteAccessController.shared;
    final canEdit = hasPermission(detail.permissions, GroupPermission.manageGroup);
    // 刪除群組：擁有者，或全站管理員；擁有者不能刪自己的預設群組、也不能刪唯一擁有的群組（資料庫同樣檢查）
    final canDelete = detail.isOwner || access.can(SitePermission.administrator);
    final deleteBlocked = !detail.isOwner
        ? null
        : detail.isDefault
            ? '這是你的預設群組，要先把其他群組設為預設才能刪除'
            : detail.ownedCount <= 1
                ? '這是你唯一擁有的群組，不能刪除'
                : null;
    final owner = detail.members.where((m) => m.isOwner).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('群組資料'),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('名稱'),
              TextField(
                controller: _name,
                enabled: canEdit && !_saving,
                maxLength: groupNameMax,
                onChanged: (_) => setState(() => _nameError = null),
                decoration: InputDecoration(errorText: _nameError, counterText: '', fillColor: context.colors.surface),
              ),
              const SizedBox(height: 16),
              const FieldLabel('說明'),
              TextField(
                controller: _description,
                enabled: canEdit && !_saving,
                maxLength: groupDescriptionMax,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  counterText: '',
                  fillColor: context.colors.surface,
                  helperText: canEdit ? '選填，${_description.text.length} / $groupDescriptionMax' : '需要「管理群組」權限才能修改',
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _dirty && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('儲存'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        GroupedList(
          header: '資訊',
          children: [
            GroupedRow(
              label: '群組 ID',
              value: _group.id,
              trailing: Icon(Icons.copy_rounded, size: 18, color: context.colors.inkMuted),
              onTap: () => copyText(context, _group.id),
            ),
            GroupedRow(label: '擁有者', value: owner?.person.displayName ?? '無'),
            GroupedRow(label: '建立時間', value: formatDateTime(_group.createdAt)),
            GroupedRow(label: '加密', value: _group.encrypted ? '已開啟' : '未開啟'),
          ],
        ),
        if (canDelete) ...[
          const SizedBox(height: 28),
          DangerButton(label: '刪除群組', onPressed: deleteBlocked == null ? _delete : null),
          FootNote(deleteBlocked ?? '刪除後群組的所有驗證碼、金鑰、身分組、成員與邀請都會一併刪除，無法恢復'),
        ],
      ],
    );
  }
}

// ---------- 紀錄 ----------

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final canOpenUser = SiteAccessController.shared.can(SitePermission.viewUsers);
    return PagedList<AuditLog>(
      key: ValueKey('group-audit-$groupId'),
      load: (before) => repo.loadGroupAuditLog(groupId, before),
      pageSize: repo.auditPageSize,
      idOf: (log) => log.id,
      emptyText: '還沒有任何紀錄',
      errorTitle: '載入操作紀錄失敗',
      itemBuilder: (context, log, _) => AuditLogRow(
        log: log,
        onOpenActor: canOpenUser ? (actor) => pushAdminPage<void>(context, UserDetailView(userId: actor.id)) : null,
      ),
    );
  }
}

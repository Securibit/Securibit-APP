import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../auth/auth_controller.dart';
import '../../groups/groups_controller.dart';
import '../../profile/devices_page.dart';
import '../../profile/session_models.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../admin_repository.dart' as repo;
import '../groups/group_detail.dart';
import '../hierarchy.dart';
import '../permission_defs.dart';
import '../roles/role_assign_form.dart';
import '../site_access.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/log_rows.dart';
import '../widgets/paged_list.dart';
import 'user_forms.dart';
import 'user_totp_section.dart';

// 登入紀錄 / 操作紀錄每次載入的筆數
const _activityPageSize = 10;

/*
 * 後台使用者詳細資料（同網站 /admin/users/[id]）：身分、帳號、登入資訊、身分組、2FA、已登入的裝置（只能查看）、登入紀錄、操作紀錄，最後是刪除。
 * 修改資料、刪除要「管理使用者」而且階層比對方高、不是自己；2FA 要自己的或階層比對方高（資料庫同樣檢查）。
 */
class UserDetailView extends StatefulWidget {
  const UserDetailView({super.key, required this.userId, this.onChanged, this.onDeleted});

  final String userId;
  // 資料改了（清單要重新整理）
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;

  @override
  State<UserDetailView> createState() => _UserDetailViewState();
}

class _UserDetailViewState extends State<UserDetailView> {
  // null：載入中
  AdminUserDetail? _detail;
  String? _error;
  List<Role> _roles = const [];
  bool _rolesLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadRoles());
  }

  // 重新載入失敗時保留畫面上原本的資料
  Future<void> _load() async {
    final result = await repo.loadAdminUser(widget.userId);
    if (!mounted) return;
    switch (result) {
      case Ok(:final data) when data != null:
        setState(() {
          _detail = data;
          _error = null;
        });
      case Ok():
        setState(() => _error = _detail == null ? '找不到這位使用者' : null);
      case Err(:final message):
        if (_detail == null) {
          setState(() => _error = message);
        } else {
          await showErrorDialog(context, '載入使用者失敗', message);
        }
    }
  }

  Future<void> _loadRoles() async {
    final result = await repo.loadSiteRoles();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _roles = sortRoles(data);
          _rolesLoaded = true;
        });
      case Err(:final message):
        await showErrorDialog(context, '載入身分組失敗', message);
    }
  }

  Future<void> _afterChange() async {
    await _load();
    widget.onChanged?.call();
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
            child: EmptyState(title: '找不到這位使用者', message: _error, actionLabel: '重試', onAction: _load),
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

  Widget _content(BuildContext context, AdminUserDetail detail) {
    final access = SiteAccessController.shared;
    final user = detail.user;
    final myUid = context.select<AuthController, String?>((a) => a.profile?.uid);
    final isSelf = myUid == user.id;
    // 只有最高位身分組的持有者不受階層限制；身分組載入前先當作受限
    final actor = Actor(unrestricted: _rolesLoaded && isSiteRoot(access.topPosition, _roles), topPosition: access.topPosition);
    final reachable = canManageMember(actor, topPosition: user.topPosition);
    final canManageUser = access.can(SitePermission.manageUsers) && !isSelf && reachable;
    final canAssignRoles = access.can(SitePermission.manageRoles);
    final canReachTotp = isSelf || reachable;
    final userRoles = _roles.where((r) => user.roleIds.contains(r.id)).toList();

    return AdminScrollBody(
      onRefresh: _load,
      children: [
        _identity(context, user, canManageUser),
        const SizedBox(height: 24),
        GroupedList(
          header: '帳號',
          footer: isSelf ? '這是你自己的帳號，名稱與 @ID 請到「設定」修改' : null,
          children: [
            GroupedRow(label: '@ID', value: user.username != null ? '@${user.username}' : '未設定'),
            GroupedRow(
              label: '使用者 ID',
              value: user.id,
              trailing: Icon(Icons.copy_rounded, size: 18, color: context.colors.inkMuted),
              onTap: () => copyText(context, user.id),
            ),
            GroupedRow(label: '電子郵件', value: user.email.isNotEmpty ? user.email : '無'),
            GroupedRow(label: '加密密碼', value: user.vaultEnabled ? '已設定' : '未設定'),
            _groupsRow(context, detail.groups),
          ],
        ),
        const SizedBox(height: 24),
        GroupedList(
          header: '登入資訊',
          children: [
            GroupedRow(label: '建立時間', value: formatDateTime(user.creationTime)),
            GroupedRow(label: '最後登入', value: formatDateTime(user.lastLoginAt)),
            // 所有登入中裝置的最後活動取最新的；沒有登入中的裝置時是「無」
            GroupedRow(label: '最後活動', value: formatDateTime(user.lastActiveAt)),
            // 階層不比對方高時資料庫不給 IP（null）
            GroupedRow(
              label: 'IP',
              value: (user.lastLoginIp?.isNotEmpty ?? false)
                  ? user.lastLoginIp
                  : (user.lastLoginAt != null && user.lastLoginIp == null ? '不公開' : '無'),
            ),
            GroupedRow(label: '裝置', value: user.lastLoginDevice ?? '無'),
          ],
        ),
        const SizedBox(height: 24),
        SectionHeader(
          '身分組',
          actionLabel: canAssignRoles ? '編輯' : null,
          onAction: _rolesLoaded ? () => _assignRoles(user, actor, isSelf) : null,
        ),
        SoftCard(
          child: userRoles.isEmpty
              ? const MutedText('只有 @everyone')
              : Wrap(spacing: 6, runSpacing: 6, children: [for (final r in userRoles) RoleChip(name: r.name, color: r.color)]),
        ),
        if (access.can(SitePermission.viewUserTotp) && canReachTotp) ...[
          const SizedBox(height: 24),
          UserTotpSection(user: user, canManage: access.can(SitePermission.manageUserTotp)),
        ],
        const SizedBox(height: 24),
        const SectionHeader('已登入的裝置'),
        _UserSessions(key: ValueKey('sessions-${user.id}'), userId: user.id),
        const SizedBox(height: 24),
        const SectionHeader('登入紀錄'),
        PagedList<LoginRecord>(
          key: ValueKey('login-${user.id}'),
          load: (before) => repo.loadAdminUserLoginHistory(user.id, before, _activityPageSize),
          pageSize: _activityPageSize,
          idOf: (r) => r.id,
          emptyText: '還沒有登入紀錄',
          errorTitle: '載入登入紀錄失敗',
          itemBuilder: (context, record, index) => LoginRecordRow(record: record, latest: index == 0),
        ),
        const SizedBox(height: 24),
        const SectionHeader('帳號操作紀錄'),
        PagedList<AccountActivity>(
          key: ValueKey('activity-${user.id}'),
          load: (before) => repo.loadAdminUserActivity(user.id, before, _activityPageSize),
          pageSize: _activityPageSize,
          idOf: (a) => a.id,
          emptyText: '還沒有操作紀錄',
          errorTitle: '載入操作紀錄失敗',
          itemBuilder: (context, activity, _) => ActivityRow(activity: activity, subjectId: user.id),
        ),
        if (canManageUser) ...[
          const SizedBox(height: 28),
          DangerButton(label: '刪除使用者', onPressed: () => _delete(user)),
          const FootNote('會刪除帳號、只有他一個人的群組（含預設群組）與群組成員資格，無法恢復；擁有有其他成員的群組時要先轉移或刪除群組'),
        ],
      ],
    );
  }

  Widget _identity(BuildContext context, AdminUser user, bool canEdit) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          UserAvatar(name: user.name.isNotEmpty ? user.name : user.email, photoUrl: user.photoUrl, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isNotEmpty ? user.name : '（未命名）',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700),
                ),
                Text(
                  user.username != null ? '@${user.username}' : (user.email.isNotEmpty ? user.email : '沒有電子郵件'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                ),
              ],
            ),
          ),
          if (canEdit) TextButton(onPressed: () => _edit(user), child: const Text('編輯')),
        ],
      ),
    );
  }

  // 群組：有「管理所有群組」開後台的群組頁；沒有的話，自己也在的群組回主畫面打開它
  Widget _groupsRow(BuildContext context, List<AdminUserGroup> groups) {
    final colors = context.colors;
    final canManageGroups = SiteAccessController.shared.can(SitePermission.manageGroups);
    final myGroupIds = context.select<GroupsController, Set<String>>((g) => {for (final group in g.groups ?? const []) group.id});
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('群組', style: TextStyle(fontSize: AppText.body))),
          const SizedBox(width: 16),
          Expanded(
            child: groups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('無', textAlign: TextAlign.right, style: TextStyle(fontSize: AppText.body, color: colors.inkMuted)),
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final group in groups)
                        _GroupChip(
                          group: group,
                          onTap: canManageGroups
                              ? () => pushAdminPage<void>(context, AdminGroupDetailView(groupId: group.id))
                              : myGroupIds.contains(group.id)
                                  ? () => _openMyGroup(group.id)
                                  : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // 回到主畫面打開自己所在的群組
  void _openMyGroup(String groupId) {
    context.read<GroupsController>().select(groupId);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _edit(AdminUser user) async {
    final saved = await showAdminForm<bool>(context, UserEditForm(user: user));
    if (saved == true && mounted) await _afterChange();
  }

  Future<void> _delete(AdminUser user) async {
    final deleted = await showAdminForm<bool>(context, UserDeleteForm(user: user));
    if (deleted == true && mounted) widget.onDeleted?.call();
  }

  Future<void> _assignRoles(AdminUser user, Actor actor, bool isSelf) async {
    final access = SiteAccessController.shared;
    final saved = await showAdminForm<bool>(
      context,
      RoleAssignForm(
        title: '指派身分組',
        roles: _roles,
        selected: user.roleIds,
        actor: actor,
        actorPermissions: access.permissions,
        onSave: (ids) => repo.setUserSiteRoles(user.id, ids),
      ),
    );
    if (saved != true || !mounted) return;
    // 改到自己的身分組時，自己的權限也要重新讀
    await Future.wait([_afterChange(), _loadRoles(), if (isSelf) access.reload()]);
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group, required this.onTap});

  final AdminUserGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (group.isOwner) ...[
                Tooltip(message: '擁有者', child: Icon(Icons.workspace_premium_rounded, size: 14, color: colors.inkMuted)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: onTap == null ? colors.ink : colors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已登入的裝置（只能查看，同網站後台的 SessionList readOnly）：和個人頁面的「已登入的裝置」同一種列
class _UserSessions extends StatefulWidget {
  const _UserSessions({super.key, required this.userId});

  final String userId;

  @override
  State<_UserSessions> createState() => _UserSessionsState();
}

class _UserSessionsState extends State<_UserSessions> {
  // null：載入中
  List<SessionRecord>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await repo.loadAdminUserSessions(widget.userId);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(:final data):
          _sessions = data;
          _error = null;
        case Err(:final message):
          _sessions ??= const [];
          _error = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    if (sessions == null) return const ListLoading();
    // 讀不到（例如舊的資料庫沒有這個功能）直接寫在這裡，不跳對話框
    if (_error != null && sessions.isEmpty) return SoftCard(child: MutedText('載入已登入的裝置失敗：$_error'));
    if (sessions.isEmpty) return const ListEmpty('沒有登入中的裝置');
    return GroupedList(children: [for (final session in sessions) SessionRow(session: session, readOnly: true)]);
  }
}

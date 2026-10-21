import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../admin/admin_format.dart';
import '../admin/admin_models.dart';
import '../admin/admin_nav.dart';
import '../admin/admin_repository.dart' as admin;
import '../admin/hierarchy.dart';
import '../admin/permission_defs.dart';
import '../admin/roles/role_assign_form.dart';
import '../admin/site_access.dart';
import '../admin/users/user_detail.dart';
import '../admin/users/user_forms.dart';
import '../admin/widgets/admin_widgets.dart';
import '../auth/auth_controller.dart';
import '../groups/groups_controller.dart';
import 'profile_frame.dart';
import 'profile_models.dart';
import 'profile_repository.dart' as repo;

/*
 * 別人的個人頁面（同網站 /u/[id]）：大頭照、名稱、@ID、全站身分組，下面是加入時間、共同群組，
 * 有權限時最後是「管理」（編輯、指派身分組、2FA 與後台使用者頁、刪除）。
 * 按鈕只依權限與階層決定要不要顯示，真正的檢查在資料庫的 RPC。
 */
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.userId, required this.inDialog});

  final String userId;
  final bool inDialog;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  UserPublic? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 決定「管理」要顯示什麼的全站權限；還沒讀過時先讀
    final uid = context.read<AuthController>().profile?.uid;
    final access = SiteAccessController.shared;
    if (access.uid != uid) scheduleMicrotask(() => access.attach(uid));
    unawaited(_load());
  }

  // 用 id 讀（改過 @ID 也找得到）；重新載入失敗時保留畫面上的資料
  Future<void> _load() async {
    final result = await repo.loadUserPublic(_data?.id ?? widget.userId);
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _data = data;
          _error = null;
        });
      case Err(:final message):
        if (_data == null) {
          setState(() => _error = message);
        } else {
          await showErrorDialog(context, '重新載入失敗', message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return ProfilePageScaffold(
        title: '個人頁面',
        inDialog: widget.inDialog,
        children: [
          if (_error != null)
            EmptyState(title: '找不到這位使用者', message: _error, actionLabel: '重試', onAction: _load)
          else
            const Padding(padding: EdgeInsets.only(top: 48), child: Center(child: CircularProgressIndicator.adaptive())),
        ],
      );
    }
    return ProfilePageScaffold(
      title: '個人頁面',
      inDialog: widget.inDialog,
      onRefresh: _load,
      children: [
        _Identity(user: data),
        const SizedBox(height: 24),
        GroupedList(header: '帳號', children: [GroupedRow(label: '加入時間', value: formatDateTime(data.createdAt))]),
        const SizedBox(height: 24),
        _SharedGroups(key: ValueKey('groups-${data.id}'), target: data, onChanged: _load),
        _AdminActions(key: ValueKey('admin-${data.id}'), target: data, onChanged: _load),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final UserPublic user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: user.name.isNotEmpty ? user.name : '?', photoUrl: user.photoUrl, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  user.name.isNotEmpty ? user.name : '（未命名）',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700),
                ),
                if (user.username != null)
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                  ),
                if (user.siteRoles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final role in user.siteRoles) RoleChip(name: role.name, color: role.color)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/*
 * 共同群組：每列可以點開群組（回到主畫面切過去）；我在那個群組可能管得到他時，右邊多一個「…」
 * （指派身分組、移出群組）。點開「…」才讀那個群組的 detail，讀過就沿用，有變動時丟掉重讀。
 */
class _SharedGroups extends StatefulWidget {
  const _SharedGroups({super.key, required this.target, required this.onChanged});

  final UserPublic target;
  final Future<void> Function() onChanged;

  @override
  State<_SharedGroups> createState() => _SharedGroupsState();
}

class _SharedGroupsState extends State<_SharedGroups> {
  final _details = <String, AdminGroupDetail>{};
  String? _loadingGid;

  // 全站管理員 / 管理所有群組：在任何群組都不受階層限制（同群組頁）
  bool get _siteSuper {
    final access = SiteAccessController.shared;
    return access.can(SitePermission.administrator) || access.can(SitePermission.manageGroups);
  }

  void _openGroup(String gid) {
    context.read<GroupsController>().select(gid);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openMenu(BuildContext buttonContext, SharedGroup group) async {
    var detail = _details[group.id];
    if (detail == null) {
      setState(() => _loadingGid = group.id);
      final result = await admin.loadGroupDetail(group.id);
      if (!mounted) return;
      setState(() => _loadingGid = null);
      switch (result) {
        case Ok(:final data):
          _details[group.id] = detail = data;
        case Err(:final message):
          await showErrorDialog(context, '載入群組失敗', message);
          return;
      }
    }
    if (!buttonContext.mounted) return;
    final menu = sharedGroupMenu(detail, widget.target.id, siteSuper: _siteSuper);
    final action = await _showMenu(buttonContext, menu);
    if (action == null || !mounted || menu.member == null) return;
    switch (action) {
      case SharedGroupAction.roles:
        await _assignRoles(group, detail, menu.member!);
      case SharedGroupAction.kick:
        await _kick(group);
    }
  }

  Future<SharedGroupAction?> _showMenu(BuildContext buttonContext, SharedGroupMenu menu) {
    final colors = context.colors;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    Widget item(IconData icon, String label, {bool danger = false, bool enabled = true}) => Row(
          children: [
            Icon(icon, size: 20, color: danger && enabled ? colors.alarm : colors.inkMuted),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: AppText.body, color: !enabled ? colors.inkMuted : (danger ? colors.alarm : colors.ink)),
              ),
            ),
          ],
        );
    return showMenu<SharedGroupAction>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final action in menu.actions)
          PopupMenuItem(
            value: action,
            child: switch (action) {
              SharedGroupAction.roles => item(Icons.sell_rounded, '指派身分組'),
              SharedGroupAction.kick => item(Icons.person_remove_rounded, '移出群組', danger: true),
            },
          ),
        if (menu.reason != null)
          PopupMenuItem(enabled: false, child: item(Icons.info_outline_rounded, menu.reason!, enabled: false)),
      ],
    );
  }

  Future<void> _assignRoles(SharedGroup group, AdminGroupDetail detail, GroupMember member) async {
    final saved = await showAdminForm<bool>(
      context,
      RoleAssignForm(
        title: '指派「${group.name}」的身分組',
        roles: detail.roles,
        selected: member.roleIds,
        actor: Actor(unrestricted: detail.isOwner || _siteSuper, topPosition: detail.topPosition),
        actorPermissions: detail.permissions,
        onSave: (ids) => admin.setMemberRoles(group.id, member.id, ids),
      ),
    );
    if (saved == true && mounted) await _afterChange(group.id);
  }

  Future<void> _kick(SharedGroup group) async {
    final ok = await confirmDialog(
      context,
      title: '移出群組',
      message: '確定要將 ${widget.target.displayName} 移出「${group.name}」嗎？對方之後要重新受邀才能再加入',
      confirmLabel: '移出',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await admin.kickMember(group.id, widget.target.id);
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '移出群組失敗', message);
      return;
    }
    showToast(context, '已移出群組');
    await _afterChange(group.id);
  }

  // 群組有變動：丟掉這個群組的 detail（下次點開重讀），並重新載入頁面
  Future<void> _afterChange(String gid) async {
    _details.remove(gid);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = widget.target.sharedGroups;
    if (groups.isEmpty) {
      return const GroupedList(header: '共同群組', children: [_MutedRow('沒有共同群組')]);
    }
    final myGroups = context.watch<GroupsController>().groups;
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) {
        // 我在每個群組可能可以管理成員嗎（只用來決定要不要顯示「…」）
        final mine = {for (final g in myGroups ?? const []) g.id: g};
        bool maybeManage(String gid) {
          final g = mine[gid];
          if (g == null) return false;
          return g.isOwner ||
              hasPermission(g.permissions, GroupPermission.kickMembers) ||
              hasPermission(g.permissions, GroupPermission.manageRoles);
        }

        final siteSuper = _siteSuper;
        final anyMenu = siteSuper || groups.any((g) => maybeManage(g.id));
        return GroupedList(
          header: '共同群組',
          children: [
            for (final group in groups)
              Row(
                children: [
                  Expanded(child: _GroupRow(name: group.name, onTap: () => _openGroup(group.id))),
                  if (siteSuper || maybeManage(group.id))
                    Builder(
                      builder: (buttonContext) => SizedBox.square(
                        dimension: 44,
                        child: _loadingGid == group.id
                            ? Center(
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.inkMuted),
                                ),
                              )
                            : IconButton(
                                tooltip: '在「${group.name}」管理 ${widget.target.displayName}',
                                onPressed: _loadingGid != null ? null : () => _openMenu(buttonContext, group),
                                icon: Icon(Icons.more_horiz_rounded, color: colors.inkMuted),
                              ),
                      ),
                    )
                  // 有其他列顯示「…」時留一樣的寬度，讓箭頭對齊
                  else if (anyMenu)
                    const SizedBox(width: 44),
                  if (anyMenu) const SizedBox(width: 4),
                ],
              ),
          ],
        );
      },
    );
  }
}

/*
 * 「管理」：依全站權限與階層顯示（同網站 UserAdminActions）。
 * 指派身分組要「管理身分組」＋「進入後台」（讀得到身分組清單）；2FA 與後台使用者頁要「進入後台」＋「查看使用者」。
 */
class _AdminActions extends StatefulWidget {
  const _AdminActions({super.key, required this.target, required this.onChanged});

  final UserPublic target;
  final Future<void> Function() onChanged;

  @override
  State<_AdminActions> createState() => _AdminActionsState();
}

class _AdminActionsState extends State<_AdminActions> {
  final _access = SiteAccessController.shared;
  List<Role> _roles = const [];
  bool _rolesLoaded = false;
  // 身分組載入完成（或不需要載入）才判斷階層，避免先閃一下「比你高」
  bool _rolesDone = false;
  bool _rolesRequested = false;
  AdminUser? _adminUser;
  bool _adminUserRequested = false;

  bool get _canEdit => _access.can(SitePermission.manageUsers);
  bool get _canAssign => _access.can(SitePermission.manageRoles) && _access.can(SitePermission.viewAdmin);
  bool get _canOpenAdmin => _access.can(SitePermission.viewAdmin) && _access.can(SitePermission.viewUsers);
  bool get _canTotp => _access.can(SitePermission.viewUserTotp) && _canOpenAdmin;
  bool get _anyAction => _canEdit || _canAssign || _canTotp;
  bool get _needRoles => _anyAction && _access.can(SitePermission.viewAdmin);
  bool get _needAdminUser => _canEdit && _access.can(SitePermission.viewUsers);

  @override
  void initState() {
    super.initState();
    _access.addListener(_onAccess);
    _ensureLoaded();
  }

  @override
  void dispose() {
    _access.removeListener(_onAccess);
    super.dispose();
  }

  void _onAccess() {
    _ensureLoaded();
    if (mounted) setState(() {});
  }

  // 權限讀到之後才知道要讀什麼，所以權限變了也要再看一次
  void _ensureLoaded() {
    if (_needRoles && !_rolesRequested) {
      _rolesRequested = true;
      unawaited(_loadRoles());
    }
    if (_needAdminUser && !_adminUserRequested) {
      _adminUserRequested = true;
      unawaited(_loadAdminUser());
    }
  }

  // 失敗時跳錯誤（仍算載入完成，階層當作受限）
  Future<void> _loadRoles() async {
    final result = await admin.loadSiteRoles();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _roles = sortRoles(data);
          _rolesLoaded = true;
          _rolesDone = true;
        });
      case Err(:final message):
        setState(() => _rolesDone = true);
        await showErrorDialog(context, '載入身分組失敗', message);
    }
  }

  // 編輯 / 刪除表單要的完整資料（email 等）；只有「查看使用者」時才讀
  Future<void> _loadAdminUser() async {
    final result = await admin.loadAdminUser(widget.target.id);
    if (!mounted) return;
    switch (result) {
      case Ok(:final data) when data != null:
        setState(() => _adminUser = data.user);
      case Ok():
        await showErrorDialog(context, '載入使用者失敗', '找不到這位使用者');
      case Err(:final message):
        await showErrorDialog(context, '載入使用者失敗', message);
    }
  }

  // 每個操作成功後：重新載入頁面資料，以及這裡用到的身分組 / 使用者資料
  Future<void> _afterChange() async {
    await Future.wait([
      widget.onChanged(),
      if (_needRoles) _loadRoles(),
      if (_needAdminUser) _loadAdminUser(),
    ]);
  }

  Actor get _actor => Actor(unrestricted: _rolesLoaded && isSiteRoot(_access.topPosition, _roles), topPosition: _access.topPosition);

  AdminUser? get _editUser => _adminUser ?? (_needAdminUser ? null : widget.target.toAdminUser());

  Future<void> _edit(AdminUser user) async {
    final saved = await showAdminForm<bool>(context, UserEditForm(user: user));
    if (saved == true && mounted) await _afterChange();
  }

  Future<void> _assignRoles() async {
    final saved = await showAdminForm<bool>(
      context,
      RoleAssignForm(
        title: '指派身分組',
        roles: _roles,
        selected: [for (final role in widget.target.siteRoles) role.id],
        actor: _actor,
        actorPermissions: _access.permissions,
        onSave: (ids) => admin.setUserSiteRoles(widget.target.id, ids),
      ),
    );
    if (saved == true && mounted) await _afterChange();
  }

  // 2FA 在後台的使用者頁看（每次查看都會記錄，所以不在這裡直接載入金鑰）
  void _openAdminUser() {
    final navigator = Navigator.of(context);
    unawaited(pushAdminPage<void>(
      context,
      UserDetailView(
        userId: widget.target.id,
        onChanged: () => unawaited(widget.onChanged()),
        // 在後台刪掉了：回到主畫面
        onDeleted: () => navigator.popUntil((route) => route.isFirst),
      ),
    ));
  }

  Future<void> _delete(AdminUser user) async {
    final navigator = Navigator.of(context);
    final deleted = await showAdminForm<bool>(context, UserDeleteForm(user: user));
    if (deleted == true) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (!_anyAction && !_canOpenAdmin) return const SizedBox.shrink();
    if (_needRoles && !_rolesDone) return const SizedBox.shrink();

    // 對方的位置比自己高或同位：不能管理（看後台詳情不受階層限制）
    final manageable = canManageMember(_actor, topPosition: widget.target.topPosition);
    final editUser = _editUser;
    final showEdit = _canEdit && manageable;
    final showAssign = _canAssign && manageable;
    final showTotp = _canTotp && manageable;
    final outranked = _anyAction && !manageable;
    final chevron = Icon(Icons.chevron_right_rounded, color: colors.inkMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        GroupedList(
          header: '管理',
          children: [
            if (outranked) const _MutedRow('這位使用者的身分組比你高，無法管理'),
            if (showEdit)
              GroupedRow(label: '編輯名稱與 @ID', accent: true, onTap: editUser == null ? null : () => _edit(editUser)),
            if (showAssign)
              GroupedRow(label: '指派身分組', accent: true, onTap: _roles.isEmpty ? null : _assignRoles),
            if (showTotp) GroupedRow(label: '查看 2FA', accent: true, trailing: chevron, onTap: _openAdminUser),
            if (_canOpenAdmin) GroupedRow(label: '在後台開啟', accent: true, trailing: chevron, onTap: _openAdminUser),
          ],
        ),
        if (showEdit) ...[
          const SizedBox(height: 24),
          DangerButton(label: '刪除使用者', onPressed: editUser == null ? null : () => _delete(editUser)),
          const FootNote('會刪除帳號、只有他一個人的群組（含預設群組）與群組成員資格，無法恢復；擁有有其他成員的群組時要先轉移或刪除群組'),
        ],
      ],
    );
  }
}

// 共同群組的一列：群組圖示、名稱（太長時省略）、箭頭
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.workspaces_rounded, size: 20, color: colors.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// 分組清單裡的一列灰字說明
class _MutedRow extends StatelessWidget {
  const _MutedRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: TextStyle(fontSize: AppText.body, color: context.colors.inkMuted)),
        ),
      );
}

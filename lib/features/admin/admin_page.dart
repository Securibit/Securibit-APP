import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import 'admin_repository.dart' as repo;
import 'audit_section.dart';
import 'groups/groups_section.dart';
import 'notifications/broadcast_section.dart';
import 'notifications/notify_settings_section.dart';
import 'permission_defs.dart';
import 'roles/site_roles_section.dart';
import 'site_access.dart';
import 'users/users_section.dart';
import 'widgets/admin_widgets.dart';

/// 後台的區塊（同網站 src/app/admin/_components/sections.ts）；沒有權限的不顯示
enum AdminSection {
  overview('總覽', Icons.dashboard_rounded, SitePermission.viewAdmin),
  users('使用者', Icons.people_alt_rounded, SitePermission.viewUsers),
  // 有進入後台就能看（唯讀），有「管理身分組」才能修改
  roles('身分組', Icons.shield_rounded, SitePermission.viewAdmin),
  groups('群組', Icons.workspaces_rounded, SitePermission.manageGroups),
  broadcast('發送通知', Icons.send_rounded, SitePermission.sendNotifications),
  // 有進入後台就能看（唯讀），有「管理使用者」才能修改
  notifySettings('通知設定', Icons.notifications_rounded, SitePermission.viewAdmin),
  audit('操作紀錄', Icons.history_rounded, SitePermission.viewAuditLog);

  const AdminSection(this.title, this.icon, this.permission);

  final String title;
  final IconData icon;
  final int permission;
}

/// 開啟後台（整頁）
Future<void> openAdmin(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminPage()));

/*
 * 後台：
 * - 寬（≥ 720）：左邊是區塊清單（同網站後台的側欄），右邊是區塊內容；區塊裡再分「清單｜詳細資料」
 * - 窄（手機）：首頁是 iOS 分組清單（總覽的數字、管理的各區塊），點一個區塊開下一頁，清單再點開詳細資料
 */
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  AdminSection _section = AdminSection.overview;

  @override
  void initState() {
    super.initState();
    // 進後台時重新讀一次自己的權限
    unawaited(SiteAccessController.shared.reload());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) {
        final access = SiteAccessController.shared;
        if (!access.canViewAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('後台')),
            body: NoPermissionView(permission: permissionName(sitePermissionDefs, SitePermission.viewAdmin)),
          );
        }
        final sections = AdminSection.values.where((s) => access.can(s.permission)).toList();
        final current = sections.contains(_section) ? _section : AdminSection.overview;
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Scaffold(
                appBar: AppBar(title: const Text('後台')),
                body: SafeArea(top: false, child: _AdminHome(onOpen: (s) => _push(context, s))),
              );
            }
            final colors = context.colors;
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: _SectionSidebar(
                      sections: sections,
                      current: current,
                      onSelect: (s) => setState(() => _section = s),
                    ),
                  ),
                  VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6)),
                  Expanded(
                    child: Scaffold(
                      appBar: AppBar(title: Text(current.title), automaticallyImplyLeading: false),
                      body: SafeArea(
                        top: false,
                        left: false,
                        child: KeyedSubtree(
                          key: ValueKey(current),
                          child: current == AdminSection.overview
                              ? _AdminHome(onOpen: (s) => setState(() => _section = s))
                              : _sectionBody(current),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _push(BuildContext context, AdminSection section) {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(section.title)),
        body: SafeArea(top: false, child: _sectionBody(section)),
      ),
    )));
  }
}

Widget _sectionBody(AdminSection section) => switch (section) {
      AdminSection.overview => const SizedBox.shrink(),
      AdminSection.users => const UsersSection(),
      AdminSection.roles => const SiteRolesSection(),
      AdminSection.groups => const GroupsSection(),
      AdminSection.broadcast => const BroadcastSection(),
      AdminSection.notifySettings => const NotifySettingsSection(),
      AdminSection.audit => const AuditSection(),
    };

// 寬視窗左邊的區塊清單（同主畫面側欄的樣式）
class _SectionSidebar extends StatelessWidget {
  const _SectionSidebar({required this.sections, required this.current, required this.onSelect});

  final List<AdminSection> sections;
  final AdminSection current;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.surface1,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Text('後台', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final section in sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: section == current ? colors.surface2 : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          onTap: () => onSelect(section),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                Icon(section.icon, size: 20, color: section == current ? colors.accent : colors.inkMuted),
                                const SizedBox(width: 10),
                                Text(
                                  section.title,
                                  style: TextStyle(
                                    fontSize: AppText.body,
                                    fontWeight: section == current ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
 * 後台首頁（同網站 AdminHomeClient）：「總覽」一列一個數字與自己的身分組，「管理」是各區塊的入口。
 * 數字要有權限才載入，失敗就顯示「–」。
 */
class _AdminHome extends StatefulWidget {
  const _AdminHome({required this.onOpen});

  final ValueChanged<AdminSection> onOpen;

  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  int? _userTotal;
  int? _roleTotal;
  int? _groupTotal;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCounts());
  }

  Future<void> _loadCounts() async {
    final access = SiteAccessController.shared;
    final rolesFuture = repo.loadSiteRoles();
    final usersFuture = access.can(SitePermission.viewUsers) ? repo.loadAdminUsers('', 0, 1) : null;
    final groupsFuture = access.can(SitePermission.manageGroups) ? repo.loadAdminGroups('') : null;
    final roles = await rolesFuture;
    final users = await usersFuture;
    final groups = await groupsFuture;
    if (!mounted) return;
    setState(() {
      if (roles case Ok(:final data)) _roleTotal = data.length;
      if (users case Ok(:final data)) _userTotal = data.total;
      if (groups case Ok(:final data)) _groupTotal = data.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = SiteAccessController.shared;
    final profile = context.select<AuthController, String?>((a) => a.profile?.displayName);
    final canViewUsers = access.can(SitePermission.viewUsers);
    final canManageGroups = access.can(SitePermission.manageGroups);
    final sections = AdminSection.values.where((s) => s != AdminSection.overview && access.can(s.permission)).toList();
    String count(int? value) => value == null ? '–' : '$value';
    final counts = {AdminSection.users: _userTotal, AdminSection.roles: _roleTotal, AdminSection.groups: _groupTotal};

    return AdminScrollBody(
      onRefresh: () async {
        await Future.wait([access.reload(), _loadCounts()]);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: MutedText('歡迎回來，${profile ?? '管理員'}'),
        ),
        GroupedList(
          header: '總覽',
          children: [
            if (canViewUsers) GroupedRow(label: '使用者', value: count(_userTotal)),
            GroupedRow(label: '身分組', value: count(_roleTotal)),
            if (canManageGroups) GroupedRow(label: '群組', value: count(_groupTotal)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 3), child: Text('你的身分組', style: TextStyle(fontSize: AppText.body))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: access.access.roles.isEmpty
                        ? Text('只有 @everyone', textAlign: TextAlign.right, style: TextStyle(fontSize: AppText.body, color: context.colors.inkMuted))
                        : Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final r in access.access.roles) RoleChip(name: r.name, color: r.color)],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (sections.isEmpty)
          const ListEmpty('你還沒有任何後台區塊的權限')
        else
          GroupedList(
            header: '管理',
            children: [
              for (final section in sections)
                GroupedRow(
                  leading: Icon(section.icon, color: context.colors.inkMuted),
                  label: section.title,
                  value: counts[section] == null ? null : '${counts[section]}',
                  trailing: Icon(Icons.chevron_right_rounded, color: context.colors.inkMuted),
                  onTap: () => widget.onOpen(section),
                ),
            ],
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/widgets/empty_state.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../admin_repository.dart' as repo;
import '../hierarchy.dart';
import '../permission_defs.dart';
import '../site_access.dart';
import '../widgets/admin_widgets.dart';
import 'role_editor.dart';
import 'roles_manager.dart';

/*
 * 全站身分組（同網站 /admin/roles）：有進入後台就能看（唯讀），有「管理身分組」才能修改。
 * 只有最高位身分組的持有者不受階層限制（一般管理員也要遵守）。
 */
class SiteRolesSection extends StatefulWidget {
  const SiteRolesSection({super.key});

  @override
  State<SiteRolesSection> createState() => _SiteRolesSectionState();
}

class _SiteRolesSectionState extends State<SiteRolesSection> {
  List<Role>? _roles;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // 失敗時保留畫面上原本的清單
  Future<List<Role>?> _load() async {
    final result = await repo.loadSiteRoles();
    if (!mounted) return null;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _roles = sortRoles(data);
          _error = null;
        });
        return _roles;
      case Err(:final message):
        setState(() => _error = _roles == null ? message : null);
        return null;
    }
  }

  // 修改後重新載入清單；自己的身分組可能被改到，權限也一起重新讀
  Future<List<Role>?> _changed() async {
    final results = await Future.wait([_load(), SiteAccessController.shared.reload().then((_) => null)]);
    return results.first;
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    if (roles == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: EmptyState(title: '載入身分組失敗', message: _error, actionLabel: '重試', onAction: _load),
        );
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) {
        final access = SiteAccessController.shared;
        final canManage = access.can(SitePermission.manageRoles);
        final config = RoleEditorConfig(
          definitions: sitePermissionDefs,
          actor: Actor(unrestricted: access.unrestricted(roles), topPosition: access.topPosition),
          actorPermissions: access.permissions,
          canManage: canManage,
          onUpdate: repo.updateSiteRole,
          onDelete: repo.deleteSiteRole,
          onChanged: _changed,
        );
        final intro = Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: MutedText(
            canManage
                ? '身分組越上面越高，權限會合併計算。除了全站擁有者，只能編輯、指派比自己最高身分組還低的身分組，而且只能開啟自己也有的權限'
                : '你只能查看，需要「管理身分組」權限才能修改',
          ),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= adminSplitWidth;
            final manager = RolesManager(
              roles: roles,
              config: config,
              split: split,
              intro: intro,
              onCreate: repo.createSiteRole,
              onReorder: repo.reorderSiteRoles,
            );
            if (split) return manager;
            return AdminScrollBody(onRefresh: () async => _load(), children: [manager]);
          },
        );
      },
    );
  }
}

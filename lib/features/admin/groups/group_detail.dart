import 'package:flutter/material.dart';

import '../../groups/manage/group_view.dart';
import '../admin_nav.dart';
import '../permission_defs.dart';
import '../site_access.dart';
import '../users/user_detail.dart';

/*
 * 後台的群組管理（同網站 /admin/groups/[id] 的 GroupView adminMode）：和前台共用 GroupView，
 * 多了直接新增成員；點成員或紀錄的操作者開後台的使用者頁（要有「查看使用者」）。
 */
class AdminGroupDetailView extends StatelessWidget {
  const AdminGroupDetailView({super.key, required this.groupId, this.onChanged, this.onDeleted});

  final String groupId;
  // 群組資料改了（清單要重新整理）
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) {
        final canOpenUser = SiteAccessController.shared.can(SitePermission.viewUsers);
        return GroupView(
          groupId: groupId,
          adminMode: true,
          onChanged: onChanged,
          onExit: onDeleted,
          onOpenUser: canOpenUser ? (id) => pushAdminPage<void>(context, UserDetailView(userId: id)) : null,
        );
      },
    );
  }
}

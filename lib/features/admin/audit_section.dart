import 'package:flutter/material.dart';

import 'admin_models.dart';
import 'admin_nav.dart';
import 'admin_repository.dart' as repo;
import 'permission_defs.dart';
import 'site_access.dart';
import 'users/user_detail.dart';
import 'widgets/admin_widgets.dart';
import 'widgets/log_rows.dart';
import 'widgets/paged_list.dart';

/*
 * 全站操作紀錄（同網站 /admin/audit，需要「查看操作紀錄」）：一次 50 筆，「載入更多」往前載入。
 * 不含群組內的紀錄（那些在後台的群組頁裡）。
 */
class AuditSection extends StatefulWidget {
  const AuditSection({super.key});

  @override
  State<AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<AuditSection> {
  // 下拉重新整理時換一個 key 重新掛載清單
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    final canOpenUser = SiteAccessController.shared.can(SitePermission.viewUsers);
    return AdminScrollBody(
      maxWidth: 820,
      onRefresh: () async => setState(() => _generation++),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: MutedText('全站的身分組、使用者與 2FA 相關操作'),
        ),
        PagedList<AuditLog>(
          key: ValueKey('site-audit-$_generation'),
          load: (before) => repo.loadAdminAuditLog(before),
          pageSize: repo.auditPageSize,
          idOf: (log) => log.id,
          emptyText: '還沒有任何紀錄',
          errorTitle: '載入操作紀錄失敗',
          itemBuilder: (context, log, _) => AuditLogRow(
            log: log,
            onOpenActor: canOpenUser ? (actor) => pushAdminPage<void>(context, UserDetailView(userId: actor.id)) : null,
          ),
        ),
      ],
    );
  }
}

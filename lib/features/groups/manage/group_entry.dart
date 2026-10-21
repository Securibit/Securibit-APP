import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../admin/widgets/admin_widgets.dart';
import '../groups_controller.dart';
import 'group_forms.dart';
import 'group_rules.dart';
import 'group_view.dart';
import 'join_invite_form.dart';

/*
 * 群組管理的入口（工作包 A 實作）：其他畫面只透過這裡打開群組管理、新增群組、用邀請加入
 */

/// 打開群組管理；tab 是要先顯示的分頁（members、roles、invites、settings、audit）
Future<void> openGroupManage(BuildContext context, String groupId, {String? tab}) async {
  final initial = GroupManageTab.fromName(tab);
  // 寬視窗用對話框（同設定），窄螢幕整頁
  if (MediaQuery.sizeOf(context).width >= 720) {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
          child: _GroupManagePage(groupId: groupId, initialTab: initial, inDialog: true),
        ),
      ),
    );
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _GroupManagePage(groupId: groupId, initialTab: initial, inDialog: false),
  ));
}

/// 新增群組，建好後回傳新群組的 id
Future<String?> openCreateGroup(BuildContext context) async {
  final groups = context.read<GroupsController>();
  final id = await showAdminForm<String>(context, const GroupCreateForm());
  if (id == null || id.isEmpty) return null;
  // 重新讀取後選到新的群組
  await groups.reload();
  groups.select(id);
  return id;
}

/// 用邀請連結或代碼加入群組，加入後回傳群組 id
Future<String?> openJoinByInvite(BuildContext context, {String? code}) async {
  final groups = context.read<GroupsController>();
  final id = await showAdminForm<String>(context, JoinInviteForm(code: code));
  if (id == null || id.isEmpty) return null;
  await groups.reload();
  groups.select(id);
  return id;
}

class _GroupManagePage extends StatelessWidget {
  const _GroupManagePage({required this.groupId, required this.initialTab, required this.inDialog});

  final String groupId;
  final GroupManageTab? initialTab;
  final bool inDialog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理群組'),
        automaticallyImplyLeading: !inDialog,
        actions: [
          if (inDialog)
            IconButton(tooltip: '關閉', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: GroupView(
          groupId: groupId,
          initialTab: initialTab,
          // 離開或刪除群組之後關掉
          onExit: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

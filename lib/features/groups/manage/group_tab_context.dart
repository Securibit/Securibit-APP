import 'package:flutter/foundation.dart';

import '../../admin/admin_models.dart';
import '../../admin/hierarchy.dart';

/// 各分頁共用的資料
class GroupTabContext {
  const GroupTabContext({
    required this.detail,
    required this.actor,
    required this.myUid,
    required this.adminMode,
    required this.onChanged,
    required this.onExit,
    required this.onOpenUser,
  });

  final AdminGroupDetail detail;
  final Actor actor;
  final String? myUid;
  // 後台：可以直接新增成員；成員與紀錄的操作者點了開後台的使用者頁
  final bool adminMode;
  // 改了東西之後重新載入（也會更新主畫面的群組清單）
  final Future<void> Function() onChanged;
  // 離開或刪除了群組，這個畫面要關掉
  final VoidCallback onExit;
  // 點成員或操作者；null 時不能點
  final void Function(String userId)? onOpenUser;

  String get groupId => detail.group.id;
}

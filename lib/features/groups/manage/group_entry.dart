import 'package:flutter/material.dart';

/*
 * 群組管理的入口（工作包 A 實作）：其他畫面只透過這裡打開群組管理、新增群組、用邀請加入
 */

/// 打開群組管理；tab 是要先顯示的分頁（members、roles、invites、settings、audit）
Future<void> openGroupManage(BuildContext context, String groupId, {String? tab}) async {}

/// 新增群組，建好後回傳新群組的 id
Future<String?> openCreateGroup(BuildContext context) async => null;

/// 用邀請連結或代碼加入群組，加入後回傳群組 id
Future<String?> openJoinByInvite(BuildContext context, {String? code}) async => null;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../settings/settings_view.dart';
import 'activity_page.dart';
import 'profile_frame.dart';
import 'user_profile_page.dart';

/*
 * 個人資料的入口：其他畫面只透過這裡打開別人的個人頁面與自己的活動紀錄
 */

/// 打開某個使用者的個人頁；是自己時打開設定（自己的帳戶資料在那裡）
Future<void> openUserProfile(BuildContext context, String userId) async {
  final myUid = context.read<AuthController>().profile?.uid;
  if (myUid != null && userId.toLowerCase() == myUid.toLowerCase()) {
    await openSettings(context);
    return;
  }
  await showProfilePage(context, (inDialog) => UserProfilePage(userId: userId, inDialog: inDialog));
}

/// 打開自己的登入紀錄與帳號操作紀錄
Future<void> openActivity(BuildContext context) async {
  await showProfilePage(context, (inDialog) => ActivityPage(inDialog: inDialog));
}

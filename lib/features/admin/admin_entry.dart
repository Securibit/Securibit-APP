import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../auth/auth_controller.dart';
import 'site_access.dart';

/*
 * 側欄（桌面左欄、手機 Drawer）最下面的「後台」入口：只有有「進入後台」權限的人看得到。
 * 包住原本的側欄，不用改側欄本身；顯示時側欄的底部安全區域交給這一列處理。
 */
class AdminSidebarEntry extends StatelessWidget {
  const AdminSidebarEntry({super.key, required this.child, required this.onOpen});

  final Widget child;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthController, String?>((a) => a.profile?.uid);
    final access = SiteAccessController.shared;
    // 登入的使用者換了就重新讀權限（不能在 build 裡直接通知，排到下一輪）
    if (uid != access.uid) scheduleMicrotask(() => access.attach(uid));

    return ListenableBuilder(
      listenable: access,
      builder: (context, _) {
        // 一直用同一層結構包著側欄，權限讀完或改變時側欄才不會被整個重建（選取底色的動畫狀態會不見）
        final show = access.canViewAdmin && access.uid == uid;
        final colors = context.colors;
        return ColoredBox(
          color: colors.surface1,
          child: Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(context: context, removeBottom: show, child: child),
              ),
              if (show) ...[
                Divider(height: 0.5, color: colors.line.withValues(alpha: 0.6)),
                SafeArea(
                  top: false,
                  right: false,
                  child: InkWell(
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings_rounded, size: 22, color: colors.accent),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '後台',
                              style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import '../vault/vault_controller.dart';
import 'app_lock.dart';
import 'settings_controller.dart';

/// 設定：寬視窗用對話框，窄螢幕用整頁
Future<void> openSettings(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: const SettingsView()),
      ),
    );
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsView()));
}

// 設定頁：帳戶資料（可複製）、主題、加密群組與生物辨識、登出
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthController>();
    final settings = context.watch<SettingsController>();
    final vault = context.watch<VaultController>();
    final profile = auth.profile;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('設定'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (profile != null) ...[
            Row(
              children: [
                UserAvatar(name: profile.displayName, photoUrl: profile.photoUrl, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName, style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
                      if (profile.email.isNotEmpty)
                        Text(profile.email, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            GroupedList(
              header: '帳戶',
              footer: '名稱與 @ID 請到網站的帳戶頁修改',
              children: [
                GroupedRow(label: '名稱', value: profile.name.isEmpty ? '未設定' : profile.name),
                GroupedRow(
                  label: '@ID',
                  value: profile.username.isEmpty ? '未設定' : '@${profile.username}',
                  trailing: profile.username.isEmpty ? null : _CopyButton(text: '@${profile.username}', message: '已複製 @ID'),
                ),
                GroupedRow(label: 'UID', value: profile.uid, trailing: _CopyButton(text: profile.uid, message: '已複製 UID')),
                if (profile.email.isNotEmpty) GroupedRow(label: 'Email', value: profile.email),
              ],
            ),
          ],
          const SizedBox(height: 24),
          GroupedList(
            header: '外觀',
            children: [
              for (final (mode, label) in const [
                (ThemeMode.system, '跟隨系統'),
                (ThemeMode.light, '淺色'),
                (ThemeMode.dark, '深色'),
              ])
                GroupedRow(
                  label: label,
                  onTap: () => settings.setThemeMode(mode),
                  trailing: settings.themeMode == mode ? Icon(Icons.check_rounded, color: colors.accent) : null,
                ),
            ],
          ),
          if (vault.status != VaultStatus.off || AppPlatform.canUseBiometrics) ...[
            const SizedBox(height: 24),
            GroupedList(
              header: '安全',
              footer: AppPlatform.canUseBiometrics ? '開啟生物辨識鎖定後，每次打開 App 都要先通過 Face ID、Touch ID、指紋或裝置密碼' : null,
              children: [
                if (vault.status != VaultStatus.off)
                  GroupedRow(
                    label: '加密群組',
                    value: switch (vault.status) {
                      VaultStatus.unlocked => '已解鎖',
                      VaultStatus.loading => '確認中',
                      _ => '已鎖定',
                    },
                    trailing: vault.status == VaultStatus.unlocked
                        ? TextButton(
                            onPressed: () async {
                              await vault.lock();
                              if (context.mounted) showToast(context, '已鎖定加密群組');
                            },
                            child: const Text('立即鎖定'),
                          )
                        : null,
                  ),
                if (AppPlatform.canUseBiometrics)
                  GroupedRow(
                    label: '生物辨識鎖定',
                    trailing: Switch.adaptive(
                      value: settings.biometricLock,
                      onChanged: (value) async {
                        // 開啟前先驗證一次，確定這台裝置可以用
                        if (value) {
                          final error = await authenticateOwner();
                          if (!context.mounted) return;
                          if (error != null) {
                            await showErrorDialog(context, '無法開啟生物辨識鎖定', error);
                            return;
                          }
                        }
                        settings.setBiometricLock(value);
                      },
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          GroupedList(
            children: [
              GroupedRow(
                label: '登出',
                danger: true,
                onTap: () async {
                  final ok = await confirmDialog(
                    context,
                    title: '登出',
                    message: '登出後這台裝置的離線資料與記住的加密密碼都會清除',
                    confirmLabel: '登出',
                    danger: true,
                  );
                  if (!ok || !context.mounted) return;
                  final navigator = Navigator.of(context);
                  final error = await context.read<AuthController>().signOut();
                  if (!context.mounted) return;
                  if (error != null) {
                    await showErrorDialog(context, '登出失敗', error);
                    return;
                  }
                  navigator.popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text, required this.message});

  final String text;
  final String message;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '複製',
        visualDensity: VisualDensity.compact,
        onPressed: () => copyText(context, text, message: message),
        icon: Icon(Icons.copy_rounded, size: 18, color: context.colors.inkMuted),
      );
}

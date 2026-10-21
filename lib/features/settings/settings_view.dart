import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import '../menubar/desktop_tray.dart';
import '../update/update_controller.dart';
import '../update/update_dialog.dart';
import '../vault/vault_controller.dart';
import 'app_lock.dart';
import 'lock/app_lock_controller.dart';
import 'lock/lock_policy.dart';
import 'lock/lock_secret.dart';
import 'lock/lock_setup_page.dart';
import 'lock/lock_wait.dart';
import 'screen_privacy.dart';
import 'settings_controller.dart';

// 設定已經開著（macOS 選單列的「設定…」不會再開一個）
bool _settingsOpen = false;

/// 設定：寬視窗用對話框，窄螢幕用整頁
Future<void> openSettings(BuildContext context) async {
  if (_settingsOpen) return;
  _settingsOpen = true;
  try {
    await _showSettings(context);
  } finally {
    _settingsOpen = false;
  }
}

Future<void> _showSettings(BuildContext context) {
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

// 設定頁：帳戶資料（可複製）、主題、加密群組、App 鎖定、截圖、選單列（macOS）、關於與更新（iOS 沒有）、登出
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthController>();
    final settings = context.watch<SettingsController>();
    final vault = context.watch<VaultController>();
    final updatesSupported = context.select<UpdateController, bool>((u) => u.supported);
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
          if (vault.status != VaultStatus.off) ...[
            const SizedBox(height: 24),
            GroupedList(
              header: '加密',
              children: [
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
              ],
            ),
          ],
          const SizedBox(height: 24),
          const _LockSection(),
          const SizedBox(height: 24),
          GroupedList(
            header: '隱私',
            footer: ScreenPrivacy.description,
            children: [
              GroupedRow(
                label: '允許截圖',
                trailing: Switch.adaptive(
                  // Linux 擋不了，一律顯示為允許且不能切換
                  value: ScreenPrivacy.canBlockCapture ? settings.allowScreenshots : true,
                  onChanged: ScreenPrivacy.canBlockCapture ? settings.setAllowScreenshots : null,
                ),
              ),
            ],
          ),
          if (DesktopTray.supported) ...[
            const SizedBox(height: 24),
            const _MenuBarSection(),
          ],
          if (updatesSupported) ...[
            const SizedBox(height: 24),
            const _UpdateSection(),
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

/*
 * App 鎖定：鎖定方式（關閉／九宮格圖形／四位數／六位數密碼）、變更、生物辨識、自動鎖定時間。
 * 換方式或關閉前要先輸入目前的圖形或密碼；生物辨識只在設定了圖形或密碼後才能打開。
 */
class _LockSection extends StatelessWidget {
  const _LockSection();

  Future<void> _choose(BuildContext context, AppLockController lock, LockType type) async {
    if (type == lock.type && type != LockType.off) return;
    if (type == LockType.off && !lock.enabled) return;
    await openLockSetup(context, lock, type);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lock = context.watch<SettingsController>().appLock;
    final current = lock.enabled ? lock.type : LockType.off;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedList(
          header: '鎖定方式',
          footer: lock.available ? '設定後，打開 App 或離開一段時間再回來都要先解鎖' : '這台裝置無法使用安全儲存，不能設定鎖定',
          children: [
            for (final type in LockType.values)
              GroupedRow(
                label: type.label,
                onTap: lock.available ? () => _choose(context, lock, type) : null,
                trailing: current == type ? Icon(Icons.check_rounded, color: colors.accent) : null,
              ),
          ],
        ),
        if (lock.enabled) ...[
          const SizedBox(height: 24),
          GroupedList(
            footer: AppPlatform.canUseBiometrics ? '生物辨識失敗或取消時，可以改用${lockNoun(lock.type)}解鎖' : null,
            children: [
              GroupedRow(
                label: '變更${lockNoun(lock.type)}',
                accent: true,
                onTap: () => openLockSetup(context, lock, lock.type),
              ),
              if (AppPlatform.canUseBiometrics)
                GroupedRow(
                  label: biometricUnlockLabel,
                  trailing: Switch.adaptive(
                    value: lock.biometric,
                    onChanged: (value) async {
                      // 打開前先驗證一次，確定這台裝置可以用
                      if (value) {
                        final error = await authenticateOwner();
                        if (!context.mounted) return;
                        if (error != null) {
                          if (error != biometricRejected) await showErrorDialog(context, '無法使用生物辨識', error);
                          return;
                        }
                      }
                      await lock.setBiometric(value);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          GroupedList(
            header: '自動鎖定',
            footer: '離開 App 超過這段時間再回來要重新解鎖；重新打開 App 一定要解鎖',
            children: [
              for (final timeout in LockTimeout.values)
                GroupedRow(
                  label: timeout.label,
                  onTap: () => lock.setTimeout(timeout),
                  trailing: lock.timeout == timeout ? Icon(Icons.check_rounded, color: colors.accent) : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/*
 * 常駐圖示：macOS 的選單列、Linux 的系統匣（關視窗只是藏起來）與登入時自動開啟。
 * macOS 的登入時自動開啟用 SMAppService，macOS 13 以前沒有，開關停用並說明；Linux 寫 autostart 檔，一律可用。
 */
class _MenuBarSection extends StatelessWidget {
  const _MenuBarSection();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final launch = settings.launchAtLogin;
    final place = DesktopTray.place;
    final linux = Platform.isLinux;
    final notes = [
      if (!settings.showInMenuBar)
        '關閉視窗就會結束 Securibit'
      else if (linux)
        '關閉視窗後 Securibit 會留在系統匣，點圖示就能複製驗證碼；選「結束 Securibit」才會結束。桌面沒有系統匣時關閉視窗一樣會結束'
      else
        '關閉視窗後 Securibit 會留在選單列，點圖示就能複製驗證碼；按 ⌘Q 才會結束',
      if (linux) 'GNOME 要先安裝 AppIndicator 擴充功能才看得到系統匣圖示；KDE、XFCE、Cinnamon 可以直接使用',
      if (launch == LaunchAtLoginState.unsupported) '登入時自動開啟需要 macOS 13 以上',
      if (launch == LaunchAtLoginState.requiresApproval) '要到「系統設定 › 一般 › 登入項目」允許 Securibit 才會自動開啟',
    ];
    return GroupedList(
      header: place,
      footer: notes.join('\n'),
      children: [
        GroupedRow(
          label: '在$place顯示',
          trailing: Switch.adaptive(value: settings.showInMenuBar, onChanged: settings.setShowInMenuBar),
        ),
        GroupedRow(
          label: '登入時自動開啟',
          trailing: Switch.adaptive(
            value: launch.on,
            onChanged: launch == LaunchAtLoginState.unsupported
                ? null
                : (value) async {
                    final error = await settings.setLaunchAtLogin(value);
                    if (!context.mounted) return;
                    if (error != null) {
                      await showErrorDialog(context, linux ? '無法變更自動啟動' : '無法變更登入項目', error);
                    } else if (settings.launchAtLogin == LaunchAtLoginState.requiresApproval) {
                      await LaunchAtLogin.openSystemSettings();
                    }
                  },
          ),
        ),
      ],
    );
  }
}

/*
 * 關於與更新：目前版本、手動檢查更新、啟動時檢查更新。
 * 沒有設定 UPDATE_REPO（自己架後端的人關掉檢查更新）時只顯示版本。
 */
class _UpdateSection extends StatelessWidget {
  const _UpdateSection();

  Future<void> _check(BuildContext context, UpdateController updates) async {
    final release = await updates.check();
    if (!context.mounted) return;
    if (release != null) {
      // 手動檢查時，略過的版本也照樣提示
      await showUpdateDialog(context, updates, release);
    } else if (updates.status == UpdateStatus.failed) {
      showToast(context, '無法檢查更新，請檢查網路連線');
    } else if (updates.status == UpdateStatus.upToDate) {
      showToast(context, '已是最新版本');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final updates = context.watch<UpdateController>();
    final checking = updates.status == UpdateStatus.checking;
    final status = switch (updates.status) {
      UpdateStatus.checking => '檢查中',
      UpdateStatus.upToDate => '已是最新版本',
      UpdateStatus.available => '有新版本 ${updates.latest?.version}',
      UpdateStatus.failed => '無法檢查',
      UpdateStatus.idle => null,
    };
    return GroupedList(
      header: '關於與更新',
      footer: updates.enabled
          ? '從 GitHub 的 ${updates.repo} 檢查新版本，有新版本時提示並用瀏覽器下載，不會自動安裝'
              '${DesktopTray.supported && updates.checkOnLaunch ? '；常駐在${DesktopTray.place}時每天再檢查一次' : ''}'
          : null,
      children: [
        GroupedRow(label: '版本', value: updates.currentVersion ?? '讀取中'),
        if (updates.enabled) ...[
          GroupedRow(
            label: '檢查更新',
            accent: true,
            value: status,
            trailing: checking
                ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.inkMuted))
                : null,
            onTap: checking ? null : () => _check(context, updates),
          ),
          GroupedRow(
            label: '啟動時檢查更新',
            trailing: Switch.adaptive(value: updates.checkOnLaunch, onChanged: updates.setCheckOnLaunch),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/web_pages.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import '../menubar/desktop_tray.dart';
import '../notifications/notification_settings_page.dart';
import '../profile/account_section.dart';
import '../update/update_controller.dart';
import '../update/update_dialog.dart';
import '../vault/vault_settings_section.dart';
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

// 設定頁：帳戶資料（可編輯）、通知、主題、加密、App 鎖定、截圖、選單列（macOS）、關於與更新（iOS 沒有）、登出與刪除帳戶
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthController>();
    final settings = context.watch<SettingsController>();
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
            AccountSection(profile: profile),
            const SizedBox(height: 24),
            // 通知開關（同網站帳戶設定的「通知」分頁）
            GroupedList(
              children: [
                GroupedRow(
                  label: '通知',
                  trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
                  onTap: () => openNotificationSettings(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
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
          const SizedBox(height: 24),
          const VaultSettingsSection(),
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
              for (final (label, path) in const [('隱私權政策', '/privacy'), ('免責聲明', '/disclaimer')])
                GroupedRow(
                  label: label,
                  trailing: Icon(Icons.open_in_new_rounded, size: 20, color: colors.inkMuted),
                  onTap: () => openWebPage(path),
                ),
            ],
          ),
          const SizedBox(height: 24),
          GroupedList(
            footer: profile == null ? null : '刪除帳戶會一併永久刪除所有驗證碼金鑰，刪除前請確認已在各服務關閉兩步驟驗證或改用其他驗證器',
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
              if (profile != null) GroupedRow(label: '刪除帳戶', danger: true, onTap: () => confirmDeleteAccount(context)),
            ],
          ),
        ],
      ),
    );
  }
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
 * 常駐圖示：macOS 的選單列、Linux 與 Windows 的系統匣（關視窗只是藏起來）與登入時自動開啟。
 * macOS 的登入時自動開啟用 SMAppService，macOS 13 以前沒有，開關停用並說明；
 * Linux 寫 autostart 檔、Windows 寫登錄檔的 Run 值，一律可用。
 */
class _MenuBarSection extends StatelessWidget {
  const _MenuBarSection();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final launch = settings.launchAtLogin;
    final platform = TrayPlatform.current;
    final place = platform.place;
    final notes = trayNotes(
      platform,
      showInTray: settings.showInMenuBar,
      showCodes: settings.showCodesInMenuBar,
      launch: launch,
    );
    return GroupedList(
      header: place,
      footer: notes.join('\n'),
      children: [
        GroupedRow(
          label: '在$place顯示',
          trailing: Switch.adaptive(value: settings.showInMenuBar, onChanged: settings.setShowInMenuBar),
        ),
        if (settings.showInMenuBar)
          GroupedRow(
            label: '在$place顯示驗證碼',
            trailing: Switch.adaptive(value: settings.showCodesInMenuBar, onChanged: settings.setShowCodesInMenuBar),
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
                      await showErrorDialog(context, platform == TrayPlatform.macos ? '無法變更登入項目' : '無法變更自動啟動', error);
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
 * 關於與更新：目前版本、檢查更新（和自動檢查同一套流程，會顯示下載與安裝的狀態）、自動檢查更新。
 * 下載好之後多一列「重新啟動並更新」（Linux .deb、Android 是「立即更新」）。
 * 沒有設定 UPDATE_REPO（自己架後端的人關掉檢查更新）時只顯示版本。
 */
class _UpdateSection extends StatelessWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final updates = context.watch<UpdateController>();
    final version = updates.latest?.version;
    final progress = updates.progress;
    final busy = const {UpdateStatus.checking, UpdateStatus.downloading, UpdateStatus.installing}.contains(updates.status);
    final status = switch (updates.status) {
      UpdateStatus.checking => '檢查中',
      UpdateStatus.upToDate => '已是最新版本',
      UpdateStatus.available => '有新版本 $version',
      UpdateStatus.downloading => '正在下載 $version${progress == null ? '' : '（${(progress * 100).floor()}%）'}',
      UpdateStatus.retrying => '下載失敗，稍後重試',
      UpdateStatus.ready => '$version 已準備好',
      UpdateStatus.installing => '正在安裝',
      UpdateStatus.failed => '無法檢查',
      UpdateStatus.idle => null,
    };
    final source = updates.usesTestFeed ? '測試用的 ${updates.feedUrl}' : 'GitHub 的 ${updates.repo}';
    final footer = switch (updates.status) {
      UpdateStatus.available when updates.manualReason != null => updates.manualReason!,
      _ => '從 $source 檢查新版本，有新版本時在背景下載並確認檔案完整，好了會提示重新啟動更新'
          '${updates.checkOnLaunch ? '；開著的時候每小時再檢查一次' : ''}',
    };
    return GroupedList(
      header: '關於與更新',
      footer: updates.enabled ? footer : null,
      children: [
        GroupedRow(label: '版本', value: updates.currentVersion ?? '讀取中'),
        if (updates.enabled) ...[
          if (updates.status == UpdateStatus.ready)
            GroupedRow(
              label: updates.installLabel,
              accent: true,
              value: '$version',
              onTap: () => installUpdate(context, updates),
            ),
          GroupedRow(
            label: '檢查更新',
            accent: true,
            value: status,
            trailing: busy
                ? SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      // 知道進度時畫出進度，不知道時轉圈
                      value: updates.status == UpdateStatus.downloading ? progress : null,
                      color: colors.inkMuted,
                    ),
                  )
                : null,
            onTap: busy ? null : () => checkForUpdatesNow(context, updates),
          ),
          GroupedRow(
            label: '自動檢查更新',
            trailing: Switch.adaptive(value: updates.checkOnLaunch, onChanged: updates.setCheckOnLaunch),
          ),
        ],
      ],
    );
  }
}

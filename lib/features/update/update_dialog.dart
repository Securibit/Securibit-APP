import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import 'release.dart';
import 'release_notes_view.dart';
import 'update_controller.dart';
import 'update_installer.dart';

// 提示已經開著（自動檢查與手動檢查同時查到時不會疊兩個）
bool _open = false;

/// 手動檢查更新（設定頁的「檢查更新」、Mac 上方選單的「檢查更新…」）：和自動檢查同一套流程，
/// 下載好了就提示安裝，還在下載就說一聲，沒有新版就說已是最新
Future<void> checkForUpdatesNow(BuildContext context, UpdateController updates) async {
  if (!updates.enabled) {
    showToast(context, '這個版本沒有設定檢查更新');
    return;
  }
  final pending = updates.latest;
  if (pending != null) {
    switch (updates.status) {
      case UpdateStatus.ready:
        await showUpdatePrompt(context, updates, pending);
        return;
      case UpdateStatus.installing:
        showToast(context, '正在安裝更新');
        return;
      case UpdateStatus.downloading:
        showToast(context, '正在下載 ${pending.version}${_percent(updates)}，好了會提示你');
        return;
      default:
        break;
    }
  }
  final release = await updates.check();
  if (!context.mounted) return;
  if (release != null) {
    switch (updates.status) {
      case UpdateStatus.ready:
      case UpdateStatus.available:
        await showUpdatePrompt(context, updates, release);
      case UpdateStatus.retrying:
        showToast(context, '下載 ${release.version} 失敗，稍後會自動重試');
      default:
        showToast(context, '找到新版本 ${release.version}，正在背景下載，好了會提示你');
    }
  } else if (updates.status == UpdateStatus.failed) {
    showToast(context, '無法檢查更新，請檢查網路連線');
  } else if (updates.status == UpdateStatus.upToDate) {
    showToast(context, '已是最新版本');
  }
}

String _percent(UpdateController updates) {
  final progress = updates.progress;
  return progress == null ? '' : '（${(progress * 100).floor()}%）';
}

/// 有新版本的提示：下載好了是「新版本已準備好」（稍後／重新啟動並更新），不能自動安裝時是用瀏覽器下載
Future<void> showUpdatePrompt(BuildContext context, UpdateController updates, AppRelease release) async {
  if (_open) return;
  _open = true;
  try {
    await showDialog<void>(context: context, builder: (_) => _UpdateDialog(updates: updates, release: release));
  } finally {
    _open = false;
  }
}

/// 安裝下載好的版本；失敗時說明原因並提供用瀏覽器下載。Android 還沒允許安裝時先帶使用者去設定
Future<void> installUpdate(BuildContext context, UpdateController updates) async {
  final message = updates.installer.installingMessage;
  if (message != null) showToast(context, message);
  final outcome = await updates.install();
  if (!context.mounted) return;
  switch (outcome.result) {
    case InstallResult.started:
      return;
    case InstallResult.needsPermission:
      await _askInstallPermission(context, updates);
    case InstallResult.cancelled:
    case InstallResult.failed:
      final release = updates.latest;
      await _showInstallError(context, outcome.message ?? '無法安裝更新', release == null ? null : updates.downloadUrl(release));
  }
}

// Android：「安裝不明應用程式」還沒允許。打開設定，使用者回到 App 時再試一次
Future<void> _askInstallPermission(BuildContext context, UpdateController updates) async {
  final ok = await confirmDialog(
    context,
    title: '允許安裝更新',
    message: '要先允許 Securibit 安裝應用程式才能更新。按「前往設定」後打開「允許這個來源」，再回到 Securibit',
    confirmLabel: '前往設定',
  );
  if (!ok || !context.mounted) return;
  final resumed = Completer<void>();
  final listener = AppLifecycleListener(onResume: () {
    if (!resumed.isCompleted) resumed.complete();
  });
  await updates.installer.openPermissionSettings();
  await resumed.future;
  listener.dispose();
  if (!context.mounted) return;
  final outcome = await updates.install();
  if (!context.mounted || outcome.result == InstallResult.started) return;
  if (outcome.result == InstallResult.needsPermission) {
    showToast(context, '還沒有允許安裝，這次沒有更新');
  } else {
    final release = updates.latest;
    await _showInstallError(context, outcome.message ?? '無法安裝更新', release == null ? null : updates.downloadUrl(release));
  }
}

Future<void> _showInstallError(BuildContext context, String message, String? url) {
  final colors = context.colors;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('無法更新'),
      content: Text(url == null ? message : '$message\n\n也可以用瀏覽器下載新版，自己安裝'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('好'),
        ),
        if (url != null)
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _openInBrowser(url);
            },
            child: const Text('用瀏覽器下載'),
          ),
      ],
    ),
  );
}

Future<bool> _openInBrowser(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.updates, required this.release});

  final UpdateController updates;
  final AppRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateController get updates => widget.updates;
  AppRelease get release => widget.release;
  bool get _ready => updates.status == UpdateStatus.ready || updates.status == UpdateStatus.installing;

  // 先關掉提示，失敗與 Android 的權限說明用另外的對話框（開在 Navigator 底下，不跟著這個提示關掉）
  Future<void> _install() async {
    final navigator = Navigator.of(context)..pop();
    await installUpdate(navigator.context, updates);
  }

  Future<void> _download() async {
    final navigator = Navigator.of(context);
    final opened = await _openInBrowser(updates.downloadUrl(release));
    if (!mounted) return;
    if (!opened) {
      await showErrorDialog(context, '無法開啟瀏覽器', '請到這個網址下載：\n${release.pageUrl}');
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = releaseNoteBlocks(release.notes);
    final current = updates.currentVersion;
    final ready = _ready;
    final reason = ready ? null : updates.manualReason;

    return AlertDialog(
      title: Text(ready ? '新版本已準備好，強烈建議更新' : '有新版本，強烈建議更新'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Securibit ${release.version} ${ready ? '已下載完成' : '已推出'}${current == null ? '' : '，目前是 $current'}'),
            const SizedBox(height: 6),
            Text(
              '新版本包含錯誤修正與安全性更新，請盡快更新',
              style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: colors.alarm),
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(reason, style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: colors.ink)),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              // 更新內容太長時在框裡捲動，按鈕一直看得到
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(width: double.infinity, child: ReleaseNotesView(blocks: notes)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // 稍後：下一次自動檢查（一小時內）會再提示；macOS 結束 App 時也會順便更新
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('稍後'),
        ),
        if (ready)
          FilledButton(onPressed: _install, child: Text(updates.installLabel))
        else
          FilledButton(onPressed: _download, child: const Text('用瀏覽器下載')),
      ],
    );
  }
}

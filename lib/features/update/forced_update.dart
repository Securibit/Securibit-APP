import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/lock_backdrop.dart';
import '../../core/widgets/logo.dart';
import 'min_version.dart';
import 'update_controller.dart';
import 'update_dialog.dart';

/// Google Play 的商店頁
const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.bityo.securibit';

/// 強制更新時這台怎麼更新
enum ForcedUpdateRoute {
  // 桌面與 GitHub 版 Android：用現有的更新流程，在背景下載後「重新啟動並更新」
  selfUpdate,
  // Google Play 版：打開商店頁
  playStore,
  // iOS：到 App Store 或 TestFlight 更新
  appStore,
  // 沒有設定檢查更新（自己架的）：用瀏覽器下載
  browser,
}

ForcedUpdateRoute forcedUpdateRoute({required bool isIOS, required bool isAndroid, required bool updatesEnabled, required bool updatesSupported}) {
  if (isIOS) return ForcedUpdateRoute.appStore;
  if (updatesEnabled) return ForcedUpdateRoute.selfUpdate;
  // Android 但不能自己更新：Google Play 版
  if (isAndroid && !updatesSupported) return ForcedUpdateRoute.playStore;
  return ForcedUpdateRoute.browser;
}

/*
 * 包在 MaterialApp.builder 的最外層（App 鎖定外面）：目前的版本低於後台設定的最低版本時，
 * 整頁蓋上「強制更新」，不能關、不用先解鎖（跟更新提示一樣蓋在鎖定畫面上）。
 * 有自己的 Navigator，安裝時的權限說明、錯誤對話框才跳得出來。
 */
class ForcedUpdateGate extends StatelessWidget {
  const ForcedUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final required = context.select<MinVersionController, MinVersion?>((c) => c.required);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 擋住時下面的畫面不接受操作（也不用畫）
        Offstage(offstage: required != null, child: TickerMode(enabled: required == null, child: child)),
        if (required != null)
          HeroControllerScope.none(
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => ForcedUpdatePage(minimum: required)),
            ),
          ),
      ],
    );
  }
}

class ForcedUpdatePage extends StatefulWidget {
  const ForcedUpdatePage({super.key, required this.minimum});

  final MinVersion minimum;

  @override
  State<ForcedUpdatePage> createState() => _ForcedUpdatePageState();
}

class _ForcedUpdatePageState extends State<ForcedUpdatePage> {
  bool _started = false;

  // 開始在背景下載（自動檢查更新關掉了也要下載）；已經在下載或下載好就不動
  void _ensureDownload(UpdateController updates) {
    if (_started || !updates.enabled) return;
    if (const {UpdateStatus.idle, UpdateStatus.upToDate}.contains(updates.status)) {
      _started = true;
      scheduleMicrotask(() => unawaited(updates.check()));
    }
  }

  Future<void> _openUrl(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) await showErrorDialog(context, '無法開啟', '請到這個網址下載：\n$url');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final updates = context.watch<UpdateController>();
    final current = context.select<MinVersionController, String?>((c) => c.currentVersion);
    // 還在讀更新設定（是不是 Google Play 版、有沒有設定 repo）時先當成可以自己更新，顯示「正在檢查新版本」
    final pending = !updates.loaded && updates.target != null;
    final route = forcedUpdateRoute(
      isIOS: Platform.isIOS,
      isAndroid: Platform.isAndroid,
      updatesEnabled: updates.enabled || pending,
      updatesSupported: updates.supported,
    );
    if (route == ForcedUpdateRoute.selfUpdate) _ensureDownload(updates);
    final message = widget.minimum.message.isNotEmpty
        ? widget.minimum.message
        : '這個版本已經不能使用，請更新到 ${widget.minimum.version} 以上才能繼續使用 Securibit';

    return Scaffold(
      body: LockBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 64),
                    const SizedBox(height: 20),
                    const Text('強制更新', textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text(
                      '目前是 ${current ?? '未知版本'}，最低需要 ${widget.minimum.version}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(width: double.infinity, child: _actions(context, route, updates)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, ForcedUpdateRoute route, UpdateController updates) {
    final colors = context.colors;
    Widget note(String text) => Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted));
    Widget button(String label, VoidCallback onPressed) => FilledButton(onPressed: onPressed, child: Text(label));

    switch (route) {
      case ForcedUpdateRoute.appStore:
        return note('請到 App Store 或 TestFlight 更新 Securibit');
      case ForcedUpdateRoute.playStore:
        return button('前往 Google Play 更新', () => _openUrl(playStoreUrl));
      case ForcedUpdateRoute.browser:
        return note('請到 Securibit 的下載頁下載新版');
      case ForcedUpdateRoute.selfUpdate:
        break;
    }

    final release = updates.latest;
    final browserUrl = release != null ? updates.downloadUrl(release) : updates.releasesPageUrl;
    final browser = browserUrl == null
        ? null
        : TextButton(onPressed: () => _openUrl(browserUrl), child: const Text('用瀏覽器下載'));
    final progress = updates.progress;

    final List<Widget> children = switch (updates.status) {
      UpdateStatus.ready => [
          button(updates.installLabel, () => installUpdate(context, updates)),
          const SizedBox(height: 8),
          note('${release?.version ?? '新版本'} 已下載完成'),
        ],
      UpdateStatus.installing => [note('正在安裝更新'), const SizedBox(height: 12), const LinearProgressIndicator()],
      UpdateStatus.downloading => [
          note('正在下載 ${release?.version ?? '新版本'}${progress == null ? '' : '（${(progress * 100).floor()}%）'}'),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: progress, minHeight: 6)),
        ],
      UpdateStatus.retrying => [note('下載失敗，稍後會自動重試'), if (browser != null) ...[const SizedBox(height: 8), browser]],
      UpdateStatus.available => [
          note(updates.manualReason ?? '這台裝置無法自動更新，請用瀏覽器下載新版'),
          if (browser != null) ...[const SizedBox(height: 12), FilledButton(onPressed: () => _openUrl(browserUrl!), child: const Text('用瀏覽器下載'))],
        ],
      UpdateStatus.failed => [
          note('無法檢查更新，請檢查網路連線'),
          const SizedBox(height: 12),
          button('重試', () => unawaited(updates.check())),
          if (browser != null) ...[const SizedBox(height: 4), browser],
        ],
      UpdateStatus.upToDate => [note('還找不到可以下載的新版本，請稍後再試'), if (browser != null) ...[const SizedBox(height: 8), browser]],
      UpdateStatus.idle || UpdateStatus.checking => [
          note('正在檢查新版本'),
          const SizedBox(height: 12),
          const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

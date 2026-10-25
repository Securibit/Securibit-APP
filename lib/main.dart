import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/platform.dart';
import 'core/security_core.dart';
import 'core/window_visibility.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/refresh_guard_client.dart';
import 'features/auth/secure_session_storage.dart';
import 'features/cache/offline_cache.dart';
import 'features/groups/groups_controller.dart';
import 'features/links/deep_link_controller.dart';
import 'features/links/deep_link_service.dart';
import 'features/menubar/menu_bar_codes.dart';
import 'features/menubar/menu_bar_service.dart';
import 'features/notifications/desktop_notifier.dart';
import 'features/notifications/notification_link_queue.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/notifications/push/android_push.dart';
import 'features/notifications/push/push_registrar.dart';
import 'features/profile/session_device.dart';
import 'features/settings/settings_controller.dart';
import 'features/update/min_version.dart';
import 'features/update/release.dart';
import 'features/update/update_controller.dart';
import 'features/update/update_installer.dart';
import 'features/update/update_service.dart';
import 'features/vault/vault_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows 登入時自動開啟（--hidden）：主視窗一開始就藏在系統匣，App 鎖定與更新提示都當作視窗藏著
  if (Platform.isWindows && WindowVisibility.launchedHidden(args)) WindowVisibility.visible.value = false;
  // Rust 安全核心（TOTP、加密群組、App 鎖定雜湊、記憶體裡的金鑰）
  await initSecurityCore();
  if (!Env.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  try {
    AppPlatform.version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // 讀不到就不帶版本，登入紀錄只顯示 Securibit App
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    // 換新 token 只在伺服器明確拒絕時才登出，網路或伺服器暫時出錯時保留 session
    httpClient: RefreshGuardClient(),
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SecureSessionStorage(),
    ),
  );
  // 「已登入的裝置」要顯示的裝置名稱、平台與 App 版本
  SessionDeviceReporter.start();

  final settings = SettingsController();
  await settings.load();

  // 最低版本：開 App 就檢查（不用登入），低於最低版本時整頁蓋上「強制更新」（見 ForcedUpdateGate）
  final minVersion = MinVersionController();
  unawaited(minVersion.start());

  const cache = OfflineCache();
  final vault = VaultController();
  final groups = GroupsController(cache: cache);
  // 鈴鐺與收件匣；點了推播或系統通知等著打開的畫面
  final notifications = NotificationsController();
  final notificationLinks = NotificationLinkQueue();
  // 桌面：App 開著或常駐時，新的通知跳系統通知
  DesktopNotifier.start(notifications, notificationLinks);
  // Android 推播：登入後把 token 寫進這個 session（等 session 的裝置資料寫好），登出前清掉
  PushRegistrar.start();
  final auth = AuthController(
    cache: cache,
    onSignedIn: (profile) {
      vault.attach(profile);
      groups.start(profile.uid);
      unawaited(notifications.start(profile.uid));
    },
    onSignedOut: (uid) {
      // Rust 記憶體裡的金鑰全部歸零
      SecretSeal.clearAll();
      vault.detach(uid);
      groups.clear();
      notifications.clear();
      notificationLinks.clear();
    },
  )..start();
  // 有新的通知（即時通知、背景同步）時重新讀收件匣
  groups.notificationSignals.listen((_) => unawaited(notifications.refresh()));
  // 登出前取消這台的推播 token
  auth.beforeSignOut = PushRegistrar.unregister;
  // 點推播打開對應的畫面（鎖著時等解鎖，見 NotificationHost）；App 在前景收到時重新讀收件匣
  AndroidPush.opened.listen(notificationLinks.push);
  AndroidPush.received.listen((_) => unawaited(notifications.refresh()));
  unawaited(AndroidPush.takeLaunchLink().then((link) {
    if (link != null) notificationLinks.push(link);
  }));
  // 設定、更改、停用加密密碼後重新讀個人資料（vault 設定存在 profile）
  vault.onProfileChanged = () async {
    await auth.refreshProfile();
  };

  // macOS 選單列、Linux 與 Windows 系統匣（其他平台不做事）
  final navigatorKey = GlobalKey<NavigatorState>();
  MenuBarService(
    settings: settings,
    auth: auth,
    groups: groups,
    vault: vault,
    codes: MenuBarCodes(cache: cache),
    navigatorKey: navigatorKey,
  ).start();
  // 點連結打開 App：群組邀請、otpauth、otpauth-migration（見 lib/features/links/）
  final links = DeepLinkController();
  unawaited(DeepLinkService(links: links, auth: auth, navigatorKey: navigatorKey).start());

  // 檢查與自動更新（GitHub Releases）：在背景讀版本、等幾秒再查，不擋啟動；iOS、Google Play 版不檢查
  final updateTarget = UpdateTarget.current();
  final updates = UpdateController(
    repo: Env.updateRepo,
    feedUrl: Env.updateFeedUrl,
    target: updateTarget,
    installer: UpdateInstaller.forTarget(updateTarget),
  );
  unawaited(UpdateService(updates: updates, navigatorKey: navigatorKey).start());

  runApp(
    MultiProvider(
      providers: [
        Provider<OfflineCache>.value(value: cache),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider.value(value: groups),
        ChangeNotifierProvider.value(value: updates),
        ChangeNotifierProvider.value(value: links),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: notificationLinks),
        ChangeNotifierProvider.value(value: minVersion),
      ],
      child: SecuribitApp(home: const RootView(), navigatorKey: navigatorKey),
    ),
  );
}

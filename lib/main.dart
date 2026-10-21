import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/security_core.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/secure_session_storage.dart';
import 'features/cache/offline_cache.dart';
import 'features/groups/groups_controller.dart';
import 'features/menubar/menu_bar_codes.dart';
import 'features/menubar/menu_bar_service.dart';
import 'features/settings/settings_controller.dart';
import 'features/update/release.dart';
import 'features/update/update_controller.dart';
import 'features/update/update_service.dart';
import 'features/vault/vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Rust 安全核心（TOTP、加密群組、App 鎖定雜湊、記憶體裡的金鑰）
  await initSecurityCore();
  if (!Env.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SecureSessionStorage(),
    ),
  );

  final settings = SettingsController();
  await settings.load();

  const cache = OfflineCache();
  final vault = VaultController();
  final groups = GroupsController(cache: cache);
  final auth = AuthController(
    cache: cache,
    onSignedIn: (profile) {
      vault.attach(profile);
      groups.start(profile.uid);
    },
    onSignedOut: (uid) {
      // Rust 記憶體裡的金鑰全部歸零
      SecretSeal.clearAll();
      vault.detach(uid);
      groups.clear();
    },
  )..start();
  // 設定、更改、停用加密密碼後重新讀個人資料（vault 設定存在 profile）
  vault.onProfileChanged = () async {
    await auth.refreshProfile();
  };

  // macOS 選單列、Linux 系統匣（其他平台不做事）
  final navigatorKey = GlobalKey<NavigatorState>();
  MenuBarService(
    settings: settings,
    auth: auth,
    groups: groups,
    vault: vault,
    codes: MenuBarCodes(cache: cache),
    navigatorKey: navigatorKey,
  ).start();

  // 檢查更新（GitHub Releases）：在背景讀版本、等幾秒再查，不擋啟動；iOS 不檢查
  final updates = UpdateController(repo: Env.updateRepo, target: UpdateTarget.current());
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
      ],
      child: SecuribitApp(home: const RootView(), navigatorKey: navigatorKey),
    ),
  );
}

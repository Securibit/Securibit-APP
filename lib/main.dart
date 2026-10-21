import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/secure_session_storage.dart';
import 'features/cache/offline_cache.dart';
import 'features/groups/groups_controller.dart';
import 'features/menubar/menu_bar_codes.dart';
import 'features/menubar/menu_bar_service.dart';
import 'features/settings/settings_controller.dart';
import 'features/vault/vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      vault.detach(uid);
      groups.clear();
    },
  )..start();

  // macOS 選單列（其他平台不做事）
  final navigatorKey = GlobalKey<NavigatorState>();
  MenuBarService(
    settings: settings,
    auth: auth,
    groups: groups,
    vault: vault,
    codes: MenuBarCodes(cache: cache),
    navigatorKey: navigatorKey,
  ).start();

  runApp(
    MultiProvider(
      providers: [
        Provider<OfflineCache>.value(value: cache),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider.value(value: groups),
      ],
      child: SecuribitApp(home: const RootView(), navigatorKey: navigatorKey),
    ),
  );
}

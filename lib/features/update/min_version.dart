import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import 'app_version.dart';

/// 後台設定的最低 App 版本（site_settings 的 min_app_version）
class MinVersion {
  const MinVersion({required this.version, required this.message});

  final AppVersion version;
  // 後台寫的說明；沒寫是空字串
  final String message;

  /// app_config() 的回傳：{ min_app_version: { version, message } | null }；也接受直接給 { version, message }
  static MinVersion? fromAppConfig(Object? data) {
    final map = asMap(data);
    final raw = map.containsKey('min_app_version') ? map['min_app_version'] : (map.containsKey('version') ? map : null);
    if (raw is! Map) return null;
    final version = AppVersion.tryParse(asString(raw['version']));
    if (version == null) return null;
    return MinVersion(version: version, message: asString(raw['message']).trim());
  }
}

/// 目前的版本是不是低於最低版本（任一個讀不到就不擋）
bool belowMinimum(String? current, MinVersion? minimum) {
  final version = AppVersion.tryParse(current);
  if (version == null || minimum == null) return false;
  return minimum.version > version;
}

/*
 * 強制更新：開 App 就讀 app_config()（anon 也能呼叫，不用登入、不用解鎖），之後回到前景時每小時再讀一次。
 * 目前的版本低於後台設定的最低版本時 required 不是 null，ForcedUpdateGate 蓋上整頁「需要更新」，不能關。
 * 離線、讀不到、資料庫還沒有這個功能都不擋（保留上一次的結果）。網站不受影響。
 */
class MinVersionController extends ChangeNotifier {
  MinVersionController({Future<Result<MinVersion?>> Function()? fetch, Future<String?> Function()? readVersion, DateTime Function()? clock})
      : _fetch = fetch ?? _fetchAppConfig,
        _readVersion = readVersion ?? _packageVersion,
        _clock = clock ?? DateTime.now;

  static const recheckEvery = Duration(hours: 1);

  /// 目前是不是被擋住（UpdateService 這時不另外跳更新提示，交給強制更新的頁面）
  static final active = ValueNotifier<bool>(false);

  final Future<Result<MinVersion?>> Function() _fetch;
  final Future<String?> Function() _readVersion;
  final DateTime Function() _clock;

  String? currentVersion;
  MinVersion? minimum;
  DateTime? _checkedAt;
  AppLifecycleListener? _lifecycle;

  /// 要更新到的最低版本；不用強制更新時是 null
  MinVersion? get required => belowMinimum(currentVersion, minimum) ? minimum : null;

  static Future<Result<MinVersion?>> _fetchAppConfig() => rpc('app_config', MinVersion.fromAppConfig);

  static Future<String?> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  Future<void> start() async {
    await check();
    _lifecycle ??= AppLifecycleListener(onResume: () {
      final last = _checkedAt;
      if (last == null || _clock().difference(last) >= recheckEvery) unawaited(check());
    });
  }

  Future<void> check() async {
    try {
      currentVersion ??= await _readVersion();
    } catch (_) {
      // 讀不到版本就不擋
    }
    final result = await _fetch();
    _checkedAt = _clock();
    if (result case Ok(:final data)) minimum = data;
    active.value = required != null;
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}

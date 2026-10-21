import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'release.dart';

enum UpdateStatus { idle, checking, upToDate, available, failed }

/*
 * 檢查更新：讀 GitHub Releases 公開 API 的 /repos/<repo>/releases/latest（不用 token），和目前的版本比較。
 * 只負責檢查與提示，下載交給瀏覽器，不會自動安裝。
 * - repo 來自 env.json 的 UPDATE_REPO，留空（或不是 owner/name 的格式）就關閉檢查更新
 * - 「略過這個版本」與「啟動時檢查更新」（預設打開）存在這台裝置；略過的版本之後不再自動提示，手動檢查照樣顯示
 * - 檢查失敗（離線、API 錯誤、被限流）不丟例外，只把狀態設成 failed，自動檢查時什麼都不顯示
 * - target 是 null（iOS 等）時整個功能不出現
 */
class UpdateController extends ChangeNotifier {
  UpdateController({
    required String repo,
    required this.target,
    http.Client? client,
    Future<String?> Function()? readVersion,
    DateTime Function()? clock,
  })  : repo = repo.trim(),
        _client = client ?? http.Client(),
        _readVersion = readVersion ?? _packageVersion,
        _clock = clock ?? DateTime.now;

  static const _checkOnLaunchKey = 'securibit:updateCheckOnLaunch';
  static const _skippedKey = 'securibit:updateSkipped';
  static final _repoPattern = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

  final String repo;
  final UpdateTarget? target;
  final http.Client _client;
  final Future<String?> Function() _readVersion;
  final DateTime Function() _clock;

  /// 目前的版本（pubspec.yaml 的 version，不含 build 號）；還沒讀到是 null
  String? currentVersion;
  bool checkOnLaunch = true;
  String? skippedVersion;
  UpdateStatus status = UpdateStatus.idle;
  // 最近一次檢查到比目前新的版本
  AppRelease? latest;
  DateTime? lastCheckedAt;

  SharedPreferences? _prefs;
  AppVersion? _current;
  Future<AppRelease?>? _inFlight;

  /// 這個平台有沒有檢查更新（iOS 沒有，設定頁也不顯示）
  bool get supported => target != null;

  /// 可以檢查：平台支援、有設定 repo、讀得到目前的版本
  bool get enabled => supported && _repoPattern.hasMatch(repo) && _current != null;

  static Future<String?> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      checkOnLaunch = prefs.getBool(_checkOnLaunchKey) ?? true;
      skippedVersion = prefs.getString(_skippedKey);
    } catch (_) {
      // 讀不到就用預設值
    }
    try {
      final version = await _readVersion();
      _current = AppVersion.tryParse(version);
      currentVersion = _current?.toString() ?? version;
    } catch (_) {
      // 讀不到版本就不檢查更新
    }
    notifyListeners();
  }

  void setCheckOnLaunch(bool enabled) {
    checkOnLaunch = enabled;
    notifyListeners();
    _prefs?.setBool(_checkOnLaunchKey, enabled);
  }

  /// 「略過這個版本」：之後同一版不再自動提示
  Future<void> skip(AppRelease release) async {
    skippedVersion = release.version.toString();
    notifyListeners();
    await _prefs?.setString(_skippedKey, skippedVersion!);
  }

  /// 自動檢查時要不要提示這一版（手動檢查一律提示）
  bool shouldPrompt(AppRelease release) => release.version.toString() != skippedVersion;

  /// 距離上次檢查超過 every（用牆上時間，電腦睡眠的時間也算）
  bool isDue(Duration every) {
    final last = lastCheckedAt;
    return last == null || _clock().difference(last) >= every;
  }

  /// 這個平台要下載的網址（找不到對應的檔案就是 Release 頁面）
  String downloadUrl(AppRelease release) => target == null ? release.pageUrl : release.downloadUrl(target!);

  /// 檢查一次；有比目前新的版本時回傳它，沒有或失敗時回傳 null（看 status 分辨）。同時只會有一個請求
  Future<AppRelease?> check() {
    if (!enabled) return Future.value(null);
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  /// 啟動時與桌面版定期的自動檢查：關掉了、沒有新版、或是使用者略過的版本都回傳 null
  Future<AppRelease?> checkAutomatically() async {
    if (!checkOnLaunch) return null;
    final release = await check();
    return release != null && shouldPrompt(release) ? release : null;
  }

  Future<AppRelease?> _check() async {
    status = UpdateStatus.checking;
    notifyListeners();
    try {
      final res = await _client.get(
        Uri.https('api.github.com', '/repos/$repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Securibit/$currentVersion',
        },
      ).timeout(const Duration(seconds: 15));
      lastCheckedAt = _clock();
      // 404：repo 還沒有發行任何正式版
      if (res.statusCode == 404) return _finish(UpdateStatus.upToDate, null);
      if (res.statusCode != 200) return _finish(UpdateStatus.failed, null);
      final release = AppRelease.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
      if (release == null || !(release.version > _current!)) return _finish(UpdateStatus.upToDate, null);
      return _finish(UpdateStatus.available, release);
    } catch (_) {
      // 離線、逾時、不是 JSON：安靜地失敗
      lastCheckedAt = _clock();
      return _finish(UpdateStatus.failed, null);
    }
  }

  AppRelease? _finish(UpdateStatus next, AppRelease? release) {
    status = next;
    // 失敗時保留上次查到的新版本，設定頁照樣能顯示
    if (next != UpdateStatus.failed) latest = release;
    notifyListeners();
    return release;
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

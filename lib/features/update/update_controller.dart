import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'checksums.dart';
import 'release.dart';
import 'update_downloader.dart';
import 'update_installer.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  // 檢查失敗
  failed,
  // 有新版本，但這台不能自己安裝（原因在 manualReason），只能用瀏覽器下載
  available,
  // 在背景下載並驗證新版本（進度在 progress）
  downloading,
  // 下載或驗證失敗，等一下自動重試
  retrying,
  // 已下載並通過檢查碼，可以安裝
  ready,
  installing,
}

/*
 * 檢查與自動更新（像 Discord）：讀 GitHub Releases 公開 API 的 /repos/<repo>/releases/latest（不用 token），
 * 有新版本就在背景下載這個平台的安裝檔，和 Release 附的 SHA256SUMS.txt 比對，不符就丟掉、絕不安裝；
 * 通過後解開放好（ready），提示「重新啟動並更新」。各平台怎麼裝見 update_installer.dart。
 * - repo 來自 env.json 的 UPDATE_REPO，留空（或不是 owner/name 的格式）就關閉檢查更新
 * - 開發測試：--dart-define=UPDATE_FEED_URL=<網址> 改讀這份 JSON（格式同 releases/latest），可以指到本機的 http；
 *   正式版不設定，行為完全照 GitHub
 * - 「自動檢查更新」（預設打開）存在這台裝置；關掉後只有手動檢查才會下載
 * - 檢查失敗（離線、API 錯誤、被限流）不丟例外，只把狀態設成 failed；下載失敗安靜地重試
 * - 不能自動安裝時（沒有 .zip、沒有檢查碼、App 在唯讀的位置…）狀態是 available，提示用瀏覽器下載
 * - target 是 null（iOS 等）或 Google Play 版時整個功能不出現
 */
class UpdateController extends ChangeNotifier {
  UpdateController({
    required String repo,
    required this.target,
    String feedUrl = '',
    UpdateInstaller? installer,
    http.Client? client,
    Future<String?> Function()? readVersion,
    DateTime Function()? clock,
    List<Duration>? retryDelays,
  })  : repo = repo.trim(),
        feedUrl = feedUrl.trim(),
        _installer = installer ?? const BrowserOnlyInstaller(),
        _client = client ?? http.Client(),
        _readVersion = readVersion ?? _packageVersion,
        _clock = clock ?? DateTime.now,
        _retryDelays = retryDelays ?? const [Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 10), Duration(minutes: 30)];

  static const _checkOnLaunchKey = 'securibit:updateCheckOnLaunch';
  // 舊版的「略過這個版本」，現在不能略過，讀到就清掉
  static const _legacySkippedKey = 'securibit:updateSkipped';
  static final _repoPattern = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');
  // 下載好的版本資料夾裡記錄通過檢查的檔案
  static const _readyFile = 'ready.json';

  final String repo;
  final String feedUrl;
  final UpdateTarget? target;
  final UpdateInstaller _installer;
  final http.Client _client;
  final Future<String?> Function() _readVersion;
  final DateTime Function() _clock;
  final List<Duration> _retryDelays;

  /// 目前的版本（pubspec.yaml 的 version，不含 build 號）；還沒讀到是 null
  String? currentVersion;
  // load() 跑完了（知道是不是 Google Play 版、能不能檢查）
  bool loaded = false;
  bool checkOnLaunch = true;
  UpdateStatus status = UpdateStatus.idle;
  // 最近一次檢查到比目前新的版本
  AppRelease? latest;
  DateTime? lastCheckedAt;
  // 下載進度 0～1；不知道檔案多大時是 null
  double? progress;
  // available 時：為什麼不能自動安裝（null 是沒有特別的原因，例如這個平台沒有自動安裝）
  String? manualReason;

  /// 需要提示使用者時呼叫（UpdateService 跳出提示）：下載好了、或查到新版本但只能用瀏覽器下載；
  /// 自動檢查時已經是這兩種狀態也會再呼叫一次（按「稍後」一小時後再提示）
  void Function(AppRelease release)? onPrompt;

  SharedPreferences? _prefs;
  AppVersion? _current;
  bool _allowed = true;
  Future<AppRelease?>? _inFlight;
  // 每次開始下載新的一版就加一，舊的下載結果直接丟掉
  int _generation = 0;
  int _attempt = 0;
  Timer? _retryTimer;
  Directory? _stage;
  File? _download;

  /// 這個平台有沒有檢查更新（iOS、Google Play 版沒有，設定頁也不顯示）
  bool get supported => target != null && _allowed;

  /// 開發測試用的 UPDATE_FEED_URL
  bool get usesTestFeed => feedUrl.isNotEmpty;

  /// 可以檢查：平台支援、有設定 repo（或測試用的網址）、讀得到目前的版本
  bool get enabled => supported && (usesTestFeed || _repoPattern.hasMatch(repo)) && _current != null;

  /// 下載好之後的按鈕：「重新啟動並更新」（macOS、Linux .tar.gz、Windows）或「立即更新」（Linux .deb、Android）
  String get installLabel => _installer.actionLabel;

  UpdateInstaller get installer => _installer;

  static Future<String?> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  Uri get _feedUri => usesTestFeed ? Uri.parse(feedUrl) : Uri.https('api.github.com', '/repos/$repo/releases/latest');

  late final _downloader = UpdateDownloader(_client, userAgent: 'Securibit/$currentVersion', allowInsecure: usesTestFeed);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      checkOnLaunch = prefs.getBool(_checkOnLaunchKey) ?? true;
      if (prefs.containsKey(_legacySkippedKey)) await prefs.remove(_legacySkippedKey);
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
    if (target != null) _allowed = await _installer.selfUpdateAllowed();
    loaded = true;
    notifyListeners();
    if (enabled) await _cleanUp();
  }

  void setCheckOnLaunch(bool enabled) {
    checkOnLaunch = enabled;
    notifyListeners();
    _prefs?.setBool(_checkOnLaunchKey, enabled);
  }

  /// 距離上次檢查超過 every（用牆上時間，電腦睡眠的時間也算）
  bool isDue(Duration every) {
    final last = lastCheckedAt;
    return last == null || _clock().difference(last) >= every;
  }

  /// 用瀏覽器下載的網址（找不到對應的檔案就是 Release 頁面）
  String downloadUrl(AppRelease release) => target == null ? release.pageUrl : release.downloadUrl(target!);

  /// 還沒查到新版本時用瀏覽器打開的頁面（GitHub 的最新版）；用測試網址或沒設定 repo 時是 null
  String? get releasesPageUrl => !usesTestFeed && _repoPattern.hasMatch(repo) ? 'https://github.com/$repo/releases/latest' : null;

  // 正在背景處理某一版（下載、等重試、已準備好、安裝中）：再檢查一次時不改變狀態
  bool get _busy => const {UpdateStatus.downloading, UpdateStatus.retrying, UpdateStatus.ready, UpdateStatus.installing}.contains(status);

  /// 檢查一次；有比目前新的版本時回傳它（同時在背景開始下載），沒有或失敗時回傳 null（看 status 分辨）。同時只會有一個請求
  Future<AppRelease?> check() {
    if (!enabled) return Future.value(null);
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  /// 啟動時與每小時的自動檢查：關掉了或沒有新版時回傳 null。
  /// 已經下載好（或只能用瀏覽器下載）的同一版再提示一次
  Future<AppRelease?> checkAutomatically() async {
    if (!checkOnLaunch) return null;
    final before = status;
    final beforeVersion = latest?.version;
    final release = await check();
    final waiting = before == UpdateStatus.ready || before == UpdateStatus.available;
    if (release != null && waiting && status == before && release.version == beforeVersion) onPrompt?.call(release);
    return release;
  }

  Future<AppRelease?> _check() async {
    final previous = status;
    final busy = _busy;
    if (!busy) {
      status = UpdateStatus.checking;
      notifyListeners();
    }
    final AppRelease? release;
    try {
      final res = await _client.get(
        _feedUri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Securibit/$currentVersion',
        },
      ).timeout(const Duration(seconds: 15));
      lastCheckedAt = _clock();
      // 404：repo 還沒有發行任何正式版
      if (res.statusCode == 404) return _finish(UpdateStatus.upToDate, busy: busy);
      if (res.statusCode != 200) return _finish(UpdateStatus.failed, busy: busy);
      release = AppRelease.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {
      // 離線、逾時、不是 JSON：安靜地失敗
      lastCheckedAt = _clock();
      return _finish(UpdateStatus.failed, busy: busy);
    }
    if (release == null || !(release.version > _current!)) return _finish(UpdateStatus.upToDate, busy: busy);

    final same = latest?.version == release.version;
    latest = release;
    if (same && (busy || previous == UpdateStatus.available)) {
      // 同一版：下載好了、正在下載、或只能用瀏覽器下載的，狀態不變；重試次數用完的，每小時的檢查再試一次
      status = previous;
      if (previous == UpdateStatus.retrying && !(_retryTimer?.isActive ?? false)) {
        await _startDownload(release);
      } else {
        notifyListeners();
      }
      return release;
    }
    await _startDownload(release);
    return release;
  }

  AppRelease? _finish(UpdateStatus next, {required bool busy}) {
    // 背景還在處理之前查到的版本時不蓋掉狀態
    if (!busy) {
      status = next;
      // 失敗時保留上次查到的新版本，設定頁照樣能顯示
      if (next != UpdateStatus.failed) latest = null;
    }
    notifyListeners();
    return null;
  }

  /// 開始在背景下載；等到確定能不能自動安裝（不能時狀態已經是 available）、或真的開始下載才回傳
  Future<void> _startDownload(AppRelease release) {
    final generation = ++_generation;
    _attempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    status = UpdateStatus.downloading;
    progress = null;
    manualReason = null;
    notifyListeners();
    final planned = Completer<void>();
    unawaited(_runDownload(release, generation, planned).whenComplete(() {
      if (!planned.isCompleted) planned.complete();
    }));
    return planned.future;
  }

  Future<void> _runDownload(AppRelease release, int generation, [Completer<void>? planned]) async {
    bool stale() => generation != _generation;
    try {
      final support = await _installer.support();
      if (stale()) return;
      if (!support.auto) return _manual(release, support.reason);
      final asset = release.installAsset(target!);
      if (asset == null) return _manual(release, '這一版沒有可以自動安裝的檔案，請用瀏覽器下載');
      final sumsAsset = release.checksumsAsset;
      if (sumsAsset == null) return _manual(release, '這一版沒有附上檢查碼（SHA256SUMS.txt），無法確認檔案完整，請用瀏覽器下載');
      final root = await _installer.workDir();
      if (stale()) return;
      if (root == null) return _manual(release, null);
      final stage = Directory('${root.path}/${release.version}');
      final file = File('${stage.path}/${asset.name}');

      // 上次開著時已經下載並準備好
      if (await _isReady(stage, file, release)) {
        if (!stale()) await _ready(release, stage, file);
        return;
      }
      if (status == UpdateStatus.retrying) {
        status = UpdateStatus.downloading;
        notifyListeners();
      }
      if (planned != null && !planned.isCompleted) planned.complete();

      final sums = parseChecksums(await _downloader.fetchText(Uri.parse(sumsAsset.url)));
      if (stale()) return;
      final expected = checksumFor(sums, asset.name);
      if (expected == null) return _manual(release, '檢查碼清單裡沒有 ${asset.name}，無法確認檔案完整，請用瀏覽器下載');

      // 其他版本留下的檔案用不到了
      await _removeOthers(root, keep: stage);
      if (await stage.exists()) await stage.delete(recursive: true);
      await stage.create(recursive: true);
      var lastPercent = -1;
      await _downloader.download(Uri.parse(asset.url), file, onProgress: (received, total) {
        if (stale() || total == null || total <= 0) return;
        final percent = received * 100 ~/ total;
        if (percent == lastPercent) return;
        lastPercent = percent;
        progress = received / total;
        notifyListeners();
      });
      if (stale()) return;

      // 檢查碼不符：丟掉檔案，絕不安裝（可能是下載壞掉，之後重新下載）
      if (await sha256OfFile(file) != expected) {
        await file.delete();
        throw const UpdateDownloadException('檢查碼不符');
      }
      await _installer.prepare(file, stage, release);
      await File('${stage.path}/$_readyFile').writeAsString(jsonEncode({'version': '${release.version}', 'asset': asset.name, 'sha256': expected}));
      if (!stale()) await _ready(release, stage, file);
    } on UpdatePrepareException catch (e) {
      // 檔案內容不對，重新下載也一樣：改用瀏覽器下載
      if (!stale()) _manual(release, '${e.message}，請用瀏覽器下載');
    } catch (_) {
      if (!stale()) _retry(release, generation);
    }
  }

  // 已經下載好：記錄的檢查碼和檔案一致，而且解開好了
  Future<bool> _isReady(Directory stage, File file, AppRelease release) async {
    try {
      final record = jsonDecode(await File('${stage.path}/$_readyFile').readAsString());
      if (record is! Map || record['version'] != '${release.version}' || record['asset'] != file.uri.pathSegments.last) return false;
      if (!await file.exists() || await sha256OfFile(file) != record['sha256']) return false;
      return _installer.isPrepared(stage);
    } catch (_) {
      return false;
    }
  }

  Future<void> _ready(AppRelease release, Directory stage, File file) async {
    _stage = stage;
    _download = file;
    status = UpdateStatus.ready;
    progress = null;
    manualReason = null;
    notifyListeners();
    await _installer.armOnQuit(stage);
    onPrompt?.call(release);
  }

  void _manual(AppRelease release, String? reason) {
    status = UpdateStatus.available;
    progress = null;
    manualReason = reason;
    notifyListeners();
    onPrompt?.call(release);
  }

  void _retry(AppRelease release, int generation) {
    status = UpdateStatus.retrying;
    progress = null;
    notifyListeners();
    // 重試次數用完就等下一次自動檢查
    if (_attempt >= _retryDelays.length) return;
    final delay = _retryDelays[_attempt++];
    _retryTimer = Timer(delay, () {
      if (generation == _generation) unawaited(_runDownload(release, generation));
    });
  }

  /// 安裝下載好的版本：macOS、Linux、Windows 會結束 App（替換或安裝後重新打開），Android 跳出系統的安裝畫面
  Future<InstallOutcome> install() async {
    final stage = _stage;
    final file = _download;
    final release = latest;
    if (status != UpdateStatus.ready || stage == null || file == null || release == null) {
      return const InstallOutcome(InstallResult.failed, '新版本還沒準備好');
    }
    status = UpdateStatus.installing;
    notifyListeners();
    // 安裝前再確認一次檔案沒有被換掉
    if (!await _isReady(stage, file, release)) {
      unawaited(_startDownload(release));
      return const InstallOutcome(InstallResult.failed, '下載的檔案有變動，正在重新下載');
    }
    final outcome = await _installer.install(stage, file);
    if (outcome.result != InstallResult.started || !_installer.exitsApp) {
      status = UpdateStatus.ready;
      notifyListeners();
    }
    return outcome;
  }

  // 開 App 時清掉已經裝好（不比目前新）的版本留下的檔案
  Future<void> _cleanUp() async {
    try {
      final root = await _installer.workDir();
      if (root == null || !await root.exists()) return;
      await for (final entry in root.list()) {
        final version = AppVersion.tryParse(entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty));
        if (version == null || !(version > _current!)) await entry.delete(recursive: true);
      }
    } catch (_) {
      // 清不掉就算了
    }
  }

  Future<void> _removeOthers(Directory root, {required Directory keep}) async {
    try {
      if (!await root.exists()) return;
      await for (final entry in root.list()) {
        if (entry.path != keep.path) await entry.delete(recursive: true);
      }
    } catch (_) {
      // 清不掉就算了
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _client.close();
    super.dispose();
  }
}

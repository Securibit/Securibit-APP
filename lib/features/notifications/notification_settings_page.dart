import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/platform.dart';
import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../profile/profile_frame.dart';
import 'notification_models.dart';
import 'notifications_repository.dart' as repo;
import 'push/android_push.dart';

/// 設定的「通知」
Future<void> openNotificationSettings(BuildContext context) =>
    showProfilePage(context, (inDialog) => NotificationSettingsPage(inDialog: inDialog));

/// 通知分頁的說明（同網站帳戶設定的「通知」）
const notificationSettingsFooter = '關掉後不會再跳出通知或推播，但鈴鐺裡還是看得到。這份設定網站與 App 共用；App 的推播也可以在系統設定裡關閉';

/*
 * 通知開關（同網站帳戶設定的「通知」分頁）：系統、帳戶、功能三組，每種一個開關。
 * 「重要公告」顯示但鎖住（一定會通知）。關掉只影響推播與系統通知，鈴鐺裡一樣留紀錄。
 * Android：有推播時最上面顯示系統通知權限，被關掉時可以前往系統設定打開。
 * 開關一改就存（notification_prefs_set，只送改了的那一種），失敗時改回來並說明。
 */
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.inDialog, this.load, this.save});

  final bool inDialog;
  // 測試用
  final Future<Result<NotificationPrefs>> Function()? load;
  final Future<Result<NotificationPrefs>> Function(Map<String, bool> changes)? save;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> with WidgetsBindingObserver {
  NotificationPrefs? _prefs;
  String? _error;
  // Android 有推播時的系統權限；null 是不用顯示
  PushPermission? _permission;
  int _saveSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    unawaited(_loadPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 從系統設定回來時重新看權限
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadPermission());
  }

  Future<void> _load() async {
    final result = await (widget.load ?? repo.loadNotificationPrefs)();
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(:final data):
          _prefs = data;
          _error = null;
        case Err(:final message):
          _error = message;
      }
    });
  }

  Future<void> _loadPermission() async {
    if (!AndroidPush.supported || !await AndroidPush.available()) return;
    final permission = await AndroidPush.permission();
    if (mounted) setState(() => _permission = permission);
  }

  Future<void> _toggle(String type, bool on) async {
    final before = _prefs;
    if (before == null) return;
    final next = before.set(type, on);
    setState(() => _prefs = next);
    final seq = ++_saveSeq;
    final result = await (widget.save ?? repo.saveNotificationPrefs)({type: on});
    if (!mounted || seq != _saveSeq) return;
    switch (result) {
      case Ok(:final data):
        setState(() => _prefs = data);
      case Err(:final message):
        setState(() => _prefs = before);
        await showErrorDialog(context, '無法儲存通知設定', message);
    }
  }

  Future<void> _requestPermission() async {
    // Android 13 以上還能再跳一次系統的詢問；被拒絕太多次或更舊的版本只能到系統設定打開
    final granted = await AndroidPush.requestPermission();
    if (!granted) await AndroidPush.openSettings();
    await _loadPermission();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final prefs = _prefs;
    return ProfilePageScaffold(
      title: '通知',
      inDialog: widget.inDialog,
      onRefresh: _load,
      children: [
        if (_permission == PushPermission.denied) ...[
          GroupedList(
            footer: '要允許 Securibit 顯示通知，手機才會跳出推播',
            children: [
              GroupedRow(
                label: '系統通知權限已關閉',
                trailing: TextButton(onPressed: _requestPermission, child: const Text('前往設定')),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (prefs == null && _error == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator.adaptive()))
        else if (prefs == null)
          GroupedList(
            footer: _error,
            children: [GroupedRow(label: '無法載入通知設定', accent: true, value: '重試', onTap: _load)],
          )
        else ...[
          for (final category in NotificationCategory.values) ...[
            GroupedList(
              header: category.label,
              children: [
                for (final def in notificationTypes.where((d) => d.category == category))
                  _PrefRow(def: def, value: prefs.enabled(def.type), onChanged: def.locked ? null : (on) => _toggle(def.type, on)),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              [
                notificationSettingsFooter,
                if (Platform.isIOS) 'iPhone 目前沒有推播，通知會出現在鈴鐺裡',
                if (AppPlatform.isDesktop) 'Securibit 開著或常駐在${Platform.isMacOS ? '選單列' : '系統匣'}時，會用系統通知告訴你',
              ].join('\n'),
              style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
            ),
          ),
        ],
      ],
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({required this.def, required this.value, required this.onChanged});

  final NotificationTypeDef def;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(def.label, style: const TextStyle(fontSize: AppText.body))),
                    if (def.locked) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock_rounded, size: 15, color: colors.inkMuted),
                    ],
                  ],
                ),
                Text(def.description, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

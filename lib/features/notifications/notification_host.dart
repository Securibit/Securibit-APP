import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security_core.dart';
import '../settings/settings_controller.dart';
import 'notification_inbox.dart';
import 'notification_link_queue.dart';
import 'push/android_push.dart';

/*
 * 包在登入後的主畫面外面（見 RootView）：
 * - 點了推播或系統通知（NotificationLinkQueue）：App 沒有鎖定時打開對應的畫面，鎖著就等解鎖
 * - Android 13 以上：登入後第一次進主畫面時直接要系統的通知權限（不先跳 App 自己的說明）；
 *   拒絕了就算，設定的「通知」顯示「系統通知權限已關閉」與前往設定的按鈕。問過一次就不再問（記在這台裝置）
 */
class NotificationHost extends StatefulWidget {
  const NotificationHost({super.key, required this.child});

  final Widget child;

  static const askedKey = 'securibit:pushPermissionAsked';

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost> {
  late final NotificationLinkQueue _links = context.read<NotificationLinkQueue>();
  late final SettingsController _settings = context.read<SettingsController>();
  bool _busy = false;
  bool _askChecked = false;

  @override
  void initState() {
    super.initState();
    _links.addListener(_check);
    _settings.appLock.addListener(_check);
    SecretSeal.sealed.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _links.removeListener(_check);
    _settings.appLock.removeListener(_check);
    SecretSeal.sealed.removeListener(_check);
    super.dispose();
  }

  bool get _locked => _settings.appLock.lockedAt(DateTime.now());

  void _check() {
    if (_busy || !mounted || _locked) return;
    final link = _links.take();
    if (link != null) {
      _busy = true;
      unawaited(_open(link).whenComplete(() {
        _busy = false;
        if (mounted) _check();
      }));
      return;
    }
    if (!_askChecked) {
      _askChecked = true;
      _busy = true;
      unawaited(_askPermission().whenComplete(() {
        _busy = false;
        if (mounted) _check();
      }));
    }
  }

  Future<void> _open(String link) async {
    // 先回到主畫面（關掉設定、收件匣等），再打開對應的畫面
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await openNotificationLink(context, link.isEmpty ? null : link);
  }

  Future<void> _askPermission() async {
    if (!AndroidPush.supported || !await AndroidPush.available()) return;
    if (await AndroidPush.permission() != PushPermission.denied) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(NotificationHost.askedKey) ?? false) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await prefs.setBool(NotificationHost.askedKey, true);
    await AndroidPush.requestPermission();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

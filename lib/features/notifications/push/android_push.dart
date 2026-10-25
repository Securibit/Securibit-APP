import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 系統通知權限
enum PushPermission { granted, denied, unsupported }

/*
 * Android 推播的原生介面（channel：securibit/push，原生端見 android/app/src/main/kotlin/com/bityo/securibit/Push.kt）。
 * 只用原生的 Firebase Cloud Messaging（不用 Flutter 的 firebase_messaging）；沒有 google-services.json 時 available 是 false。
 * 其他平台（iOS 先不接推播、桌面用 desktop_notifier.dart）全部回傳「不支援」。
 */
class AndroidPush {
  AndroidPush._();

  static const channel = MethodChannel('securibit/push');

  static bool get supported => Platform.isAndroid;

  static final _tokens = StreamController<String>.broadcast();
  static final _opened = StreamController<String>.broadcast();
  static final _received = StreamController<void>.broadcast();
  static bool _listening = false;

  /// FCM 換了 token
  static Stream<String> get tokenChanges => _tokens.stream;

  /// App 開著時點了推播通知（link 是站內路徑；空字串是沒有連結，打開收件匣）
  static Stream<String> get opened => _opened.stream;

  /// App 在前景時收到推播（重新讀收件匣）
  static Stream<void> get received => _received.stream;

  static void listen() {
    if (!supported || _listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'tokenChanged':
          final token = args['token'];
          if (token is String && token.isNotEmpty) _tokens.add(token);
        case 'opened':
          final link = args['link'];
          _opened.add(link is String ? link : '');
        case 'received':
          _received.add(null);
      }
      return null;
    });
  }

  static Future<T?> _invoke<T>(String method) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 這個版本有沒有設定推播（google-services.json）
  static Future<bool> available() async => await _invoke<bool>('available') ?? false;

  static Future<String?> token() => _invoke<String>('token');

  static Future<PushPermission> permission() async {
    if (!supported) return PushPermission.unsupported;
    return switch (await _invoke<String>('permission')) {
      'granted' => PushPermission.granted,
      'denied' => PushPermission.denied,
      _ => PushPermission.unsupported,
    };
  }

  /// Android 13 以上跳出系統的通知權限；回傳是否允許
  static Future<bool> requestPermission() async => await _invoke<bool>('requestPermission') ?? false;

  /// 打開系統設定的這個 App 的通知
  static Future<void> openSettings() => _invoke<void>('openSettings');

  /// 冷啟動時點通知帶進來的連結（取一次就沒了）；null 是不是點通知打開的
  static Future<String?> takeLaunchLink() => _invoke<String>('takeLaunchLink');
}

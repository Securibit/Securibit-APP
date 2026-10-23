import 'dart:convert';

import '../../core/json.dart';

/*
 * 已登入的裝置用到的資料格式與顯示（同網站 src/lib/users/sessions.ts、src/lib/users/userAgent.ts、
 * src/types/Activity/Session.ts；資料庫是 list_my_sessions）
 */

/// list_my_sessions() 的一筆：一個登入中的 session
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.createdAt,
    required this.lastActiveAt,
    required this.userAgent,
    required this.ip,
    required this.aal,
    required this.current,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
  });

  final String id;
  // 首次登入
  final String? createdAt;
  // 最後活動：換 token、session 更新與 App 回報的時間取最新的
  final String? lastActiveAt;
  final String? userAgent;
  final String? ip;
  // aal1 / aal2
  final String? aal;
  // 發出請求的這個 session（這台裝置）
  final bool current;
  // App 回報的裝置資料（session_devices）；網站沒有
  final String? deviceName;
  // ios / android / macos / linux / windows
  final String? platform;
  final String? appVersion;

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        id: asString(json['id']),
        createdAt: asNullableString(json['created_at']),
        lastActiveAt: asNullableString(json['last_active_at']),
        userAgent: asNullableString(json['user_agent']),
        ip: asNullableString(json['ip']),
        aal: asNullableString(json['aal']),
        current: asBool(json['current']),
        deviceName: asNullableString(json['device_name']),
        platform: asNullableString(json['platform']),
        appVersion: asNullableString(json['app_version']),
      );
}

/// 從 user-agent 解析出的系統、瀏覽器與裝置種類
typedef UserAgentInfo = ({String os, String browser, String device});

// Securibit App：呼叫網站 API 時是 SecuribitApp (…)，直接打 Supabase 時是 Dart 預設的 Dart/3.x (dart:io)
final _app = RegExp(r'SecuribitApp|^Dart/', caseSensitive: false);
// 1.3.2 起帶版本：SecuribitApp/1.3.2 (…)
final _appVersion = RegExp(r'SecuribitApp/([0-9][0-9A-Za-z.+-]*)', caseSensitive: false);

bool _has(String ua, String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(ua);

/// 同網站 parseUserAgent 的規則
UserAgentInfo parseUserAgent(String ua) {
  var os = '未知系統';
  var device = '未知裝置';
  if (_has(ua, 'iPad')) {
    (os, device) = ('iOS', 'iPad');
  } else if (_has(ua, 'iPhone|iPod')) {
    (os, device) = ('iOS', 'iPhone');
  } else if (_has(ua, 'Android')) {
    (os, device) = ('Android', 'Android 裝置');
  } else if (_has(ua, 'Mac OS X|Macintosh')) {
    (os, device) = ('macOS', 'Mac');
  } else if (_has(ua, 'Windows')) {
    (os, device) = ('Windows', 'Windows 電腦');
  } else if (_has(ua, 'Linux')) {
    (os, device) = ('Linux', 'Linux 電腦');
  }

  var browser = '未知瀏覽器';
  if (_app.hasMatch(ua)) {
    final version = _appVersion.firstMatch(ua)?.group(1);
    browser = version == null ? 'Securibit App' : 'Securibit App $version';
  } else if (_has(ua, r'Edg/')) {
    browser = 'Edge';
  } else if (_has(ua, r'OPR/|Opera')) {
    browser = 'Opera';
  } else if (_has(ua, r'Chrome/|CriOS/')) {
    browser = 'Chrome';
  } else if (_has(ua, r'Firefox/|FxiOS/')) {
    browser = 'Firefox';
  } else if (_has(ua, r'Safari/')) {
    browser = 'Safari';
  }
  return (os: os, browser: browser, device: device);
}

// App 回報的平台
const _platformText = {
  'ios': 'iOS',
  'android': 'Android',
  'macos': 'macOS',
  'linux': 'Linux',
  'windows': 'Windows',
};

/// 列表上顯示的裝置名稱、平台、App／瀏覽器
typedef SessionDisplay = ({String name, String platform, String client});

/// App 有回報裝置資料就用回報的；否則（網站、舊版 App）從 user-agent 解析（同網站 sessionDisplay）
SessionDisplay sessionDisplay(SessionRecord session) {
  final ua = parseUserAgent(session.userAgent ?? '');
  if (session.platform != null || session.deviceName != null || session.appVersion != null) {
    final platform = session.platform == null ? ua.os : (_platformText[session.platform] ?? session.platform!);
    return (
      name: session.deviceName ?? platform,
      platform: platform,
      client: session.appVersion == null ? 'Securibit App' : 'Securibit App ${session.appVersion}',
    );
  }
  return (name: ua.device, platform: ua.os, client: ua.browser);
}

/// access token 裡的 session_id claim；解不開時 null
String? sessionIdOf(String accessToken) {
  final parts = accessToken.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return payload is Map ? asNullableString(payload['session_id']) : null;
  } catch (_) {
    return null;
  }
}

/// 裝置名稱：主機名稱（去掉 macOS 的 .local）；沒有或是 localhost 時是 null
String? cleanHostname(String hostname) {
  final name = hostname.trim().replaceFirst(RegExp(r'\.local$', caseSensitive: false), '');
  if (name.isEmpty || name.toLowerCase() == 'localhost') return null;
  return name.length > 100 ? name.substring(0, 100) : name;
}

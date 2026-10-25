import '../../../core/json.dart';
import '../../../core/result.dart';
import '../../../core/rpc.dart';
import 'broadcast_models.dart';

/*
 * 後台發送通知與通知設定的 RPC（和網站 src/lib/notifications/broadcast.ts 呼叫的完全相同）。
 */

const broadcastPageSize = 50;

Future<Result<BroadcastPreview>> previewBroadcast(BroadcastFilter filter) =>
    rpc('admin_broadcast_preview', BroadcastPreview.fromJson, {'p_filter': filter.toJson()});

/// 回傳收到的使用者數
Future<Result<int>> sendBroadcast(BroadcastKind kind, String title, String body, String? link, BroadcastFilter filter) => rpc(
      'admin_broadcast_send',
      (data) => asInt(asMap(data)['users']),
      {
        'p_kind': kind.name,
        'p_title': title.trim(),
        'p_body': body.trim(),
        'p_link': (link == null || link.trim().isEmpty) ? null : link.trim(),
        'p_filter': filter.toJson(),
      },
    );

Future<Result<List<BroadcastRecord>>> loadBroadcasts({int? before}) => rpc(
      'admin_broadcasts_list',
      (data) => asMapList(data).map(BroadcastRecord.fromJson).toList(),
      {'p_before': before, 'p_limit': broadcastPageSize},
    );

Future<Result<SiteSettings>> loadSiteSettings() => rpc('admin_site_settings_get', SiteSettings.fromJson);

Future<Result<void>> saveAdminChangeNotify(AdminChangeNotify value) =>
    rpcVoid('admin_site_settings_set', {'p_key': 'notify_admin_changes', 'p_value': value.toJson()});

/// null 是清除（不限制版本）
Future<Result<void>> saveMinAppVersion(MinAppVersion? value) =>
    rpcVoid('admin_site_settings_set', {'p_key': 'min_app_version', 'p_value': value?.toJson()});

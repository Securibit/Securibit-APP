import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../admin/admin_format.dart';
import '../admin/widgets/admin_widgets.dart';
import 'profile_frame.dart';
import 'profile_repository.dart' as repo;
import 'session_device.dart';
import 'session_models.dart';

const _tabular = [FontFeature.tabularFigures()];

/*
 * 已登入的裝置（同網站個人頁面的「已登入的裝置」）：
 * 一列一個 session（裝置名稱、平台 · App／瀏覽器 · IP、最後活動與首次登入），這台排第一並標出來；
 * 其他的可以單獨登出，下面是「登出其他所有裝置」，都要先確認。
 */
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.inDialog});

  final bool inDialog;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  // null：載入中
  List<SessionRecord>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 開 App 時那次可能沒寫成功（例如當時資料庫還沒有這個功能），先補寫這台，列表才不會是「未知裝置」
    await SessionDeviceReporter.reportNow();
    final result = await repo.loadMySessions();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() => _sessions = data);
      case Err(:final message):
        setState(() => _sessions ??= const []);
        await showErrorDialog(context, '載入已登入的裝置失敗', message);
    }
  }

  Future<void> _revoke(SessionRecord session, String name) async {
    final ok = await confirmDialog(
      context,
      title: '登出「$name」',
      message: '這台裝置要重新登入才能再使用 Securibit',
      confirmLabel: '登出',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _finish(await repo.revokeMySession(session.id), '已登出「$name」');
  }

  Future<void> _revokeOthers() async {
    final ok = await confirmDialog(
      context,
      title: '登出其他所有裝置',
      message: '除了這台裝置，其他登入中的網站與 App 都要重新登入才能再使用 Securibit',
      confirmLabel: '登出',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _finish(await repo.signOutOtherSessions(), '已登出其他所有裝置');
  }

  Future<void> _finish(Result<void> result, String done) async {
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '登出失敗', message);
      return;
    }
    showToast(context, done);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sessions = _sessions;
    final hasOthers = sessions?.any((s) => !s.current) ?? false;

    return ProfilePageScaffold(
      title: '已登入的裝置',
      inDialog: widget.inDialog,
      onRefresh: _load,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
          child: Text(
            '目前用這個帳號登入的網站與 App',
            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          ),
        ),
        if (sessions == null)
          const ListLoading()
        else if (sessions.isEmpty)
          const ListEmpty('沒有登入中的裝置')
        else
          GroupedList(
            children: [
              for (final session in sessions)
                SessionRow(session: session, onRevoke: (name) => _revoke(session, name)),
            ],
          ),
        if (hasOthers) ...[
          const SizedBox(height: 24),
          GroupedList(
            footer: '被登出的裝置會在下次更新登入狀態時回到登入畫面，通常在一小時內',
            children: [GroupedRow(label: '登出其他所有裝置', danger: true, onTap: _revokeOthers)],
          ),
        ],
      ],
    );
  }
}

/// 一個 session：裝置名稱（這台標「這台裝置」）、平台 · App／瀏覽器 · IP、最後活動與首次登入，右邊是「登出」。
/// readOnly（後台查看別人的裝置）：不標「這台裝置」、沒有「登出」
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session, this.onRevoke, this.readOnly = false});

  final SessionRecord session;
  final void Function(String name)? onRevoke;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final display = sessionDisplay(session);
    final detail = [display.platform, display.client, ?session.ip].join(' · ');
    final muted = TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: _tabular);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        display.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (session.current && !readOnly) ...[const SizedBox(width: 8), const Tag('這台裝置')],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted, fontFeatures: _tabular),
                ),
                Text('最後活動 ${formatDateTime(session.lastActiveAt)}', style: muted),
                Text('首次登入 ${formatDateTime(session.createdAt)}', style: muted),
              ],
            ),
          ),
          if (!session.current && !readOnly && onRevoke != null)
            TextButton(onPressed: () => onRevoke!(display.name), child: const Text('登出'))
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

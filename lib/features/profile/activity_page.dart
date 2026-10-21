import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/grouped_list.dart';
import '../../core/widgets/pill.dart';
import '../admin/admin_format.dart';
import '../admin/admin_models.dart';
import '../admin/widgets/log_rows.dart';
import '../admin/widgets/paged_list.dart';
import '../auth/auth_controller.dart';
import 'profile_frame.dart';
import 'profile_repository.dart' as repo;

// 每次載入的筆數（同網站 /me/activity）
const activityPageSize = 20;

/*
 * 自己的活動紀錄（同網站 /me/activity，加上個人頁面的「登入資訊」）：
 * 最後一次登入的資訊，下面分「登入」「操作」兩頁，各自「載入更多」；切換分頁時保留已載入的頁數。
 */
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.inDialog});

  final bool inDialog;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = context.watch<AuthController>().profile;
    final uid = profile?.uid ?? '';

    return ProfilePageScaffold(
      title: '活動紀錄',
      inDialog: widget.inDialog,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
          child: Text(
            '你的每次登入，以及帳號資料、加密、身分組與群組的變更',
            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          ),
        ),
        if (profile != null) ...[
          GroupedList(
            header: '登入資訊',
            children: [
              GroupedRow(label: '建立時間', value: formatDateTime(profile.creationTime)),
              GroupedRow(label: '最後登入', value: formatDateTime(profile.lastLoginAt)),
              GroupedRow(label: 'IP', value: profile.lastLoginIp.isNotEmpty ? profile.lastLoginIp : '無'),
              GroupedRow(label: '裝置', value: profile.lastLoginDevice.isNotEmpty ? profile.lastLoginDevice : '無'),
            ],
          ),
          const SizedBox(height: 24),
        ],
        Center(
          child: PillBar(labels: const ['登入', '操作'], selectedIndex: _tab, onSelect: (i) => setState(() => _tab = i)),
        ),
        const SizedBox(height: 16),
        // 兩頁都掛著，切換時不會重新載入
        Visibility(
          visible: _tab == 0,
          maintainState: true,
          child: PagedList<LoginRecord>(
            load: (before) => repo.loadMyLoginHistory(before, activityPageSize),
            pageSize: activityPageSize,
            idOf: (r) => r.id,
            emptyText: '還沒有登入紀錄',
            errorTitle: '載入登入紀錄失敗',
            itemBuilder: (context, record, index) => LoginRecordRow(record: record, latest: index == 0),
          ),
        ),
        Visibility(
          visible: _tab == 1,
          maintainState: true,
          child: PagedList<AccountActivity>(
            load: (before) => repo.loadMyAccountActivity(before, activityPageSize),
            pageSize: activityPageSize,
            idOf: (a) => a.id,
            emptyText: '還沒有操作紀錄',
            errorTitle: '載入操作紀錄失敗',
            itemBuilder: (context, activity, _) => ActivityRow(activity: activity, subjectId: uid, self: true),
          ),
        ),
      ],
    );
  }
}

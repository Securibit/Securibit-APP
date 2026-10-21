import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../audit_text.dart';
import 'admin_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// 登入紀錄的一列：裝置（最新一筆標「最近一次」）、登入方式 · IP、時間（同網站 LoginHistoryList）
class LoginRecordRow extends StatelessWidget {
  const LoginRecordRow({super.key, required this.record, required this.latest});

  final LoginRecord record;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  record.device ?? '未知裝置',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                ),
              ),
              if (latest) ...[const SizedBox(width: 8), const Tag('最近一次', accent: true)],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${providerText(record.provider)} · ${loginIpText(record.ip)}',
            style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: _tabular),
          ),
          Text(
            formatDateTime(record.createdAt),
            style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

/// 帳號操作紀錄的一列：中文描述 + 時間
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.activity, required this.subjectId, this.self = false});

  final AccountActivity activity;
  final String subjectId;
  // 本人看自己的紀錄（「你」）
  final bool self;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(describeActivity(activity, subjectId, self: self), style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
            formatDateTime(activity.log.createdAt),
            style: TextStyle(fontSize: AppText.caption, color: context.colors.inkMuted, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

/// 操作紀錄的一列：操作者（null 是「系統或已刪除的使用者」）、動作、目標、變更、時間（同網站 AuditLogList）
class AuditLogRow extends StatelessWidget {
  const AuditLogRow({super.key, required this.log, this.onOpenActor});

  final AuditLog log;
  // 點操作者（開使用者詳細資料）；沒有權限時不給
  final ValueChanged<PersonBrief>? onOpenActor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = auditTargetText(log);
    final change = auditChangeText(log.action, log.detail);
    final actor = log.actor;
    Widget who = actor == null
        ? Text('系統或已刪除的使用者', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted, fontWeight: FontWeight.w600))
        : PersonChip(person: actor, size: 28);
    if (actor != null && onOpenActor != null) {
      who = InkWell(borderRadius: BorderRadius.circular(AppRadius.small), onTap: () => onOpenActor!(actor), child: who);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          who,
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: auditActionText(log.action), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (target != null && target.isNotEmpty) TextSpan(text: '  $target'),
                if (change != null) TextSpan(text: '  $change', style: TextStyle(color: colors.inkMuted)),
              ],
            ),
            style: const TextStyle(fontSize: AppText.secondary),
          ),
          const SizedBox(height: 2),
          Text(formatDateTime(log.createdAt), style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: _tabular)),
        ],
      ),
    );
  }
}

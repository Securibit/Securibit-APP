import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../admin/admin_format.dart';
import '../../admin/admin_models.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../groups_repository.dart' as repo;
import 'group_rules.dart';
import 'group_tab_context.dart';

/*
 * 邀請分頁（同網站 GroupInvites）：建立邀請連結（有效時間、使用次數，建好顯示網址與 QR Code）、
 * 有效的連結清單與撤銷、用電子郵件或 @ID 邀請與等待回覆的清單
 */
class GroupInvitesTab extends StatefulWidget {
  const GroupInvitesTab({super.key, required this.tab});

  final GroupTabContext tab;

  @override
  State<GroupInvitesTab> createState() => _GroupInvitesTabState();
}

class _GroupInvitesTabState extends State<GroupInvitesTab> {
  int _hours = defaultInviteExpiry;
  int? _uses;
  bool _creating = false;
  // 剛建立的邀請碼
  String? _created;

  final _target = TextEditingController();
  bool _inviting = false;
  String? _cancelling;

  AdminGroupDetail get _detail => widget.tab.detail;
  String get _gid => widget.tab.groupId;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final result = await repo.createInvite(_gid, _hours, _uses);
    if (!mounted) return;
    setState(() => _creating = false);
    switch (result) {
      case Err(:final message):
        await showErrorDialog(context, '建立邀請連結失敗', message);
      case Ok(data: final code):
        setState(() => _created = code);
        showToast(context, '已建立邀請連結');
        await widget.tab.onChanged();
    }
  }

  Future<void> _revoke(GroupInvite invite) async {
    final ok = await confirmDialog(
      context,
      title: '撤銷邀請連結',
      message: '撤銷後這個連結就不能再用來加入群組，已經加入的成員不受影響',
      confirmLabel: '撤銷',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await repo.revokeInvite(invite.code);
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '撤銷邀請連結失敗', message);
      return;
    }
    if (_created == invite.code) setState(() => _created = null);
    showToast(context, '已撤銷邀請連結');
    await widget.tab.onChanged();
  }

  Future<void> _inviteUser() async {
    final target = _target.text.trim();
    if (target.isEmpty || _inviting) return;
    setState(() => _inviting = true);
    final result = await repo.inviteUser(_gid, target);
    if (!mounted) return;
    setState(() => _inviting = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '邀請失敗', message);
      return;
    }
    showToast(context, '已邀請 $target');
    _target.clear();
    await widget.tab.onChanged();
  }

  Future<void> _cancel(GroupEmailInvite invite) async {
    setState(() => _cancelling = invite.id);
    final result = await repo.cancelEmailInvite(invite.id);
    if (!mounted) return;
    setState(() => _cancelling = null);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '取消邀請失敗', message);
      return;
    }
    showToast(context, '已取消邀請');
    await widget.tab.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final canInvite = hasPermission(_detail.permissions, GroupPermission.createInvite);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canInvite) ...[
          _createSection(context),
          if (_created != null) ...[
            const SizedBox(height: 12),
            _InviteCreated(key: ValueKey(_created), code: _created!, onClose: () => setState(() => _created = null)),
          ],
          const SizedBox(height: 28),
        ],
        _linksSection(context),
        const SizedBox(height: 28),
        _emailSection(context, canInvite),
      ],
    );
  }

  Widget _createSection(BuildContext context) {
    final colors = context.colors;
    String labelOf<T>(List<(T, String)> options, T value) => options.where((o) => o.$1 == value).firstOrNull?.$2 ?? '';
    return GroupedList(
      header: '建立邀請連結',
      footer: '拿到連結的人登入後就能加入群組，加入後只有 @everyone 的權限',
      children: [
        GroupedRow(
          label: '有效時間',
          trailing: _OptionMenu<int>(
            options: inviteExpiryOptions,
            label: labelOf(inviteExpiryOptions, _hours),
            onSelected: (value) => setState(() => _hours = value),
          ),
        ),
        GroupedRow(
          label: '使用次數',
          trailing: _OptionMenu<int?>(
            options: inviteUseOptions,
            label: labelOf(inviteUseOptions, _uses),
            onSelected: (value) => setState(() => _uses = value),
          ),
        ),
        InkWell(
          onTap: _creating ? null : _create,
          child: SizedBox(
            height: 50,
            child: Center(
              child: _creating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('建立連結', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: colors.accent)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _linksSection(BuildContext context) {
    final colors = context.colors;
    final invites = _detail.invites;
    final canManageGroup = hasPermission(_detail.permissions, GroupPermission.manageGroup);
    if (invites.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionHeader('有效的邀請連結'), ListEmpty('還沒有邀請連結')],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < invites.length; i++) {
      final invite = invites[i];
      final url = inviteUrl(invite.code);
      // 自己建立的可以撤銷；別人的要「管理群組」
      final canRevoke = canManageGroup || (invite.createdBy != null && invite.createdBy!.id == widget.tab.myUid);
      if (i > 0) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    inviteMeta(invite),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '複製連結',
              onPressed: () => copyText(context, url, message: '已複製邀請連結'),
              icon: Icon(Icons.copy_rounded, size: 20, color: colors.inkMuted),
            ),
            IconButton(
              tooltip: 'QR Code',
              onPressed: () => showInviteQr(context, url),
              icon: Icon(Icons.qr_code_rounded, size: 20, color: colors.inkMuted),
            ),
            if (canRevoke)
              IconButton(
                tooltip: '撤銷',
                onPressed: () => _revoke(invite),
                icon: Icon(Icons.link_off_rounded, size: 20, color: colors.alarm),
              ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('有效的邀請連結'),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
        ),
      ],
    );
  }

  Widget _emailSection(BuildContext context, bool canInvite) {
    final colors = context.colors;
    final pending = _detail.emailInvites;
    final rows = <Widget>[
      if (canInvite)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _target,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _inviteUser(),
                  decoration: InputDecoration(
                    hintText: 'name@example.com 或 @someone',
                    isDense: true,
                    filled: true,
                    fillColor: colors.surface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _inviting || _target.text.trim().isEmpty ? null : _inviteUser,
                child: _inviting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('邀請'),
              ),
            ],
          ),
        ),
      if (pending.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text('沒有等待回覆的邀請', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
        ),
      for (final invite in pending)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invite.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body)),
                    Text(
                      '${byText(invite.invitedBy)}邀請・${formatDateTime(invite.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              // 有「邀請成員」或是自己發的可以取消
              if (canInvite || (invite.invitedBy != null && invite.invitedBy!.id == widget.tab.myUid))
                TextButton(
                  onPressed: _cancelling == invite.id ? null : () => _cancel(invite),
                  style: TextButton.styleFrom(foregroundColor: colors.alarm),
                  child: const Text('取消'),
                ),
            ],
          ),
        ),
    ];
    final separated = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) separated.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      separated.add(rows[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('用電子郵件或 @ID 邀請'),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: separated)),
        ),
        if (canInvite) const FootNote('對方登入後會在側欄的「邀請」看到，可以接受或拒絕；電子郵件可以是還沒註冊的人'),
      ],
    );
  }
}

/// 列右邊的選單：顯示目前的選項，點了選別的
class _OptionMenu<T> extends StatelessWidget {
  const _OptionMenu({required this.options, required this.label, required this.onSelected});

  final List<(T, String)> options;
  final String label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: (i) => onSelected(options[i].$1),
      itemBuilder: (context) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(value: i, child: Text(options[i].$2, style: const TextStyle(fontSize: AppText.body))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: AppText.body, color: colors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            Icon(Icons.unfold_more_rounded, size: 18, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

/// 剛建立的邀請連結：完整網址、複製、QR Code（同網站 InviteCreated）
class _InviteCreated extends StatefulWidget {
  const _InviteCreated({super.key, required this.code, required this.onClose});

  final String code;
  final VoidCallback onClose;

  @override
  State<_InviteCreated> createState() => _InviteCreatedState();
}

class _InviteCreatedState extends State<_InviteCreated> {
  bool _showQr = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = inviteUrl(widget.code);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('已建立邀請連結，傳給對方即可加入', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
              ),
              IconButton(tooltip: '關閉', onPressed: widget.onClose, icon: Icon(Icons.close_rounded, color: colors.inkMuted)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.small)),
              child: SelectableText(url, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => copyText(context, url, message: '已複製邀請連結'),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('複製'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showQr = !_showQr),
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: Text(_showQr ? '隱藏 QR Code' : 'QR Code'),
              ),
            ],
          ),
          if (_showQr) ...[
            const SizedBox(height: 8),
            Center(child: InviteQr(url: url)),
          ],
        ],
      ),
    );
  }
}

/// 邀請連結的 QR Code：白底圓角（深色主題也要掃得到）
class InviteQr extends StatelessWidget {
  const InviteQr({super.key, required this.url, this.size = 200});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: QrImageView(
          data: url,
          size: size,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(12),
          semanticsLabel: '邀請連結的 QR Code',
        ),
      );
}

/// 用對話框顯示一個邀請連結的 QR Code
Future<void> showInviteQr(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('邀請連結'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InviteQr(url: url, size: 220),
          const SizedBox(height: 12),
          SelectableText(url, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.caption, color: context.colors.inkMuted)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => copyText(context, url, message: '已複製邀請連結'), child: const Text('複製')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好')),
      ],
    ),
  );
}

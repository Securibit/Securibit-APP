import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../group_models.dart';
import '../groups_repository.dart' as repo;
import 'group_rules.dart';
import 'invite_scan_page.dart';

/*
 * 用邀請加入群組（同網站 /invite/[code]）：貼上邀請連結或代碼（手機也可以掃 QR Code），
 * 先用 group_invite_info 顯示群組、成員數與邀請人，確認後才 group_join。成功時以群組 id 關閉
 */
class JoinInviteForm extends StatefulWidget {
  const JoinInviteForm({super.key, this.code});

  // 從外面帶進來的連結或代碼（直接查詢）
  final String? code;

  @override
  State<JoinInviteForm> createState() => _JoinInviteFormState();
}

class _JoinInviteFormState extends State<JoinInviteForm> {
  late final _input = TextEditingController(text: widget.code ?? '');
  // 查到的邀請與當時的代碼；改了輸入就清掉
  InviteInfo? _info;
  String? _code;
  String? _error;
  bool _loading = false;
  bool _joining = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.code ?? '').trim().isNotEmpty) unawaited(_lookup());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _onEdited() {
    _seq++;
    setState(() {
      _info = null;
      _code = null;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _lookup() async {
    final code = parseInviteCode(_input.text);
    if (code == null) {
      setState(() => _error = _input.text.trim().isEmpty ? '請貼上邀請連結或代碼' : '看不出這是邀請連結，請確認連結是否完整');
      return;
    }
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await repo.loadInviteInfo(code);
    if (!mounted || seq != _seq) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _info = data;
          _code = code;
          _loading = false;
        });
      case Err(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
    }
  }

  Future<void> _join() async {
    final info = _info;
    final code = _code;
    if (info == null || code == null || _joining) return;
    // 已經是成員：直接前往群組
    if (info.alreadyMember && info.group != null) {
      Navigator.of(context).pop(info.group!.id);
      return;
    }
    setState(() => _joining = true);
    final result = await repo.joinGroup(code);
    if (!mounted) return;
    setState(() => _joining = false);
    switch (result) {
      case Err(:final message):
        await showErrorDialog(context, '加入群組失敗', message);
      case Ok(data: final gid):
        showToast(context, '已加入「${info.group?.name ?? '群組'}」');
        Navigator.of(context).pop(gid);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _input.text = text;
    _onEdited();
    await _lookup();
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const InviteScanPage()));
    if (value == null || !mounted) return;
    _input.text = value;
    _onEdited();
    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = _info;
    final String submitLabel;
    final bool submitEnabled;
    final VoidCallback onSubmit;
    if (info == null) {
      submitLabel = '下一步';
      submitEnabled = !_loading && _input.text.trim().isNotEmpty;
      onSubmit = _lookup;
    } else if (info.alreadyMember && info.group != null) {
      submitLabel = '前往群組';
      submitEnabled = true;
      onSubmit = _join;
    } else {
      submitLabel = '加入';
      submitEnabled = info.usable;
      onSubmit = _join;
    }

    return AdminFormScaffold(
      title: '用邀請加入群組',
      saving: _joining,
      onSubmit: onSubmit,
      submitLabel: submitLabel,
      submitEnabled: submitEnabled,
      children: [
        const FieldLabel('邀請連結或代碼'),
        TextField(
          controller: _input,
          autofocus: widget.code == null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onChanged: (_) => _onEdited(),
          onSubmitted: (_) => info == null ? _lookup() : null,
          decoration: InputDecoration(
            hintText: inviteUrl('…'),
            errorText: _error,
            errorMaxLines: 3,
            suffixIcon: IconButton(tooltip: '貼上', onPressed: _paste, icon: const Icon(Icons.content_paste_rounded)),
          ),
        ),
        if (AppPlatform.canScanQr) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('掃描 QR Code'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '向群組成員索取邀請連結，或請對方用電子郵件、@ID 邀請你（會出現在側欄的「邀請」）',
          style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
        ),
        const SizedBox(height: 24),
        if (_loading) const ListLoading() else if (info != null) _InviteCard(info: info),
      ],
    );
  }
}

/// 查到的邀請：群組名稱、成員數、邀請人、說明；不能用時說明原因
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.info});

  final InviteInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = info.group;
    if (!info.usable || group == null) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            const Text('無法使用這個邀請', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            MutedText(inviteReason(info.reason), center: true),
            const SizedBox(height: 4),
            Text('請向邀請你的人索取新的邀請連結', textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ],
        ),
      );
    }
    final inviter = inviterName(info.inviter);
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Text('你受邀加入群組', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          const SizedBox(height: 4),
          Text(group.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            [
              '${group.memberCount} 位成員',
              if (inviter != null) '由 $inviter 邀請',
            ].join('・'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            MutedText(group.description, center: true),
          ],
          if (info.alreadyMember) ...[
            const SizedBox(height: 12),
            Text('你已經是這個群組的成員', style: TextStyle(fontSize: AppText.caption, color: colors.accent, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

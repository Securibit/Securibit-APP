import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../admin/admin_models.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../group_models.dart';
import '../groups_repository.dart' as repo;
import 'group_rules.dart';
import 'group_tab_context.dart';

enum _BanAction { edit, unban }

/*
 * 封鎖名單分頁（同網站 GroupBans，要有「封鎖成員」）：被封鎖的人不能再透過邀請加入。
 * 用電子郵件或 @ID 封鎖（按「封鎖」後再填原因）、清單（頭像、名稱、@ID、看得到時的電子郵件、原因、誰封鎖的、時間）、
 * 修改原因、解除封鎖
 */
class GroupBansTab extends StatefulWidget {
  const GroupBansTab({super.key, required this.tab});

  final GroupTabContext tab;

  @override
  State<GroupBansTab> createState() => _GroupBansTabState();
}

class _GroupBansTabState extends State<GroupBansTab> {
  final _target = TextEditingController();
  List<GroupBan>? _bans;
  String? _error;

  String get _gid => widget.tab.groupId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GroupBansTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 群組資料重新載入時（例如在成員分頁封鎖了某人）一起更新
    if (oldWidget.tab.detail != widget.tab.detail) unawaited(_load());
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await repo.loadGroupBans(_gid);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(:final data):
          _bans = data;
          _error = null;
        case Err(:final message):
          _error = message;
      }
    });
  }

  Future<void> _add() async {
    final target = _target.text.trim();
    if (target.isEmpty) return;
    final saved = await showAdminForm<bool>(context, BanForm(groupId: _gid, target: target));
    if (saved != true || !mounted) return;
    _target.clear();
    setState(() {});
    // 對方可能是成員：成員清單與封鎖名單一起更新
    await widget.tab.onChanged();
    await _load();
  }

  Future<void> _onAction(GroupBan ban, _BanAction action) async {
    final name = ban.person.displayName;
    switch (action) {
      case _BanAction.edit:
        final saved = await showAdminForm<bool>(context, BanForm(groupId: _gid, existing: ban));
        if (saved == true && mounted) await _load();
      case _BanAction.unban:
        final ok = await confirmDialog(
          context,
          title: '解除封鎖',
          message: '確定要解除封鎖 $name 嗎？對方之後可以再透過邀請加入',
          confirmLabel: '解除封鎖',
        );
        if (!ok || !mounted) return;
        final result = await repo.unbanUser(_gid, ban.userId);
        if (!mounted) return;
        if (result case Err(:final message)) {
          await showErrorDialog(context, '解除封鎖失敗', message);
          return;
        }
        showToast(context, '已解除封鎖 $name');
        await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bans = _bans;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('封鎖使用者'),
        SoftCard(
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
                  onSubmitted: (_) => _add(),
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
                onPressed: _target.text.trim().isEmpty ? null : _add,
                style: TextButton.styleFrom(foregroundColor: colors.alarm),
                child: const Text('封鎖'),
              ),
            ],
          ),
        ),
        const FootNote('被封鎖的人無法再透過邀請加入；如果對方是成員，會一起移出群組。只能封鎖身分組比你低的成員'),
        const SizedBox(height: 28),
        SectionHeader(bans == null ? '封鎖名單' : '封鎖名單 ${bans.length}'),
        if (bans == null && _error != null)
          SoftCard(
            child: Column(
              children: [
                MutedText(_error!, center: true),
                TextButton(onPressed: _load, child: const Text('重試')),
              ],
            ),
          )
        else if (bans == null)
          const ListLoading()
        else if (bans.isEmpty)
          const ListEmpty('沒有封鎖任何人')
        else
          _list(context, bans),
      ],
    );
  }

  Widget _list(BuildContext context, List<GroupBan> bans) {
    final colors = context.colors;
    final openUser = widget.tab.onOpenUser;
    final rows = <Widget>[];
    for (var i = 0; i < bans.length; i++) {
      final ban = bans[i];
      final person = ban.person;
      // @ID 已經在名稱下面；有 @ID 又看得到電子郵件時另外列出
      final email = person.username != null ? person.email : null;
      if (i > 0) rows.add(Divider(indent: 64, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(InkWell(
        onTap: openUser == null ? null : () => openUser(person.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PersonChip(person: person),
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (email != null)
                            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                          Text(
                            ban.reason.isEmpty ? '沒有填寫原因' : ban.reason,
                            style: TextStyle(fontSize: AppText.secondary, color: ban.reason.isEmpty ? colors.inkMuted : colors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            banMeta(ban),
                            style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              MoreMenuButton<_BanAction>(
                actions: const [
                  MenuAction(_BanAction.edit, '修改原因', Icons.edit_rounded),
                  MenuAction(_BanAction.unban, '解除封鎖', Icons.lock_open_rounded, danger: true),
                ],
                onSelected: (a) => _onAction(ban, a),
              ),
            ],
          ),
        ),
      ));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    );
  }
}

/*
 * 封鎖原因（選填，同網站 BanReasonModal）：三種用法共用，成功時以 true 關閉
 * - target：在封鎖名單用電子郵件或 @ID 封鎖
 * - member：在成員分頁封鎖成員
 * - existing：修改封鎖原因
 */
class BanForm extends StatefulWidget {
  const BanForm({super.key, required this.groupId, this.target, this.member, this.existing})
      : assert((target != null ? 1 : 0) + (member != null ? 1 : 0) + (existing != null ? 1 : 0) == 1);

  final String groupId;
  final String? target;
  final GroupMember? member;
  final GroupBan? existing;

  @override
  State<BanForm> createState() => _BanFormState();
}

class _BanFormState extends State<BanForm> {
  late final _reason = TextEditingController(text: widget.existing?.reason ?? '');
  bool _saving = false;

  bool get _editing => widget.existing != null;

  // 顯示用的稱呼
  String get _name => widget.existing?.person.displayName ?? widget.member?.person.displayName ?? widget.target ?? '';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    final result = existing != null
        ? await repo.updateBanReason(widget.groupId, existing.userId, _reason.text)
        : await repo.banUser(widget.groupId, widget.member?.id ?? widget.target!, _reason.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, _editing ? '儲存失敗' : '封鎖失敗', message);
      return;
    }
    showToast(context, _editing ? '已更新封鎖原因' : '已封鎖 $_name');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final person = widget.existing?.person ?? widget.member?.person;
    final description = switch ((widget.member, widget.target)) {
      (_?, _) => '封鎖後對方會被移出群組，之後也無法再透過邀請加入，直到解除封鎖',
      (_, final target?) => '確定要封鎖 $target 嗎？對方如果是成員會一起移出群組',
      _ => null,
    };
    return AdminFormScaffold(
      title: _editing ? '修改封鎖原因' : (widget.member != null ? '封鎖 $_name' : '封鎖使用者'),
      saving: _saving,
      onSubmit: _submit,
      submitLabel: _editing ? '儲存' : '封鎖',
      danger: !_editing,
      children: [
        if (person != null) ...[
          SoftCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: PersonChip(person: person)),
          const SizedBox(height: 16),
        ],
        if (description != null) ...[
          Text(description, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
          const SizedBox(height: 20),
        ],
        const FieldLabel('原因'),
        TextField(
          controller: _reason,
          autofocus: true,
          maxLength: banReasonMax,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '只有能管理封鎖名單的人看得到',
            counterText: '',
            helperText: '選填，${_reason.text.characters.length} / $banReasonMax',
          ),
        ),
      ],
    );
  }
}

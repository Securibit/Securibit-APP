import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../groups/group_models.dart';
import '../../groups/groups_controller.dart';
import '../../settings/settings_controller.dart';
import '../../vault/vault_controller.dart';
import '../code_models.dart';
import '../codes_controller.dart';
import '../secret_handle.dart';
import '../totp/categories.dart';
import '../transfer/export_entry.dart';
import 'code_form.dart';
import 'otp_readout.dart';
import 'overwrite_editor.dart';

/// 右欄（或窄螢幕的下一頁）：選中那一筆的驗證碼、參數、金鑰與操作
class CodeDetailView extends StatelessWidget {
  const CodeDetailView({super.key, required this.accountId, this.onClosed, this.onClose});

  final String? accountId;
  // 刪除後（窄螢幕要回上一頁）
  final VoidCallback? onClosed;
  // 寬視窗右上角的關閉鈕，按了收起右欄；窄螢幕有返回鍵，不用傳
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CodesController>();
    final colors = context.colors;
    final account = controller.accounts?.where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            controller.locked ? '解鎖後就能查看驗證碼' : '選一筆驗證碼查看詳細資料',
            style: TextStyle(fontSize: AppText.body, color: colors.inkMuted),
          ),
        ),
      );
    }
    return _Detail(account: account, controller: controller, onClosed: onClosed, onClose: onClose);
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.account, required this.controller, this.onClosed, this.onClose});

  final GroupAccount account;
  final CodesController controller;
  final VoidCallback? onClosed;
  final VoidCallback? onClose;

  Future<void> _togglePin(BuildContext context) async {
    final error = await controller.togglePin(account);
    if (!context.mounted) return;
    if (error != null) {
      await showErrorDialog(context, account.pinned ? '取消釘選失敗' : '釘選失敗', error);
    } else {
      showToast(context, account.pinned ? '已取消釘選' : '已釘選到最上面');
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: '刪除驗證碼',
      message: controller.solo
          ? '確定要刪除「${account.name}」嗎？刪除後無法恢復'
          : '確定要從群組刪除「${account.name}」嗎？所有成員都會看不到這筆驗證碼，刪除後無法恢復',
      confirmLabel: '刪除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final error = await controller.delete(account);
    if (!context.mounted) return;
    if (error != null) {
      await showErrorDialog(context, '刪除驗證碼失敗', error);
      return;
    }
    showToast(context, '已刪除');
    onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hidden = context.select<SettingsController, bool>((s) => s.hideCodes);
    final secret = controller.secretOf(account);
    final categories = parseCategories(account.category);
    final canManage = controller.canManage(account);
    final canOverwrite = controller.canOverwrite;

    // 操作依權限列出（同網站 GroupCodeCard 的「更多」）：編輯、釘選、匯出、複製到其他群組、權限、刪除
    final actions = <Widget>[
      if (canManage) ...[
        GroupedRow(
          label: '編輯',
          accent: true,
          leading: Icon(Icons.edit_rounded, size: 20, color: colors.accent),
          onTap: () => showCodeForm(context, controller, account: account),
        ),
        GroupedRow(
          label: account.pinned ? '取消釘選' : '釘選到最上面',
          accent: true,
          leading: Icon(Icons.push_pin_rounded, size: 20, color: colors.accent),
          onTap: () => _togglePin(context),
        ),
      ],
      // 匯出與複製要拿得到正確的金鑰
      if (controller.canExport(account))
        GroupedRow(
          label: '匯出 QR Code',
          accent: true,
          leading: Icon(Icons.qr_code_rounded, size: 20, color: colors.accent),
          onTap: () => showExportItem(context, controller, account),
        ),
      if (controller.canCopy(account))
        GroupedRow(
          label: '複製到其他群組',
          accent: true,
          leading: Icon(Icons.copy_all_rounded, size: 20, color: colors.accent),
          onTap: () => showCopyToGroup(context, controller, account),
        ),
      if (canOverwrite)
        GroupedRow(
          label: '權限設定',
          accent: true,
          value: account.hasOverwrites ? '已個別設定' : null,
          leading: Icon(Icons.lock_person_rounded, size: 20, color: colors.accent),
          onTap: () => showOverwriteEditor(context, controller, account),
        ),
      if (canManage)
        GroupedRow(
          label: '刪除',
          danger: true,
          leading: Icon(Icons.delete_rounded, size: 20, color: colors.alarm),
          onTap: () => _delete(context),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          children: [
            if (account.pinned) ...[
              Icon(Icons.push_pin_rounded, size: 18, color: colors.inkMuted),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: SelectableText(
                account.name,
                style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700),
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: '關閉',
                icon: Icon(Icons.close_rounded, color: colors.inkMuted),
                style: IconButton.styleFrom(backgroundColor: colors.surface1),
              ),
          ],
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in categories)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(999)),
                  child: Text(name, style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: colors.inkMuted)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
          child: OtpReadout(
            key: ValueKey(account.id),
            account: account,
            secret: secret,
            server: controller.server,
            hidden: hidden,
            large: true,
          ),
        ),
        const SizedBox(height: 24),
        GroupedList(
          header: '設定',
          children: [
            GroupedRow(label: '位數', value: '${account.digits} 位數'),
            GroupedRow(label: '週期', value: '${account.period} 秒'),
            GroupedRow(label: '演算法', value: account.algorithm.label),
          ],
        ),
        const SizedBox(height: 24),
        _SecretSection(secret: secret, encrypted: controller.group.encrypted),
        // 沒辦法設定權限的人只看得到有沒有個別設定
        if (account.hasOverwrites && !canOverwrite) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('這筆驗證碼有個別設定權限', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          GroupedList(children: actions),
        ],
      ],
    );
  }
}

// 金鑰：有「查看金鑰」才看得到，預設遮住
class _SecretSection extends StatefulWidget {
  const _SecretSection({required this.secret, required this.encrypted});

  final SecretHandle? secret;
  final bool encrypted;

  @override
  State<_SecretSection> createState() => _SecretSectionState();
}

class _SecretSectionState extends State<_SecretSection> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secret = widget.secret;
    if (secret == null) {
      return GroupedList(
        header: '金鑰',
        footer: '你沒有「查看金鑰」權限，驗證碼由伺服器產生，金鑰不會傳到這台裝置',
        children: const [GroupedRow(label: '金鑰', value: '看不到')],
      );
    }
    final valid = secret.valid;
    // 按了「顯示金鑰」才從 Rust 取出來
    final display = !valid ? '金鑰錯誤' : (_visible ? (secret.reveal() ?? '金鑰錯誤') : '•' * 16);
    return GroupedList(
      header: '金鑰',
      footer: !valid
          ? '解不開這筆金鑰，可能是在其他裝置用舊的加密密碼新增的'
          : widget.encrypted
              ? '這個群組已加密，金鑰只在這台裝置解開'
              : null,
      children: [
        GroupedRow(
          label: '金鑰',
          value: display,
          trailing: valid
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _visible ? '隱藏金鑰' : '顯示金鑰',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _visible = !_visible),
                      icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: colors.inkMuted),
                    ),
                    IconButton(
                      tooltip: '複製金鑰',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final value = secret.reveal();
                        if (value != null) copyText(context, value, message: '已複製金鑰');
                      },
                      icon: Icon(Icons.copy_rounded, size: 20, color: colors.inkMuted),
                    ),
                  ],
                )
              : null,
        ),
      ],
    );
  }
}

/// 複製一份到其他群組（同網站 ShareToGroupModal）：只列出我有「管理驗證碼」的群組，
/// 目標是加密群組時要先解鎖，金鑰用加密密碼加密後才放進去
Future<void> showCopyToGroup(BuildContext context, CodesController controller, GroupAccount account) async {
  final groups = context.read<GroupsController>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  final wide = MediaQuery.sizeOf(context).width > 600;
  final target = await showDialog<GroupSummary>(
    context: context,
    builder: (_) => _CopyToGroupDialog(
      controller: controller,
      account: account,
      groups: copyTargetGroups(groups.groups ?? const [], controller.group.id),
    ),
  );
  if (target == null) return;
  // 側欄的筆數跟著更新
  unawaited(groups.reload());
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('已複製到「${target.name}」'),
      duration: const Duration(seconds: 6),
      width: wide ? 360 : null,
      action: SnackBarAction(
        label: '前往群組',
        onPressed: () {
          // 窄螢幕的詳細資料頁屬於原本的群組，先回到清單再切換
          navigator.popUntil((route) => route.isFirst);
          groups.select(target.id);
        },
      ),
    ));
}

class _CopyToGroupDialog extends StatefulWidget {
  const _CopyToGroupDialog({required this.controller, required this.account, required this.groups});

  final CodesController controller;
  final GroupAccount account;
  final List<GroupSummary> groups;

  @override
  State<_CopyToGroupDialog> createState() => _CopyToGroupDialogState();
}

class _CopyToGroupDialogState extends State<_CopyToGroupDialog> {
  final _passphrase = TextEditingController();
  // 只有一個群組時直接選好
  late String? _selected = widget.groups.length == 1 ? widget.groups.first.id : null;
  bool _copying = false;
  bool _unlocking = false;
  String? _unlockError;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  GroupSummary? get _target => widget.groups.where((g) => g.id == _selected).firstOrNull;

  Future<void> _unlock() async {
    if (_passphrase.text.isEmpty || _unlocking) return;
    setState(() {
      _unlocking = true;
      _unlockError = null;
    });
    final error = await context.read<VaultController>().unlock(_passphrase.text, remember: false);
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _unlockError = error;
    });
  }

  Future<void> _copy() async {
    final target = _target;
    if (target == null || _copying) return;
    setState(() => _copying = true);
    final error = await widget.controller.copyTo(widget.account, target);
    if (!mounted) return;
    setState(() => _copying = false);
    if (error != null) {
      await showErrorDialog(context, '複製到群組失敗', error);
      return;
    }
    Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vault = context.watch<VaultController>().status;
    final target = _target;
    final needUnlock = target != null && target.encrypted && vault != VaultStatus.unlocked;
    final canCopy = target != null && !needUnlock && !_copying;

    String? noteOf(GroupSummary group) {
      if (!group.encrypted) return group.description.isEmpty ? null : group.description;
      return switch (vault) {
        VaultStatus.unlocked => '已加密，金鑰會用你的加密密碼加密',
        VaultStatus.locked => '已加密，先輸入加密密碼解鎖才能放進去',
        VaultStatus.loading => '已加密，正在確認加密狀態',
        VaultStatus.off => '已加密，但找不到你的加密設定，請重新整理',
      };
    }

    bool selectable(GroupSummary group) => !group.encrypted || vault == VaultStatus.unlocked || vault == VaultStatus.locked;

    return AlertDialog(
      title: Text('複製「${widget.account.name}」到群組', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '會複製一份到群組，之後兩邊各自獨立；放進加密的群組時，金鑰會用你的加密密碼加密',
                style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
              ),
              const SizedBox(height: 16),
              if (widget.groups.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
                  child: Column(
                    children: [
                      const Text('你目前沒有可以新增驗證碼的群組', textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '需要在群組裡有「管理驗證碼」權限，可以自己建立群組，或請群組管理員開給你',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                      ),
                    ],
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  child: ColoredBox(
                    color: colors.surface1,
                    child: Column(
                      children: [
                        for (final (i, group) in widget.groups.indexed) ...[
                          if (i > 0) Divider(indent: 52, height: 0.5, color: colors.line.withValues(alpha: 0.6)),
                          _GroupOption(
                            group: group,
                            note: noteOf(group),
                            selected: group.id == _selected,
                            onTap: selectable(group) && !_copying
                                ? () => setState(() {
                                      _selected = group.id;
                                      _unlockError = null;
                                    })
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (needUnlock && vault == VaultStatus.locked) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_unlocking,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _unlock(),
                  onChanged: (_) {
                    if (_unlockError != null) setState(() => _unlockError = null);
                  },
                  decoration: InputDecoration(hintText: '加密密碼', errorText: _unlockError),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ListenableBuilder(
                    listenable: _passphrase,
                    builder: (context, _) => TextButton(
                      onPressed: _unlocking || _passphrase.text.isEmpty ? null : _unlock,
                      child: Text(_unlocking ? '解鎖中…' : '解鎖'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _copying ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('取消'),
        ),
        if (widget.groups.isNotEmpty)
          FilledButton(
            onPressed: canCopy ? _copy : null,
            child: _copying
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('複製'),
          ),
      ],
    );
  }
}

class _GroupOption extends StatelessWidget {
  const _GroupOption({required this.group, required this.note, required this.selected, required this.onTap});

  final GroupSummary group;
  final String? note;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled || selected ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? colors.accent : colors.inkMuted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (group.encrypted) ...[
                          Icon(Icons.lock_rounded, size: 15, color: colors.inkMuted),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (note != null)
                      Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../admin/admin_format.dart';
import '../../admin/admin_models.dart';
import '../../admin/permission_defs.dart';
import '../../admin/site_access.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../../settings/settings_view.dart';
import '../../vault/vault_controller.dart';
import '../../vault/vault_settings_section.dart';
import '../groups_repository.dart' as repo;
import 'group_forms.dart';
import 'group_rules.dart';
import 'group_tab_context.dart';

/*
 * 設定分頁（同網站 GroupSettings）：名稱與說明、群組 ID、預設群組與加密（只有擁有者）、
 * 轉移擁有權、離開群組、刪除群組。擋住的動作照網站一樣變灰並在下面說明原因
 */
class GroupSettingsTab extends StatefulWidget {
  const GroupSettingsTab({super.key, required this.tab});

  final GroupTabContext tab;

  @override
  State<GroupSettingsTab> createState() => _GroupSettingsTabState();
}

class _GroupSettingsTabState extends State<GroupSettingsTab> {
  late final _name = TextEditingController(text: _group.name);
  late final _description = TextEditingController(text: _group.description);
  String? _nameError;
  bool _saving = false;
  bool _settingDefault = false;
  bool _toggling = false;

  AdminGroupDetail get _detail => widget.tab.detail;
  GroupInfo get _group => _detail.group;

  bool get _dirty => _name.text.trim() != _group.name || _description.text.trim() != _group.description;

  @override
  void didUpdateWidget(covariant GroupSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 重新載入後（例如別人改了名稱），沒在編輯的欄位跟著更新
    final old = oldWidget.tab.detail.group;
    if (_name.text.trim() == old.name && old.name != _group.name) _name.text = _group.name;
    if (_description.text.trim() == old.description && old.description != _group.description) {
      _description.text = _group.description;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '請輸入群組名稱');
      return;
    }
    setState(() => _saving = true);
    final result = await repo.updateGroup(_group.id, _name.text, _description.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '儲存群組設定失敗', message);
      return;
    }
    showToast(context, '已儲存');
    await widget.tab.onChanged();
  }

  Future<void> _setDefault() async {
    setState(() => _settingDefault = true);
    final result = await repo.setDefaultGroup(_group.id);
    if (!mounted) return;
    setState(() => _settingDefault = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '設為預設群組失敗', message);
      return;
    }
    showToast(context, '已把「${_group.name}」設為預設群組');
    await widget.tab.onChanged();
  }

  Future<void> _toggleEncryption(bool encrypted) async {
    if (!encrypted) {
      final ok = await confirmDialog(
        context,
        title: '關閉加密',
        message: '關閉後「${_group.name}」的金鑰會改回明文存放在伺服器。確定要關閉嗎？',
        confirmLabel: '關閉加密',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _toggling = true);
    final error = await setGroupEncryption(context, _group.id, encrypted);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (error != null) {
      await showErrorDialog(context, encrypted ? '開啟加密失敗' : '關閉加密失敗', error);
      return;
    }
    showToast(context, encrypted ? '已開啟加密' : '已關閉加密');
    await widget.tab.onChanged();
  }

  Future<void> _transfer() async {
    final candidates = _detail.members.where((m) => !m.isOwner).toList();
    final name = await showAdminForm<String>(context, GroupTransferForm(groupId: _group.id, candidates: candidates));
    if (name == null || !mounted) return;
    showToast(context, '已將擁有權轉移給 $name');
    await widget.tab.onChanged();
  }

  Future<void> _leave() async {
    final ok = await confirmDialog(
      context,
      title: '離開群組',
      message: '確定要離開「${_group.name}」嗎？離開後就看不到群組的驗證碼，要重新受邀才能再加入',
      confirmLabel: '離開',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await repo.leaveGroup(_group.id);
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '離開群組失敗', message);
      return;
    }
    showToast(context, '已離開「${_group.name}」');
    widget.tab.onExit();
  }

  Future<void> _delete() async {
    final deleted = await showAdminForm<bool>(context, GroupDeleteForm(groupId: _group.id, groupName: _group.name));
    if (deleted != true || !mounted) return;
    widget.tab.onExit();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final colors = context.colors;
    final access = SiteAccessController.shared;
    final canEdit = hasPermission(detail.permissions, GroupPermission.manageGroup);
    final isMember = detail.members.any((m) => m.id == widget.tab.myUid);
    final canDelete = canDeleteGroup(detail, siteAdmin: access.can(SitePermission.administrator));
    final deleteBlocked = deleteBlockedReason(detail);
    final transferBlocked = transferBlockedReason(detail);
    final owner = detail.members.where((m) => m.isOwner).firstOrNull;
    final notes = dangerNotes(detail, canDelete: canDelete);
    final showDanger = detail.isOwner || isMember || canDelete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('群組資料'),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('名稱'),
              TextField(
                controller: _name,
                enabled: canEdit && !_saving,
                maxLength: groupNameMax,
                onChanged: (_) => setState(() => _nameError = null),
                decoration: InputDecoration(errorText: _nameError, counterText: '', fillColor: colors.surface),
              ),
              const SizedBox(height: 16),
              const FieldLabel('說明'),
              TextField(
                controller: _description,
                enabled: canEdit && !_saving,
                maxLength: groupDescriptionMax,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: canEdit ? '這個群組用來放哪些帳號的驗證碼' : null,
                  counterText: '',
                  fillColor: colors.surface,
                  helperText: canEdit ? '選填，${_description.text.characters.length} / $groupDescriptionMax' : null,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _dirty && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('儲存'),
                  ),
                ),
              ],
            ],
          ),
        ),
        FootNote(canEdit ? '名稱與說明會顯示給所有成員，以及收到邀請的人' : '需要「管理群組」權限才能修改名稱與說明'),
        const SizedBox(height: 24),
        GroupedList(
          header: '資訊',
          children: [
            GroupedRow(
              label: '群組 ID',
              value: _group.id,
              trailing: Icon(Icons.copy_rounded, size: 18, color: colors.inkMuted),
              onTap: () => copyText(context, _group.id),
            ),
            GroupedRow(label: '擁有者', value: owner?.person.displayName ?? '無'),
            GroupedRow(label: '建立時間', value: formatDateTime(_group.createdAt)),
            if (!detail.isOwner) GroupedRow(label: '加密', value: _group.encrypted ? '已開啟' : '未開啟'),
          ],
        ),
        if (detail.isOwner) ...[
          const SizedBox(height: 24),
          _defaultAndEncryption(context),
        ],
        if (showDanger) ...[
          const SizedBox(height: 28),
          GroupedList(
            footer: notes,
            children: [
              if (detail.isOwner) _DangerRow(label: '轉移擁有權', onTap: transferBlocked == null ? _transfer : null),
              if (isMember && !detail.isOwner) _DangerRow(label: '離開群組', onTap: _leave),
              if (canDelete) _DangerRow(label: '刪除群組', onTap: deleteBlocked == null ? _delete : null),
            ],
          ),
        ],
      ],
    );
  }

  // 預設群組與加密：只有擁有者
  Widget _defaultAndEncryption(BuildContext context) {
    final detail = _detail;
    final vault = context.watch<VaultController>().status;
    final hasOthers = detail.members.length > 1;
    // 要先解鎖才能切換；加密的群組只能有擁有者一人：還有其他成員時不能開
    final canToggle = vault == VaultStatus.unlocked && (_group.encrypted || !hasOthers);
    final needsUnlock = vault == VaultStatus.locked && (_group.encrypted || !hasOthers);
    final String encryptionHint;
    if (vault == VaultStatus.off) {
      encryptionHint = '加密要先到「設定」設定一組只有你知道的加密密碼';
    } else if (needsUnlock) {
      encryptionHint = '先輸入加密密碼解鎖才能切換';
    } else if (_group.encrypted) {
      encryptionHint = '金鑰會先在這台裝置用加密密碼加密才存到伺服器，只有你看得到；加密的群組不能邀請其他人。關閉後金鑰會改回明文存放';
    } else if (hasOthers) {
      encryptionHint = '群組還有其他成員，要先移除成員才能開啟加密（加密的群組只有你一個人）';
    } else {
      encryptionHint = '開啟後金鑰會先在這台裝置用加密密碼加密才存到伺服器，只有你看得到；加密的群組不能邀請其他人';
    }

    final list = GroupedList(
      header: '預設與加密',
      footer: '預設群組排在群組清單的第一個，新增驗證碼時預設放在這裡。$encryptionHint',
      children: [
        GroupedRow(
          label: '預設群組',
          value: detail.isDefault ? '目前的預設' : null,
          trailing: detail.isDefault
              ? null
              : TextButton(
                  onPressed: _settingDefault ? null : _setDefault,
                  child: _settingDefault
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('設為預設群組'),
                ),
        ),
        GroupedRow(
          label: '加密',
          trailing: vault == VaultStatus.off
              ? TextButton(onPressed: () => openSettings(context), child: const Text('先設定加密密碼'))
              : _toggling
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Switch(value: _group.encrypted, onChanged: canToggle ? _toggleEncryption : null),
        ),
      ],
    );
    if (!needsUnlock) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [list, const SizedBox(height: 12), const _VaultUnlockCard()],
    );
  }
}

/// 加密密碼鎖住時的解鎖框（同網站設定頁的 VaultUnlock compact）
class _VaultUnlockCard extends StatefulWidget {
  const _VaultUnlockCard();

  @override
  State<_VaultUnlockCard> createState() => _VaultUnlockCardState();
}

class _VaultUnlockCardState extends State<_VaultUnlockCard> {
  final _passphrase = TextEditingController();
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final passphrase = _passphrase.text;
    if (passphrase.isEmpty || _pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final error = await context.read<VaultController>().unlock(passphrase, remember: false);
    if (!mounted) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _passphrase,
              obscureText: true,
              enabled: !_pending,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _unlock(),
              decoration: InputDecoration(hintText: '加密密碼', isDense: true, errorText: _error, fillColor: colors.surface),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _pending || _passphrase.text.isEmpty ? null : _unlock,
            child: _pending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('解鎖'),
          ),
        ],
      ),
    );
  }
}

/// 整列置中的紅字動作；不能按時變灰
class _DangerRow extends StatelessWidget {
  const _DangerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: onTap == null ? colors.inkMuted : colors.alarm),
          ),
        ),
      ),
    );
  }
}

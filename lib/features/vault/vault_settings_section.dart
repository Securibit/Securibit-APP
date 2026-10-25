import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import '../groups/groups_controller.dart';
import 'vault_controller.dart';
import 'vault_forms.dart';

/*
 * 設定頁的「加密」區塊（同網站帳戶設定的 VaultSettings）：狀態、已加密的群組，
 * 未設定時設定密碼；鎖定時解鎖或忘記密碼重設；已解鎖時立即鎖定、更改密碼、停用加密。
 * 群組設定的「加密」開關呼叫 setGroupEncryption。
 */

const _footer = '加密套用在你擁有、已開啟加密的群組：金鑰會先在這台裝置用這組密碼加密才存到伺服器，資料庫裡只剩密文，網站管理員也看不到。'
    '密碼會另外用團隊離線保管的備援金鑰加密保存，只在你本人申請或法律要求時才會用來還原。'
    '設定密碼時會順便加密你的預設群組（只有你一個成員時），其他群組到群組設定的「加密」開關切換；加密的群組只能有你一個成員，不能邀請其他人。'
    '名稱與類別不會加密。每次在新的裝置或登出後都要輸入密碼';

/// 設定頁的「加密」區塊：設定、變更、停用、重設加密密碼
class VaultSettingsSection extends StatelessWidget {
  const VaultSettingsSection({super.key});

  Future<void> _open(BuildContext context, VaultFormMode mode) async {
    final done = await openVaultForm(context, mode);
    // 解鎖不會改變伺服器上的設定
    if (done && mode != VaultFormMode.unlock && context.mounted) _refreshAfterChange(context);
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultController>();
    final groups = context.watch<GroupsController>().groups;
    final status = vault.status;
    final encryptedNames = groups?.where((g) => g.isOwner && g.encrypted).map((g) => g.name).toList();

    return GroupedList(
      header: '加密',
      footer: _footer,
      children: [
        GroupedRow(
          label: '加密密碼',
          value: switch (status) {
            VaultStatus.off => '未設定',
            VaultStatus.loading => '確認中',
            VaultStatus.locked => '已設定，鎖定中',
            VaultStatus.unlocked => '已設定，已解鎖',
          },
        ),
        if (status != VaultStatus.off)
          GroupedRow(
            label: '已加密的群組',
            value: encryptedNames == null ? '…' : (encryptedNames.isEmpty ? '沒有' : encryptedNames.join('、')),
          ),
        if (status == VaultStatus.off)
          GroupedRow(label: '設定加密密碼', accent: true, onTap: () => _open(context, VaultFormMode.enable)),
        if (status == VaultStatus.locked) ...[
          GroupedRow(label: '解鎖', accent: true, onTap: () => _open(context, VaultFormMode.unlock)),
          GroupedRow(label: '忘記密碼', danger: true, onTap: () => confirmVaultReset(context)),
        ],
        if (status == VaultStatus.unlocked) ...[
          GroupedRow(
            label: '立即鎖定',
            accent: true,
            onTap: () async {
              await vault.lock();
              if (context.mounted) showToast(context, '已鎖定加密群組');
            },
          ),
          GroupedRow(label: '更改密碼', accent: true, onTap: () => _open(context, VaultFormMode.change)),
          GroupedRow(label: '停用加密', danger: true, onTap: () => _open(context, VaultFormMode.disable)),
        ],
      ],
    );
  }
}

/// 忘記加密密碼：確認後清空所有加密群組裡的驗證碼並停用加密（同網站 VaultUnlock 的「忘記密碼？」）
Future<void> confirmVaultReset(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    title: '忘記加密密碼',
    message: '也可以用帳戶的電子郵件寫信到 service@bityo.tw，確認是本人後我們可以協助還原密碼\n\n'
        '不想等的話，可以清空所有加密群組裡的驗證碼並停用加密（沒加密的群組不受影響），之後要到各服務重新綁定兩步驟驗證。確定要清空嗎？',
    confirmLabel: '清空並停用加密',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  final result = await context.read<VaultController>().reset();
  if (!context.mounted) return;
  final error = result.error;
  if (error != null) {
    await showErrorDialog(context, '重設失敗', error);
    return;
  }
  showToast(context, '已清空加密群組的驗證碼並停用加密');
  _refreshAfterChange(context);
}

// 加密設定或群組的加密狀態變了：重新讀取 profile（新的 vault 設定）與群組
void _refreshAfterChange(BuildContext context) {
  final refresh = context.read<VaultController>().onProfileChanged ?? context.read<AuthController>().loadProfile;
  unawaited(refresh());
  unawaited(context.read<GroupsController>().reload());
}

/// 開關群組加密；成功回傳 null，失敗回傳錯誤訊息
///
/// 條件同網站：要先設定加密密碼並解鎖、只有擁有者能切換、開啟時群組只能有自己一個成員。
/// 關閉加密前請呼叫端先確認（網站的文字：關閉後「群組名稱」的金鑰會改回明文存放在伺服器。確定要關閉嗎？）
Future<String?> setGroupEncryption(BuildContext context, String groupId, bool encrypted) async {
  final vault = context.read<VaultController>();
  final groups = context.read<GroupsController>();
  final group = groups.groups?.where((g) => g.id == groupId).firstOrNull;
  if (group != null) {
    if (!group.isOwner) return '只有群組擁有者可以切換加密';
    if (group.encrypted == encrypted) return null;
    if (encrypted && group.memberCount > 1) return '群組還有其他成員，請先移除成員再開啟加密';
  }
  final error = await vault.setGroupEncrypted(groupId, encrypted);
  if (error != null) return error;
  await groups.reload();
  return null;
}

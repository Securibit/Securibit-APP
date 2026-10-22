import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security_core.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../codes/codes_controller.dart';
import '../codes/widgets/code_form.dart';
import '../groups/group_models.dart';
import '../groups/groups_controller.dart';
import '../groups/manage/group_entry.dart';
import '../settings/settings_controller.dart';
import '../vault/vault_controller.dart';
import 'deep_link.dart';
import 'deep_link_controller.dart';

/*
 * 包在登入後的主畫面外面（見 RootView）：有等著的連結、而且 App 沒有鎖定時打開對應的畫面。
 * 主畫面出來代表已經登入；鎖定中就等解鎖（SecretSeal 解封時再看一次）。
 * - 邀請：打開「用邀請加入」並帶入代碼（同手動貼上）
 * - otpauth / otpauth-migration：先選要加到哪個群組（只有一個能加的就直接用），
 *   切到那個群組後由 CodeLinkHost 打開新增表單，使用者確認後才存
 */
class DeepLinkHost extends StatefulWidget {
  const DeepLinkHost({super.key, required this.child});

  final Widget child;

  @override
  State<DeepLinkHost> createState() => _DeepLinkHostState();
}

class _DeepLinkHostState extends State<DeepLinkHost> {
  late final DeepLinkController _links = context.read<DeepLinkController>();
  late final SettingsController _settings = context.read<SettingsController>();
  late final GroupsController _groups = context.read<GroupsController>();
  // 正在選群組，選完再看下一個
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _links.addListener(_check);
    _settings.appLock.addListener(_check);
    _groups.addListener(_check);
    SecretSeal.sealed.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _links.removeListener(_check);
    _settings.appLock.removeListener(_check);
    _groups.removeListener(_check);
    SecretSeal.sealed.removeListener(_check);
    // 登出：已經選好群組的請求不留給下一個帳號
    _links.clearCodeRequest();
    super.dispose();
  }

  void _check() {
    if (_busy || !mounted) return;
    // 新增驗證碼要先知道有哪些群組
    if (_links.pending is CodeLink && _groups.groups == null && _groups.error == null) return;
    final link = _links.takeIfReady(signedIn: true, locked: _settings.appLock.lockedAt(DateTime.now()));
    switch (link) {
      case null || InvalidLink():
        return;
      case InviteLink(:final code):
        unawaited(openJoinByInvite(context, code: code));
      case CodeLink():
        _busy = true;
        unawaited(_openCode(link).whenComplete(() {
          _busy = false;
          if (mounted) _check();
        }));
    }
  }

  Future<void> _openCode(CodeLink link) async {
    final title = link.bulk ? '無法匯入驗證碼' : '無法新增驗證碼';
    final list = _groups.groups;
    if (list == null) {
      await showErrorDialog(context, title, _groups.error ?? '還沒載入群組，請稍後再點一次連結');
      return;
    }
    if (_groups.offline) {
      await showErrorDialog(context, title, '沒有網路，無法新增驗證碼，連上網路後再點一次連結');
      return;
    }
    final vault = context.read<VaultController>();
    final eligible = groupsForNewCode(list, vaultUnlocked: vault.status == VaultStatus.unlocked && vault.keyId != null);
    if (eligible.isEmpty) {
      await showErrorDialog(context, title, noGroupForNewCodeReason(list));
      return;
    }
    final groupId = eligible.length == 1
        ? eligible.single.id
        : await showDialog<String>(
            context: context,
            builder: (_) => _GroupPicker(groups: eligible, selectedId: _groups.selectedId, bulk: link.bulk),
          );
    if (groupId == null || !mounted) return;
    _groups.select(groupId);
    _links.requestCode(groupId, link.text);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 選要加到哪個群組（目前顯示的群組打勾）
class _GroupPicker extends StatelessWidget {
  const _GroupPicker({required this.groups, required this.selectedId, required this.bulk});

  final List<GroupSummary> groups;
  final String? selectedId;
  final bool bulk;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(bulk ? '要匯入到哪個群組' : '要加到哪個群組'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in groups)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
                title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (group.isDefault) '預設群組',
                    if (group.encrypted) '已加密',
                    '${group.memberCount} 位成員',
                  ].join(' · '),
                  style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                ),
                trailing: group.id == selectedId ? Icon(Icons.check_rounded, color: colors.accent) : null,
                onTap: () => Navigator.of(context).pop(group.id),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消'))],
    );
  }
}

/*
 * 包在 CodesScope 裡面（見 HomeShell）：DeepLinkHost 選好群組後，等這個群組的清單讀好（重複的金鑰才比得出來），
 * 打開新增驗證碼表單並帶入連結，效果同在表單貼上 otpauth 連結（多筆時表單會再開整批匯入）。
 */
class CodeLinkHost extends StatefulWidget {
  const CodeLinkHost({super.key, required this.child});

  final Widget child;

  @override
  State<CodeLinkHost> createState() => _CodeLinkHostState();
}

class _CodeLinkHostState extends State<CodeLinkHost> {
  late final DeepLinkController _links = context.read<DeepLinkController>();
  // 換群組、解鎖或鎖定時 CodesScope 換新的 controller，這一層也會重建
  late final CodesController _codes = context.read<CodesController>();

  @override
  void initState() {
    super.initState();
    _links.addListener(_check);
    _codes.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _links.removeListener(_check);
    _codes.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final request = _links.codeRequest;
    if (request == null || request.groupId != _codes.group.id) return;
    // 清單還在讀
    if (!_codes.locked && _codes.accounts == null && _codes.error == null) return;
    _links.takeCodeRequest(request.groupId);
    if (_codes.locked) {
      unawaited(showErrorDialog(context, '無法新增驗證碼', '這個加密的群組還沒解鎖，解鎖後再點一次連結'));
      return;
    }
    if (!_codes.canAdd) {
      unawaited(showErrorDialog(
        context,
        '無法新增驗證碼',
        _codes.offline ? '沒有網路，無法新增驗證碼，連上網路後再點一次連結' : '你在這個群組沒有「管理驗證碼」權限',
      ));
      return;
    }
    unawaited(showCodeForm(context, _codes, initialText: request.text));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

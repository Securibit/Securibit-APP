import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../settings/settings_controller.dart';
import '../code_models.dart';
import '../codes_controller.dart';
import '../secret_handle.dart';
import '../totp/categories.dart';
import 'code_form.dart';
import 'otp_readout.dart';

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
        if (account.hasOverwrites) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('這筆驗證碼有個別設定權限', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ),
        ],
        if (canManage) ...[
          const SizedBox(height: 24),
          GroupedList(
            children: [
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
              GroupedRow(
                label: '刪除',
                danger: true,
                leading: Icon(Icons.delete_rounded, size: 20, color: colors.alarm),
                onTap: () => _delete(context),
              ),
            ],
          ),
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

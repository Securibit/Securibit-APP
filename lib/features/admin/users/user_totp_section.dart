import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../codes/code_models.dart';
import '../../codes/totp/categories.dart';
import '../../codes/totp/otp.dart';
import '../../codes/widgets/otp_readout.dart';
import '../admin_models.dart';
import '../admin_repository.dart' as repo;
import '../widgets/admin_widgets.dart';
import 'admin_totp_form.dart';

/*
 * 使用者的 2FA（他的預設群組，同網站 UserTotpList）：按「顯示」才載入，每次載入都會記一筆操作紀錄。
 * 動態碼在 App 用金鑰產生；預設群組已加密時沒有金鑰，只顯示「已加密」，管理員也不能改金鑰。
 */
class UserTotpSection extends StatefulWidget {
  const UserTotpSection({super.key, required this.user, required this.canManage});

  final AdminUser user;
  final bool canManage;

  @override
  State<UserTotpSection> createState() => _UserTotpSectionState();
}

class _UserTotpSectionState extends State<UserTotpSection> {
  List<AdminTotpItem>? _items;
  bool _loading = false;
  // 顯示金鑰的那幾筆
  final _revealed = <String>{};

  Future<void> _reveal() async {
    setState(() => _loading = true);
    final result = await repo.loadAdminUserTotp(widget.user.id);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case Ok(:final data):
        setState(() => _items = data);
      case Err(:final message):
        await showErrorDialog(context, '載入 2FA 失敗', message);
    }
  }

  void _hide() => setState(() {
        _items = null;
        _revealed.clear();
      });

  // 預設群組已加密時金鑰是密文，管理員看不到也不能改
  bool get _encrypted => _items?.any((item) => item.encrypted) ?? false;

  Future<void> _edit(AdminTotpItem item) async {
    final categories = collectCategories((_items ?? const []).map((i) => i.category));
    final updated = await showAdminForm<AdminTotpItem>(
      context,
      AdminTotpForm(
        item: item,
        secretLocked: _encrypted || item.encrypted,
        categories: categories,
        onSave: (patch) => repo.updateAdminUserTotp(widget.user.id, item.id, patch),
      ),
    );
    // 只更新畫面上那一筆，不重新載入（重新載入會再寫一筆查看紀錄）
    if (updated != null && mounted) {
      setState(() => _items = [for (final i in _items ?? const <AdminTotpItem>[]) i.id == updated.id ? updated : i]);
    }
  }

  Future<void> _delete(AdminTotpItem item) async {
    final ok = await confirmDialog(
      context,
      title: '刪除驗證碼',
      message: '確定要刪除這位使用者的「${item.name}」嗎？刪除後無法恢復，金鑰也會一併遺失',
      confirmLabel: '刪除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await repo.deleteAdminUserTotp(widget.user.id, item.id);
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '刪除驗證碼失敗', message);
      return;
    }
    setState(() => _items = _items?.where((i) => i.id != item.id).toList());
    showToast(context, '已刪除');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = _items;
    final count = items?.length ?? widget.user.totpCount;

    Widget body;
    if (items == null) {
      body = const SoftCard(child: MutedText('點「顯示」才會載入，查看會被記錄在操作紀錄'));
    } else if (items.isEmpty) {
      body = const ListEmpty('這位使用者沒有驗證碼');
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < items.length; i++) {
        if (i > 0) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
        final item = items[i];
        rows.add(_TotpRow(
          item: item,
          canManage: widget.canManage,
          showSecret: _revealed.contains(item.id),
          onToggleSecret: () => setState(() => _revealed.contains(item.id) ? _revealed.remove(item.id) : _revealed.add(item.id)),
          onEdit: () => _edit(item),
          onDelete: () => _delete(item),
        ));
      }
      body = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '驗證碼（$count 筆）',
          actionLabel: items != null ? '隱藏' : (_loading ? '載入中' : '顯示'),
          onAction: items != null ? _hide : (_loading ? null : _reveal),
        ),
        body,
        FootNote('這裡是使用者預設群組的驗證碼；其他群組請到「群組」管理${_encrypted ? '。這個群組已加密，管理員無法查看或修改金鑰' : ''}'),
      ],
    );
  }
}

class _TotpRow extends StatelessWidget {
  const _TotpRow({
    required this.item,
    required this.canManage,
    required this.showSecret,
    required this.onToggleSecret,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminTotpItem item;
  final bool canManage;
  final bool showSecret;
  final VoidCallback onToggleSecret;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  // OtpReadout 吃群組驗證碼的格式
  GroupAccount get _account => GroupAccount(
        id: item.id,
        name: item.name,
        category: item.category,
        digits: item.digits,
        period: item.period,
        algorithm: item.algorithm,
        pinned: item.pinned,
        permissions: 0,
        hasOverwrites: false,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secret = item.encrypted ? null : item.secret;
    final title = Row(
      children: [
        if (item.pinned) ...[
          Tooltip(message: '已釘選', child: Icon(Icons.push_pin_rounded, size: 14, color: colors.inkMuted)),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            item.name.isNotEmpty ? item.name : '（未命名）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final category = formatCategories(item.category);
    final leading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        if (category.isNotEmpty)
          Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
      ],
    );

    final actions = <MenuAction<String>>[
      if (secret != null) MenuAction('secret', showSecret ? '隱藏金鑰' : '顯示金鑰', showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded),
      if (canManage) const MenuAction('edit', '編輯', Icons.edit_rounded),
      if (canManage) const MenuAction('delete', '刪除', Icons.delete_rounded, danger: true),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: secret == null
                    ? Row(
                        children: [
                          Expanded(child: leading),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatOtp('•' * item.digits),
                                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600, color: colors.inkMuted),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_rounded, size: 12, color: colors.inkMuted),
                                  const SizedBox(width: 4),
                                  Text('已加密', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      )
                    : OtpReadout(account: _account, secret: secret, server: null, leading: leading),
              ),
              if (actions.isNotEmpty)
                MoreMenuButton<String>(
                  actions: actions,
                  onSelected: (value) => switch (value) {
                    'secret' => onToggleSecret(),
                    'edit' => onEdit(),
                    _ => onDelete(),
                  },
                )
              else
                const SizedBox(width: 12),
            ],
          ),
          if (secret != null && showSecret)
            Container(
              margin: const EdgeInsets.only(top: 10, right: 12),
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              decoration: BoxDecoration(color: colors.surface2, borderRadius: BorderRadius.circular(AppRadius.small)),
              child: Row(
                children: [
                  Text('金鑰', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Expanded(child: SelectableText(secret, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w500))),
                  IconButton(
                    tooltip: '複製金鑰',
                    onPressed: () => copyText(context, secret, message: '已複製金鑰'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

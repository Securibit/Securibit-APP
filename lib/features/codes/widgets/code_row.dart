import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../code_models.dart';
import '../totp/categories.dart';
import '../secret_handle.dart';
import 'otp_readout.dart';

/// 排序模式的上下移
class CodeRowSort {
  const CodeRowSort({required this.canUp, required this.canDown, required this.onUp, required this.onDown});

  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
}

// 清單裡的一筆：名稱與類別在左，驗證碼與倒數在右。點整列開詳細資料，點驗證碼複製
// 排序模式時最左邊多一組上下移的按鈕
class CodeRow extends StatelessWidget {
  const CodeRow({
    super.key,
    required this.account,
    required this.secret,
    required this.server,
    required this.hidden,
    required this.selected,
    required this.onOpen,
    this.sort,
  });

  final GroupAccount account;
  final SecretHandle? secret;
  final ServerCodes? server;
  final bool hidden;
  final bool selected;
  final VoidCallback onOpen;
  final CodeRowSort? sort;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final categories = formatCategories(account.category);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? colors.surface1 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          hoverColor: colors.surface1.withValues(alpha: 0.6),
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(sort == null ? 12 : 8, 12, 12, 12),
            child: Row(
              children: [
                if (sort != null) ...[_SortButtons(sort: sort!), const SizedBox(width: 10)],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final title = _Title(account: account, categories: categories);
                      // 窄的時候名稱在上、驗證碼在下，名稱才不會被擠掉
                      if (constraints.maxWidth < 360) {
                        return OtpReadout(account: account, secret: secret, server: server, hidden: hidden, leading: title);
                      }
                      return Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 12),
                          OtpReadout(account: account, secret: secret, server: server, hidden: hidden),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.account, required this.categories});

  final GroupAccount account;
  final String categories;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (account.pinned) ...[
              Icon(Icons.push_pin_rounded, size: 15, color: colors.inkMuted),
              const SizedBox(width: 4),
            ],
            if (account.hasOverwrites) ...[
              Tooltip(
                message: '這筆驗證碼有個別設定權限',
                child: Icon(Icons.lock_person_rounded, size: 15, color: colors.inkMuted),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (categories.isNotEmpty)
          Text(
            categories,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          ),
      ],
    );
  }
}

// 上下移的小圓鈕（同網站 GroupCodeCard 的排序模式）
class _SortButtons extends StatelessWidget {
  const _SortButtons({required this.sort});

  final CodeRowSort sort;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MoveButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: '往上移', onPressed: sort.canUp ? sort.onUp : null),
        const SizedBox(height: 4),
        _MoveButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: '往下移', onPressed: sort.canDown ? sort.onDown : null),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      style: IconButton.styleFrom(
        backgroundColor: colors.surface1,
        disabledBackgroundColor: colors.surface1.withValues(alpha: 0.5),
        foregroundColor: colors.ink,
        disabledForegroundColor: colors.inkMuted.withValues(alpha: 0.4),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

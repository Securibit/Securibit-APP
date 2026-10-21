import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../code_models.dart';
import '../totp/categories.dart';
import 'otp_readout.dart';

// 清單裡的一筆：名稱與類別在左，驗證碼與倒數在右。點整列開詳細資料，點驗證碼複製
class CodeRow extends StatelessWidget {
  const CodeRow({
    super.key,
    required this.account,
    required this.secret,
    required this.server,
    required this.hidden,
    required this.selected,
    required this.onOpen,
  });

  final GroupAccount account;
  final String? secret;
  final ServerCodes? server;
  final bool hidden;
  final bool selected;
  final VoidCallback onOpen;

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

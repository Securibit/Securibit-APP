import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ticker.dart';
import '../codes/totp/otp.dart';
import '../codes/widgets/countdown_ring.dart';

/*
 * 介紹頁與登入頁的「產品照」：不畫插圖，直接放 App 裡真的有的畫面，
 * 驗證碼用真的 TOTP 每 30 秒換一組（同網站首頁的 LiveReadout）。
 */

/// 示範用的帳號，金鑰是 RFC 6238 的測試向量，不是任何人的（同網站首頁）
class DemoAccount {
  const DemoAccount(this.name, this.account, this.secret);

  final String name;
  final String account;
  final String secret;
}

const demoAccounts = [
  DemoAccount('GitHub', 'andy@bityo.tw', 'JBSWY3DZEBSWY3DZEBSWY3DZ'),
  DemoAccount('Google', 'andy@bityo.tw', 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
  DemoAccount('Binance', 'andy@bityo.tw', 'KRSXG5CTMVRXEZLUKRSXG5CTMVRXEZLU'),
];

const _period = 30;

/// 示範驗證碼用的時鐘：平常是全 App 的秒針，測試時換成固定的時間
class DemoClock extends InheritedWidget {
  const DemoClock({super.key, required this.clock, required super.child});

  final ValueListenable<int> clock;

  static ValueListenable<int> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoClock>()?.clock ?? SecondTicker.shared;

  @override
  bool updateShouldNotify(DemoClock oldWidget) => oldWidget.clock != clock;
}

/// 某個時間點的示範驗證碼
class DemoCode {
  DemoCode._(this.code, this.next, this.secondsLeft);

  factory DemoCode.at(DemoAccount account, int nowMs) {
    final seconds = nowMs ~/ 1000;
    final counter = seconds ~/ _period;
    String generate(int c) => generateOtp(secret: account.secret, timestampMs: c * _period * 1000) ?? '------';
    return DemoCode._(generate(counter), generate(counter + 1), _period - seconds % _period);
  }

  final String code;
  final String next;
  final int secondsLeft;

  bool get expiring => isExpiring(secondsLeft, _period);
}

/// 每秒重建一次，只重建這一小塊
class DemoTicker extends StatelessWidget {
  const DemoTicker({super.key, required this.builder});

  final Widget Function(BuildContext context, int nowMs) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DemoClock.of(context),
      builder: (context, now, _) => builder(context, now),
    );
  }
}

/// 換一組驗證碼時，變了的數字往上捲出、新的從下面捲進來（像翻牌）
class RollingCode extends StatelessWidget {
  const RollingCode({super.key, required this.code, required this.style});

  // 已經格式化好的驗證碼（例如 123 456）
  final String code;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 420);
    final textStyle = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: code,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < code.length; i++)
            code[i] == ' '
                ? Text(' ', style: textStyle)
                : ClipRect(
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final incoming = child.key == ValueKey('$i${code[i]}');
                        return SlideTransition(
                          position: Tween(begin: Offset(0, incoming ? 0.9 : -0.9), end: Offset.zero).animate(animation),
                          child: FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: Text(code[i], key: ValueKey('$i${code[i]}'), style: textStyle),
                    ),
                  ),
        ],
      ),
    );
  }
}

/// 圓角卡片，跟 App 的清單一樣是白底、髮絲線框
class DemoCard extends StatelessWidget {
  const DemoCard({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: colors.line.withValues(alpha: 0.7), width: 0.5),
      ),
      child: child,
    );
  }
}

/// 驗證碼清單本人：搜尋列加上三筆會跳的驗證碼
class DemoCodeList extends StatelessWidget {
  const DemoCodeList({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final divider = Divider(height: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6));
    return DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 18, color: colors.inkMuted),
                        const SizedBox(width: 6),
                        Text('搜尋', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.add_rounded, size: 22, color: colors.accent),
                Text('新增', style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: colors.accent)),
              ],
            ),
          ),
          divider,
          for (var i = 0; i < demoAccounts.length; i++) ...[
            if (i > 0) divider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: DemoCodeRow(account: demoAccounts[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一筆驗證碼：名稱與帳號在左，驗證碼與倒數圈在右
class DemoCodeRow extends StatelessWidget {
  const DemoCodeRow({super.key, required this.account, this.codeSize = 26, this.showAccount = true});

  final DemoAccount account;
  final double codeSize;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
              if (showAccount)
                Text(account.account, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DemoTicker(
          builder: (context, now) {
            final code = DemoCode.at(account, now);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RollingCode(
                  code: formatOtp(code.code),
                  style: TextStyle(fontSize: codeSize, fontWeight: FontWeight.w600, height: 1.2, color: code.expiring ? colors.alarm : colors.ink),
                ),
                const SizedBox(width: 10),
                CountdownRing(secondsLeft: code.secondsLeft, period: _period, expiring: code.expiring, size: 32),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 大字版的一筆（同詳細資料頁）：快到期時顯示下一組
class DemoHeroCode extends StatelessWidget {
  const DemoHeroCode({super.key, this.account = const DemoAccount('GitHub', 'andy@bityo.tw', 'JBSWY3DZEBSWY3DZEBSWY3DZ')});

  final DemoAccount account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DemoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(account.name, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
          Text(account.account, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
          const SizedBox(height: 10),
          DemoTicker(
            builder: (context, now) {
              final code = DemoCode.at(account, now);
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: RollingCode(
                            code: formatOtp(code.code),
                            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w600, height: 1.15, color: code.expiring ? colors.alarm : colors.ink),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          code.expiring ? '下一組 ${formatOtp(code.next)}' : '每 30 秒換一組',
                          style: TextStyle(
                            fontSize: AppText.caption,
                            fontWeight: FontWeight.w500,
                            color: colors.inkMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  CountdownRing(secondsLeft: code.secondsLeft, period: _period, expiring: code.expiring, size: 48),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

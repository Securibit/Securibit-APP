import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ticker.dart';
import '../../../core/widgets/feedback.dart';
import '../code_models.dart';
import '../otp_snapshot.dart';
import '../secret_handle.dart';
import '../totp/otp.dart';
import 'countdown_ring.dart';

/*
 * 會跳動的驗證碼與倒數圈：只有這個 widget 監聽秒針，每秒重建的只有這一小塊。
 * 點一下複製；隱藏模式下點一下才顯示，換下一組時自動再藏起來（同網站）。
 */
class OtpReadout extends StatefulWidget {
  const OtpReadout({
    super.key,
    required this.account,
    required this.secret,
    required this.server,
    this.hidden = false,
    this.large = false,
    this.leading,
  });

  final GroupAccount account;
  // 指向 Rust 裡的金鑰；沒有「查看金鑰」時是 null，改用伺服器產碼
  final SecretHandle? secret;
  final ServerCodes? server;
  final bool hidden;
  // 詳細資料用的大字版
  final bool large;
  // 手機的直排版：名稱在上、驗證碼在下（給了 leading 就用直排）
  final Widget? leading;

  @override
  State<OtpReadout> createState() => _OtpReadoutState();
}

class _OtpReadoutState extends State<OtpReadout> {
  int? _revealedCounter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SecondTicker.shared,
      builder: (context, now, _) {
        final snapshot = OtpSnapshot.at(account: widget.account, secret: widget.secret, server: widget.server, nowMs: now);
        if (widget.large) return _buildLarge(context, snapshot);
        if (widget.leading != null) return _buildStacked(context, snapshot, widget.leading!);
        return _buildCompact(context, snapshot);
      },
    );
  }

  bool _revealed(OtpSnapshot s) => !widget.hidden || _revealedCounter == s.counter;

  Widget _code(BuildContext context, OtpSnapshot s, double fontSize) {
    final colors = context.colors;
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final digits = widget.account.digits;
    switch (s.state) {
      case OtpState.pending:
        return Text(formatOtp('-' * digits), style: style.copyWith(color: colors.inkMuted));
      case OtpState.invalid:
        return Text('金鑰錯誤', style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: colors.alarm));
      case OtpState.ready:
        final code = s.code!;
        if (!_revealed(s)) {
          return _Tap(
            tooltip: '顯示驗證碼',
            onTap: () => setState(() => _revealedCounter = s.counter),
            child: Text(formatOtp('•' * code.length), style: style.copyWith(color: colors.inkMuted)),
          );
        }
        return _Tap(
          tooltip: '點一下複製',
          onTap: () => copyText(context, code, message: '已複製驗證碼'),
          child: Text(formatOtp(code), style: style.copyWith(color: s.expiring ? colors.alarm : colors.ink)),
        );
    }
  }

  // 快到期時顯示下一組，點了複製下一組
  Widget? _next(BuildContext context, OtpSnapshot s) {
    final next = s.next;
    if (s.state != OtpState.ready || !s.expiring || next == null || !_revealed(s)) return null;
    return _Tap(
      tooltip: '複製下一組',
      onTap: () => copyText(context, next, message: '已複製下一組驗證碼'),
      child: Text(
        '下一組 ${formatOtp(next)}',
        style: TextStyle(
          fontSize: AppText.caption,
          fontWeight: FontWeight.w500,
          color: context.colors.inkMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, OtpSnapshot s) {
    final next = _next(context, s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _code(context, s, widget.account.digits == 8 ? 21 : 25),
            ?next,
          ],
        ),
        const SizedBox(width: 10),
        CountdownRing(secondsLeft: s.secondsLeft, period: s.period, expiring: s.expiring, size: 32),
      ],
    );
  }

  Widget _buildStacked(BuildContext context, OtpSnapshot s, Widget leading) {
    final next = _next(context, s);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: 4),
              _code(context, s, 30),
              ?next,
            ],
          ),
        ),
        const SizedBox(width: 12),
        CountdownRing(secondsLeft: s.secondsLeft, period: s.period, expiring: s.expiring, size: 36),
      ],
    );
  }

  Widget _buildLarge(BuildContext context, OtpSnapshot s) {
    final next = _next(context, s);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _code(context, s, 44)),
              const SizedBox(height: 4),
              next ??
                  Text(
                    s.state == OtpState.pending ? '正在取得驗證碼' : '點一下驗證碼即可複製',
                    style: TextStyle(fontSize: AppText.caption, color: context.colors.inkMuted),
                  ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        CountdownRing(secondsLeft: s.secondsLeft, period: s.period, expiring: s.expiring, size: 48),
      ],
    );
  }
}

// 可以點的文字：滑鼠移上去變手指，按下時淡一點
class _Tap extends StatelessWidget {
  const _Tap({required this.child, required this.onTap, required this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

// 圓形倒數：外圈是剩餘時間比例，中間是秒數；快到期變紅
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.secondsLeft,
    required this.period,
    required this.expiring,
    this.size = 36,
  });

  final int secondsLeft;
  final int period;
  final bool expiring;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = expiring ? colors.alarm : colors.accent;
    return Semantics(
      label: '剩餘 $secondsLeft 秒',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: secondsLeft / period,
            color: color,
            track: colors.line.withValues(alpha: 0.7),
            stroke: size / 14,
          ),
          child: Center(
            child: Text(
              '$secondsLeft',
              style: TextStyle(
                fontSize: AppText.caption,
                fontWeight: FontWeight.w600,
                color: expiring ? colors.alarm : colors.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.track, required this.stroke});

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(circle, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(circle, -math.pi / 2, math.pi * 2 * progress.clamp(0, 1), false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

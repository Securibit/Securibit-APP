import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform.dart';
import '../../../core/theme/tokens.dart';

/// 連到 dot 時要加進圖形的點：跨過中間還沒選的點會自動補上（同 Android 的圖形鎖）；已選過的點回傳空的
List<int> patternConnect(List<int> selected, int dot) {
  if (selected.contains(dot)) return const [];
  if (selected.isEmpty) return [dot];
  final last = selected.last;
  final (r1, c1) = (last ~/ 3, last % 3);
  final (r2, c2) = (dot ~/ 3, dot % 3);
  if ((r1 + r2).isEven && (c1 + c2).isEven) {
    final middle = (r1 + r2) ~/ 2 * 3 + (c1 + c2) ~/ 2;
    if (middle != last && middle != dot && !selected.contains(middle)) return [middle, dot];
  }
  return [dot];
}

/*
 * 九宮格圖形：手指或滑鼠按住拖過去連點，放開就送出。
 * clearSignal 改變時清掉畫好的圖形；error 時線條變紅（畫錯）。
 */
class PatternPad extends StatefulWidget {
  const PatternPad({super.key, required this.onComplete, this.enabled = true, this.error = false, this.clearSignal = 0});

  final ValueChanged<List<int>> onComplete;
  final bool enabled;
  final bool error;
  final int clearSignal;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final _dots = <int>[];
  Offset? _finger;
  bool _drawing = false;
  double _size = 0;

  @override
  void didUpdateWidget(PatternPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clearSignal != oldWidget.clearSignal) {
      _dots.clear();
      _finger = null;
      _drawing = false;
    }
  }

  Offset _center(int dot) {
    final cell = _size / 3;
    return Offset((dot % 3 + 0.5) * cell, (dot ~/ 3 + 0.5) * cell);
  }

  int? _hit(Offset position) {
    final radius = _size / 3 * 0.34;
    for (var dot = 0; dot < 9; dot++) {
      if ((_center(dot) - position).distance <= radius) return dot;
    }
    return null;
  }

  void _track(Offset position) {
    final dot = _hit(position);
    if (dot != null) {
      final added = patternConnect(_dots, dot);
      if (added.isNotEmpty) {
        _dots.addAll(added);
        if (AppPlatform.isMobile) HapticFeedback.selectionClick();
      }
    }
    setState(() => _finger = position);
  }

  void _start(Offset position) {
    if (!widget.enabled) return;
    setState(() {
      _dots.clear();
      _drawing = true;
    });
    _track(position);
  }

  void _end() {
    if (!_drawing) return;
    setState(() {
      _drawing = false;
      _finger = null;
    });
    if (_dots.isNotEmpty) widget.onComplete(List.unmodifiable(_dots));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = min(min(constraints.maxWidth, constraints.maxHeight), 320);
        return SizedBox.square(
          dimension: _size,
          child: Semantics(
            label: '九宮格圖形，按住並拖過至少四個點',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) => _start(details.localPosition),
              onPanUpdate: (details) {
                if (_drawing) _track(details.localPosition);
              },
              onPanEnd: (_) => _end(),
              onPanCancel: _end,
              child: CustomPaint(
                painter: _PatternPainter(
                  dots: List.of(_dots),
                  finger: _drawing ? _finger : null,
                  center: _center,
                  size: _size,
                  dotColor: colors.inkMuted.withValues(alpha: 0.45),
                  lineColor: widget.error ? colors.alarm : colors.accent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dots,
    required this.finger,
    required this.center,
    required this.size,
    required this.dotColor,
    required this.lineColor,
  });

  final List<int> dots;
  final Offset? finger;
  final Offset Function(int) center;
  final double size;
  final Color dotColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size _) {
    final cell = size / 3;
    final line = Paint()
      ..color = lineColor.withValues(alpha: 0.75)
      ..strokeWidth = max(4, cell * 0.05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (dots.isNotEmpty) {
      final path = Path()..moveTo(center(dots.first).dx, center(dots.first).dy);
      for (final dot in dots.skip(1)) {
        path.lineTo(center(dot).dx, center(dot).dy);
      }
      if (finger != null) path.lineTo(finger!.dx, finger!.dy);
      canvas.drawPath(path, line);
    }
    for (var dot = 0; dot < 9; dot++) {
      final selected = dots.contains(dot);
      if (selected) {
        canvas.drawCircle(center(dot), cell * 0.2, Paint()..color = lineColor.withValues(alpha: 0.16));
      }
      canvas.drawCircle(center(dot), selected ? cell * 0.075 : cell * 0.055, Paint()..color = selected ? lineColor : dotColor);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.finger != finger || old.lineColor != lineColor || old.dotColor != dotColor || old.size != size || !_sameDots(old.dots);

  bool _sameDots(List<int> other) {
    if (other.length != dots.length) return false;
    for (var i = 0; i < dots.length; i++) {
      if (other[i] != dots[i]) return false;
    }
    return true;
  }
}

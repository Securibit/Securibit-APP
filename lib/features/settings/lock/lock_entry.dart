import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform.dart';
import '../../../core/theme/tokens.dart';
import 'lock_secret.dart';
import 'pattern_pad.dart';

/*
 * 輸入圖形或密碼的區塊（鎖定畫面與設定流程共用），仿 iOS 的密碼畫面：
 * 標題、一行提示、圓點＋數字鍵盤（或九宮格）。輸入完自動送出，onSubmit 回傳 false 時抖動並清掉重來。
 * 桌面可以直接用鍵盤輸入數字、Backspace 刪除。
 */
class LockEntry extends StatefulWidget {
  const LockEntry({
    super.key,
    required this.type,
    required this.title,
    required this.onSubmit,
    this.message,
    this.error = false,
    this.enabled = true,
    this.keypadAction,
  });

  final LockType type;
  final String title;
  final String? message;
  // 提示是錯誤（紅字）
  final bool error;
  final bool enabled;
  // 回傳 true 代表接受
  final Future<bool> Function(String secret) onSubmit;
  // 數字鍵盤左下角的按鈕（生物辨識）
  final Widget? keypadAction;

  @override
  State<LockEntry> createState() => _LockEntryState();
}

class _LockEntryState extends State<LockEntry> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  String _pin = '';
  bool _busy = false;
  bool _wrong = false;
  int _clearSignal = 0;
  // 圖形太短之類不用送出的提示
  String? _localMessage;

  bool get _enabled => widget.enabled && !_busy;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _haptic(Future<void> Function() feedback) {
    if (AppPlatform.isMobile) feedback();
  }

  Future<void> _reject() async {
    _haptic(HapticFeedback.heavyImpact);
    await _shake.forward(from: 0);
  }

  Future<void> _submit(String secret) async {
    setState(() {
      _busy = true;
      _localMessage = null;
    });
    final ok = await widget.onSubmit(secret);
    if (!mounted) return;
    if (ok) {
      _haptic(HapticFeedback.lightImpact);
      setState(() => _busy = false);
      return;
    }
    setState(() => _wrong = true);
    await _reject();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _wrong = false;
      _clearSignal++;
    });
  }

  void _digit(String digit) {
    if (!_enabled || _pin.length >= widget.type.pinLength) return;
    _haptic(HapticFeedback.selectionClick);
    setState(() {
      _pin += digit;
      _localMessage = null;
    });
    if (_pin.length == widget.type.pinLength) _submit(_pin);
  }

  void _delete() {
    if (!_enabled || _pin.isEmpty) return;
    _haptic(HapticFeedback.selectionClick);
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _pattern(List<int> dots) async {
    if (dots.length < minPatternDots) {
      setState(() {
        _wrong = true;
        _localMessage = '至少連接 $minPatternDots 個點';
      });
      await _reject();
      if (!mounted) return;
      setState(() {
        _wrong = false;
        _clearSignal++;
      });
      return;
    }
    await _submit(encodePattern(dots));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.type.isPin || event is KeyUpEvent) return KeyEventResult.ignored;
    final character = event.character;
    if (character != null && character.length == 1 && '0123456789'.contains(character)) {
      _digit(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _delete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = _localMessage ?? widget.message;
    final isError = _localMessage != null || widget.error;
    final shaking = AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        return Transform.translate(offset: Offset(sin(t * pi * 5) * 14 * (1 - t), 0), child: child);
      },
      child: widget.type.isPin
          ? _PinDots(length: widget.type.pinLength, filled: _pin.length, error: _wrong)
          : PatternPad(onComplete: _pattern, enabled: _enabled, error: _wrong, clearSignal: _clearSignal),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700, color: colors.ink),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            height: 48,
            child: Text(
              message ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: AppText.secondary,
                fontWeight: FontWeight.w600,
                color: isError ? colors.alarm : colors.inkMuted,
              ),
            ),
          ),
          if (widget.type.isPin) ...[
            shaking,
            const SizedBox(height: 40),
            _PinPad(
              enabled: _enabled,
              onDigit: _digit,
              onDelete: _pin.isEmpty ? null : _delete,
              action: widget.keypadAction,
            ),
          ] else
            SizedBox(width: 300, height: 300, child: shaking),
        ],
      ),
    );
  }
}

// 密碼的圓點：輸入幾位就填滿幾個
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.filled, required this.error});

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = error ? colors.alarm : colors.ink;
    return Semantics(
      label: '已輸入 $filled 位，共 $length 位',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled ? color : Colors.transparent,
                  border: Border.all(color: color, width: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// iOS 風格的圓形數字鍵盤：1–9、左下角動作鍵、0、刪除
class _PinPad extends StatelessWidget {
  const _PinPad({required this.enabled, required this.onDigit, required this.onDelete, this.action});

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback? onDelete;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget key(String digit) => _PadKey(enabled: enabled, onTap: () => onDigit(digit), semantics: digit, child: Text(digit));
    Widget row(List<Widget> keys) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [for (final k in keys) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: k)]),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([key('1'), key('2'), key('3')]),
        row([key('4'), key('5'), key('6')]),
        row([key('7'), key('8'), key('9')]),
        row([
          SizedBox.square(dimension: _PadKey.size, child: action),
          key('0'),
          SizedBox.square(
            dimension: _PadKey.size,
            child: onDelete == null
                ? null
                : TextButton(
                    onPressed: enabled ? onDelete : null,
                    style: TextButton.styleFrom(foregroundColor: colors.ink, shape: const CircleBorder()),
                    child: const Text('刪除', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                  ),
          ),
        ]),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({required this.enabled, required this.onTap, required this.semantics, required this.child});

  static const size = 78.0;

  final bool enabled;
  final VoidCallback onTap;
  final String semantics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: colors.surface1,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          highlightColor: colors.surface2,
          splashFactory: NoSplash.splashFactory,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: enabled ? colors.ink : colors.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

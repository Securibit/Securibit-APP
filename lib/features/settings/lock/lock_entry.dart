import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform.dart';
import '../../../core/theme/tokens.dart';
import 'lock_secret.dart';
import 'pattern_pad.dart';

/*
 * 輸入圖形或密碼的區塊（鎖定畫面與設定流程共用），仿 iOS 的密碼畫面：
 * 標題（或鎖定畫面的品牌標題 heading）、一行提示、圓點＋數字鍵盤（或九宮格）。輸入完自動送出，onSubmit 回傳 false 時抖動並清掉重來。
 * 桌面可以直接用鍵盤輸入數字（上排數字鍵與數字小鍵盤）、Backspace 刪除。
 */
class LockEntry extends StatefulWidget {
  const LockEntry({
    super.key,
    required this.type,
    this.title,
    this.heading,
    required this.onSubmit,
    this.message,
    this.error = false,
    this.enabled = true,
    this.keypadAction,
  }) : assert(title != null || heading != null);

  final LockType type;
  // 文字標題；有 heading 時用 heading 取代
  final String? title;
  final Widget? heading;
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

  // 畫面上同時有好幾個（例如設定流程上面又蓋了鎖定畫面）時，只有最後出現的那個接鍵盤
  static final _mounted = <_LockEntryState>[];

  // Windows 的輸入法（見 windows/runner/flutter_window.cpp 的 securibit/ime）
  static const _ime = MethodChannel('securibit/ime');

  static Future<void> _setImeEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      await _ime.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 關不掉就算了，Num Lock 關掉時一樣能輸入
    }
  }

  @override
  void initState() {
    super.initState();
    // 第一個密碼畫面出現時關掉輸入法（數字小鍵盤才不會被中文輸入法攔走），最後一個離開時還原
    if (_mounted.isEmpty && widget.type.isPin) unawaited(_setImeEnabled(false));
    _mounted.add(this);
    // 直接接整個 App 的鍵盤事件，不靠焦點：鎖定前搜尋框之類拿著焦點、或視窗切換後焦點跑掉時也收得到
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _mounted.remove(this);
    if (_mounted.isEmpty) unawaited(_setImeEnabled(true));
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

  // 上排數字鍵與數字小鍵盤（數字小鍵盤在部分平台沒有 character，所以看按鍵本身）
  static final _digitKeys = {
    for (var i = 0; i <= 9; i++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): '$i',
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): '$i',
    },
  };

  // 數字小鍵盤的實體按鍵：Windows 關掉 Num Lock 時送出的是 End、↓ 之類，看實體位置才知道是哪個數字
  static final _numpadKeys = {
    PhysicalKeyboardKey.numpad0: '0',
    PhysicalKeyboardKey.numpad1: '1',
    PhysicalKeyboardKey.numpad2: '2',
    PhysicalKeyboardKey.numpad3: '3',
    PhysicalKeyboardKey.numpad4: '4',
    PhysicalKeyboardKey.numpad5: '5',
    PhysicalKeyboardKey.numpad6: '6',
    PhysicalKeyboardKey.numpad7: '7',
    PhysicalKeyboardKey.numpad8: '8',
    PhysicalKeyboardKey.numpad9: '9',
  };

  bool _onKey(KeyEvent event) {
    if (!widget.type.isPin || event is KeyUpEvent || !mounted) return false;
    // 上面蓋著對話框（例如忘記密碼）或另一個輸入區塊時不接
    if (_mounted.last != this || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = event.logicalKey;
    final character = event.character;
    final digit = _digitKeys[key] ?? _numpadKeys[event.physicalKey] ?? (character != null && character.length == 1 && '0123456789'.contains(character) ? character : null);
    if (digit != null) {
      _digit(digit);
      return true;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _delete();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = _localMessage ?? widget.message;
    final isError = _localMessage != null || widget.error;
    final heading = widget.heading;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading != null)
            heading
          else
            Text(
              widget.title ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700, color: colors.ink),
            ),
          SizedBox(height: heading != null ? 6 : 8),
          // 留兩行的高度，錯誤提示換行時下面的鍵盤不會跳動
          SizedBox(
            width: 300,
            height: 44,
            child: Text(
              message ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: AppText.secondary,
                fontWeight: isError ? FontWeight.w600 : FontWeight.w400,
                color: isError ? colors.alarm : colors.inkMuted,
              ),
            ),
          ),
          if (widget.type.isPin) ...[
            shaking,
            const SizedBox(height: 30),
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

// 密碼的圓點：輸入幾位就填滿幾個（綠色），還沒輸入的是灰色空心圈，錯誤時整排變紅
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.filled, required this.error});

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color color(int i) => error ? colors.alarm : (i < filled ? colors.accent : colors.inkMuted);
    return Semantics(
      label: '已輸入 $filled 位，共 $length 位',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled ? color(i) : Colors.transparent,
                  border: Border.all(color: color(i), width: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// iOS 風格的圓形數字鍵盤：1–9、左下角動作鍵、0、刪除（只有圖示、沒有圓底）；鍵距同設計稿（左右 106、上下 90）
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
          padding: const EdgeInsets.symmetric(vertical: 6),
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
                : IconButton(
                    tooltip: '刪除',
                    onPressed: enabled ? onDelete : null,
                    color: colors.inkMuted,
                    iconSize: 30,
                    icon: const Icon(Icons.backspace_outlined),
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
    // 深色用軟底、亮色再深一階，在漸層底上才看得出圓鍵
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: dark ? colors.surface1 : colors.surface2,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          highlightColor: dark ? colors.surface2 : colors.line,
          splashFactory: NoSplash.splashFactory,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 30,
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

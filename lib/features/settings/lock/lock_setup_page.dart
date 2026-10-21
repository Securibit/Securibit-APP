import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import 'app_lock_controller.dart';
import 'lock_entry.dart';
import 'lock_secret.dart';
import 'lock_wait.dart';

/// 設定、變更或關閉 App 鎖定；target 是 LockType.off 時代表關閉。回傳 true 代表有變更
Future<bool> openLockSetup(BuildContext context, AppLockController lock, LockType target) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => LockSetupPage(lock: lock, target: target)),
  );
  return changed ?? false;
}

// current：先輸入目前的；create：輸入新的；confirm：再輸入一次確認
enum _Step { current, create, confirm }

/*
 * 鎖定的設定流程：已經有鎖定時先輸入目前的圖形或密碼，
 * 新的要輸入兩次一樣才存（只存雜湊）。關閉鎖定只需要輸入目前的。
 */
class LockSetupPage extends StatefulWidget {
  const LockSetupPage({super.key, required this.lock, required this.target});

  final AppLockController lock;
  final LockType target;

  @override
  State<LockSetupPage> createState() => _LockSetupPageState();
}

class _LockSetupPageState extends State<LockSetupPage> with LockWaitTicker {
  late _Step _step = lock.enabled ? _Step.current : _Step.create;
  String? _first;
  String? _message;
  bool _error = false;
  bool _saving = false;

  @override
  AppLockController get lock => widget.lock;

  LockType get _target => widget.target;

  @override
  void initState() {
    super.initState();
    syncWait();
  }

  String get _pageTitle {
    if (_target == LockType.off) return '關閉鎖定';
    if (lock.enabled && lock.type == _target) return '變更${lockNoun(_target)}';
    return '設定${_target.label}';
  }

  String get _entryTitle => switch (_step) {
        _Step.current => lock.type.isPin ? '輸入目前的密碼' : '畫出目前的圖形',
        _Step.create => _target.isPin ? '輸入新的${_target.label}' : '畫出新的解鎖圖形',
        _Step.confirm => _target.isPin ? '再輸入一次密碼' : '再畫一次圖形',
      };

  String? get _hint => switch (_step) {
        _Step.create when !_target.isPin => '至少連接 $minPatternDots 個點',
        _Step.confirm => '確認兩次一樣',
        _ => null,
      };

  void _goTo(_Step step, {String? message, bool error = false}) {
    setState(() {
      _step = step;
      _message = message;
      _error = error;
    });
  }

  Future<bool> _submit(String secret) async {
    switch (_step) {
      case _Step.current:
        final result = await lock.verify(secret);
        if (!mounted) return false;
        if (result is! LockCheckOk) {
          syncWait();
          setState(() {
            _message = waiting ? null : lockCheckMessage(result, lock.type, DateTime.now());
            _error = true;
          });
          return false;
        }
        if (_target == LockType.off) {
          await _save(null);
          return true;
        }
        _goTo(_Step.create);
        return true;
      case _Step.create:
        _first = secret;
        _goTo(_Step.confirm);
        return true;
      case _Step.confirm:
        if (secret != _first) {
          _first = null;
          // 先讓這一次抖動，再回到第一步
          Future<void>.delayed(const Duration(milliseconds: 450), () {
            if (mounted) _goTo(_Step.create, message: '兩次不一樣，請重新設定', error: true);
          });
          return false;
        }
        await _save(secret);
        return true;
    }
  }

  // secret 是 null 時關閉鎖定
  Future<void> _save(String? secret) async {
    setState(() => _saving = true);
    final error = secret == null ? await lock.disable() : await lock.setLock(_target, secret);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      await showErrorDialog(context, '無法儲存鎖定設定', error);
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    showToast(context, secret == null ? '已關閉鎖定' : '已設定${_target.label}');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = _step == _Step.current ? lock.type : _target;
    final waitText = _step == _Step.current ? waitMessage : null;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(_pageTitle),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LockEntry(
                key: ValueKey(_step),
                type: type,
                title: _entryTitle,
                message: waitText ?? _message ?? _hint,
                error: waitText != null || (_message != null && _error),
                enabled: waitText == null && !_saving,
                onSubmit: _submit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

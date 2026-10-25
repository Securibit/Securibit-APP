import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import 'vault_controller.dart';

// 加密密碼至少幾個字元（同網站 VaultSettings）
const vaultMinLength = 8;

// enable：設定密碼並啟用；unlock：解鎖；change：更改密碼；disable：停用加密
enum VaultFormMode { enable, unlock, change, disable }

/// 打開加密密碼的表單；成功時回傳 true（成功的提示已經顯示）
Future<bool> openVaultForm(BuildContext context, VaultFormMode mode) async {
  final done = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => VaultFormPage(mode: mode)),
  );
  return done ?? false;
}

/*
 * 設定、解鎖、更改、停用加密密碼的表單（同網站 VaultSettings 的各個表單）。
 * 密碼只在送出時交給 Rust 計算。失敗時表單留著，可以修改後再送出。
 */
class VaultFormPage extends StatefulWidget {
  const VaultFormPage({super.key, required this.mode});

  final VaultFormMode mode;

  @override
  State<VaultFormPage> createState() => _VaultFormPageState();
}

class _VaultFormPageState extends State<VaultFormPage> {
  final _current = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _remember = false;
  bool _understood = false;
  bool _pending = false;
  // 解鎖時的錯誤（顯示在輸入框下面）
  String? _unlockError;

  VaultFormMode get _mode => widget.mode;
  bool get _needsCurrent => _mode == VaultFormMode.change || _mode == VaultFormMode.disable || _mode == VaultFormMode.unlock;
  bool get _needsNew => _mode == VaultFormMode.enable || _mode == VaultFormMode.change;

  bool get _tooShort => _passphrase.text.isNotEmpty && _passphrase.text.length < vaultMinLength;
  bool get _mismatch => _confirm.text.isNotEmpty && _confirm.text != _passphrase.text;
  bool get _newOk => _passphrase.text.length >= vaultMinLength && _confirm.text == _passphrase.text;

  bool get _canSubmit {
    if (_pending) return false;
    if (_needsCurrent && _current.text.isEmpty) return false;
    if (_needsNew && !_newOk) return false;
    if (_mode == VaultFormMode.enable && !_understood) return false;
    return true;
  }

  @override
  void dispose() {
    _current.dispose();
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _title => switch (_mode) {
        VaultFormMode.enable => '設定加密密碼',
        VaultFormMode.unlock => '解鎖加密群組',
        VaultFormMode.change => '更改密碼',
        VaultFormMode.disable => '停用加密',
      };

  String get _submitLabel => switch (_mode) {
        VaultFormMode.enable => '啟用',
        VaultFormMode.unlock => '解鎖',
        VaultFormMode.change => '更改',
        VaultFormMode.disable => '停用',
      };

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final vault = context.read<VaultController>();
    if (_mode == VaultFormMode.disable) {
      final ok = await confirmDialog(
        context,
        title: '停用加密',
        message: '停用後所有加密群組的金鑰會改回明文存放在伺服器，群組也會改成沒加密。確定要停用嗎？',
        confirmLabel: '停用加密',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _pending = true;
      _unlockError = null;
    });

    if (_mode == VaultFormMode.unlock) {
      final error = await vault.unlock(_current.text, remember: _remember);
      if (!mounted) return;
      setState(() {
        _pending = false;
        _unlockError = error;
      });
      if (error == null) Navigator.of(context).pop(true);
      return;
    }

    final (result, successText, failText) = switch (_mode) {
      VaultFormMode.enable => (await vault.enable(_passphrase.text, remember: _remember), '已設定加密密碼', '設定加密密碼失敗'),
      VaultFormMode.change => (await vault.changePassphrase(_current.text, _passphrase.text), '已更改加密密碼', '更改密碼失敗'),
      _ => (await vault.disable(_current.text), '已停用金鑰加密', '停用加密失敗'),
    };
    if (!mounted) return;
    setState(() => _pending = false);
    final error = result.error;
    if (error != null) {
      await showErrorDialog(context, failText, error);
      return;
    }
    final note = result.note;
    showToast(context, note == null ? successText : '$successText，$note');
    Navigator.of(context).pop(true);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
      );

  Widget _check({required bool value, required ValueChanged<bool> onChanged, required String text, bool danger = false}) {
    final colors = context.colors;
    return CheckboxListTile(
      value: value,
      onChanged: _pending ? null : (next) => onChanged(next ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      activeColor: danger ? colors.alarm : colors.accent,
      title: Text(text, style: TextStyle(fontSize: AppText.secondary, color: colors.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final danger = _mode == VaultFormMode.disable;

    final children = <Widget>[
      if (_needsCurrent) ...[
        _label(_mode == VaultFormMode.unlock ? '加密密碼' : '目前的密碼'),
        TextField(
          controller: _current,
          obscureText: true,
          autofocus: true,
          enabled: !_pending,
          autofillHints: const [AutofillHints.password],
          textInputAction: _needsNew ? TextInputAction.next : TextInputAction.done,
          onChanged: (_) => setState(() => _unlockError = null),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            errorText: _unlockError,
            helperText: danger ? '停用後所有加密群組的金鑰會改回明文存放在伺服器，群組也會改成沒加密' : null,
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (_needsNew) ...[
        _label(_mode == VaultFormMode.change ? '新密碼' : '加密密碼'),
        TextField(
          controller: _passphrase,
          obscureText: true,
          autofocus: !_needsCurrent,
          enabled: !_pending,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            errorText: _tooShort ? '至少 $vaultMinLength 個字元' : null,
            helperText: '不是 Google 帳號密碼，是另外設定、只有你知道的密碼',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 20),
        _label('再輸入一次'),
        TextField(
          controller: _confirm,
          obscureText: true,
          enabled: !_pending,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(errorText: _mismatch ? '兩次輸入的密碼不一樣' : null),
        ),
        const SizedBox(height: 12),
      ],
      if (_mode == VaultFormMode.enable || _mode == VaultFormMode.unlock)
        _check(
          value: _remember,
          onChanged: (value) => setState(() => _remember = value),
          text: '在這台裝置記住（登出或按「立即鎖定」就會忘記）',
        ),
      if (_mode == VaultFormMode.enable)
        _check(
          value: _understood,
          onChanged: (value) => setState(() => _understood = value),
          text: '我了解密碼會另外用團隊離線保管的備援金鑰加密保存，忘記時可以寫信請團隊協助還原',
          danger: true,
        ),
      if (_pending) ...[
        const SizedBox(height: 16),
        Text(
          _mode == VaultFormMode.unlock ? '解鎖中…' : '處理中，請不要關閉 App…',
          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
        ),
      ],
    ];

    return PopScope(
      canPop: !_pending,
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _pending ? null : () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(foregroundColor: colors.ink),
                      child: const Text('取消'),
                    ),
                    Expanded(
                      child: Text(
                        _title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: danger ? TextButton.styleFrom(foregroundColor: colors.alarm) : null,
                      child: _pending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_submitLabel),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

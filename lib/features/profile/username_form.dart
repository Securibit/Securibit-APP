import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../admin/widgets/admin_widgets.dart';
import '../auth/auth_controller.dart';
import 'profile_models.dart';
import 'profile_repository.dart' as repo;

// 停止輸入多久後才查資料庫（同網站）
const _checkDelay = Duration(milliseconds: 400);

/*
 * 設定自己的 @ID（同網站 UsernameSettings）：輸入時即時檢查格式、保留字與有沒有人用，可以清除。
 * 成功時以 true 關閉。
 */
class UsernameForm extends StatefulWidget {
  const UsernameForm({super.key, required this.current});

  // 目前的 @ID（不含 @，沒有時為空字串）
  final String current;

  @override
  State<UsernameForm> createState() => _UsernameFormState();
}

class _UsernameFormState extends State<UsernameForm> {
  late final _controller = TextEditingController(text: widget.current);
  UsernameCheck? _check;
  Timer? _timer;
  bool _saving = false;

  UsernameDraft get _draft => UsernameDraft(current: widget.current, input: _controller.text, check: _check);

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() {});
    _timer?.cancel();
    final draft = _draft;
    if (!draft.needCheck || draft.checked != null) return;
    final name = draft.name;
    _timer = Timer(_checkDelay, () async {
      final result = await repo.usernameAvailable(name);
      if (!mounted) return;
      setState(() {
        _check = switch (result) {
          Ok(:final data) => UsernameCheck(name: name, available: data),
          Err(:final message) => UsernameCheck(name: name, available: null, message: message),
        };
      });
    });
  }

  Future<void> _save(String next) async {
    if (_saving) return;
    setState(() => _saving = true);
    final result = await repo.setUsername(next);
    if (!mounted) return;
    switch (result) {
      case Err(:final message):
        setState(() => _saving = false);
        await showErrorDialog(context, next.isNotEmpty ? '設定 @ID 失敗' : '清除 @ID 失敗', message);
      case Ok(:final data):
        await context.read<AuthController>().refreshProfile();
        if (!mounted) return;
        showToast(context, data != null ? '已將 @ID 設為 @$data' : '已清除 @ID');
        Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = _draft;
    final error = draft.error;
    return AdminFormScaffold(
      title: '@ID',
      saving: _saving,
      submitEnabled: draft.canSave,
      onSubmit: () => _save(draft.name),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [_UsernameInputFormatter()],
          onChanged: _onChanged,
          onSubmitted: (_) {
            if (draft.canSave) _save(draft.name);
          },
          decoration: InputDecoration(
            hintText: 'your.id',
            prefixText: '@',
            errorText: error,
            errorMaxLines: 3,
            helperText: error == null ? draft.description : null,
            helperStyle: TextStyle(
              fontSize: AppText.caption,
              color: draft.changed && draft.checked?.available == true ? colors.accent : colors.inkMuted,
            ),
          ),
        ),
        if (widget.current.isNotEmpty) ...[
          const SizedBox(height: 24),
          DangerButton(label: '清除 @ID', onPressed: _saving ? null : () => _save('')),
        ],
        const SizedBox(height: 16),
        Text(
          '@ID 是別人找到你的名字，例如邀請你加入群組時可以輸入 @ID',
          style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
        ),
      ],
    );
  }
}

// 輸入時去掉空白與開頭的 @、轉小寫
class _UsernameInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = sanitizeUsernameInput(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

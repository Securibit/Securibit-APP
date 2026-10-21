import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_repository.dart' as repo;
import '../widgets/admin_widgets.dart';

/*
 * 修改使用者的名稱與 @ID（同網站 UserEditModal）：只送出有變動的欄位（沒變的傳 null），@ID 清空代表清除。
 * 成功時以 true 關閉。
 */
class UserEditForm extends StatefulWidget {
  const UserEditForm({super.key, required this.user});

  final AdminUser user;

  @override
  State<UserEditForm> createState() => _UserEditFormState();
}

class _UserEditFormState extends State<UserEditForm> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _username = TextEditingController(text: widget.user.username ?? '');
  bool _saving = false;
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  String get _nextName => _name.text.trim();
  String get _nextUsername => normalizeUsername(_username.text);

  String? get _nameError => _nextName.isEmpty ? '請輸入名稱' : null;

  // 格式、UUID 樣式、保留字（同資料庫）；沒改的不檢查（舊的 @ID 可能是後來才變成保留字）
  String? get _usernameError {
    final next = _nextUsername;
    if (next.isEmpty || next == (widget.user.username ?? '')) return null;
    return usernameProblem(next);
  }

  Future<void> _save() async {
    setState(() => _touched = true);
    if (_nameError != null || _usernameError != null) return;
    final nameChanged = _nextName != widget.user.name;
    final usernameChanged = _nextUsername != (widget.user.username ?? '');
    if (!nameChanged && !usernameChanged) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    final result = await repo.updateAdminUser(
      widget.user.id,
      name: nameChanged ? _nextName : null,
      username: usernameChanged ? _nextUsername : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '修改使用者失敗', message);
      return;
    }
    showToast(context, '已儲存');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: '編輯使用者',
      saving: _saving,
      onSubmit: _save,
      children: [
        const FieldLabel('名稱'),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(errorText: _touched || _name.text.isEmpty ? _nameError : null),
        ),
        const SizedBox(height: 20),
        const FieldLabel('@ID'),
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            hintText: '留空代表清除',
            prefixText: '@',
            errorText: _usernameError,
            helperText: '小寫英文、數字、底線與點，3～32 字',
          ),
        ),
      ],
    );
  }
}

/*
 * 刪除使用者（同網站 DeleteUserModal）：要先輸入對方的 email（沒有 email 時輸入使用者 ID）才能按刪除。
 * 走網站的 /api/admin/delete-user；成功時以 true 關閉。
 */
class UserDeleteForm extends StatefulWidget {
  const UserDeleteForm({super.key, required this.user});

  final AdminUser user;

  @override
  State<UserDeleteForm> createState() => _UserDeleteFormState();
}

class _UserDeleteFormState extends State<UserDeleteForm> {
  final _typed = TextEditingController();
  bool _pending = false;

  String get _expected => widget.user.email.isNotEmpty ? widget.user.email : widget.user.id;
  bool get _matched => _typed.text.trim().toLowerCase() == _expected.toLowerCase();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_matched || _pending) return;
    setState(() => _pending = true);
    final result = await repo.deleteAdminUser(widget.user.id);
    if (!mounted) return;
    setState(() => _pending = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '刪除使用者失敗', message);
      return;
    }
    showToast(context, '已刪除使用者');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = widget.user;
    return AdminFormScaffold(
      title: '刪除使用者',
      saving: _pending,
      onSubmit: _confirm,
      submitLabel: '刪除',
      submitEnabled: _matched,
      danger: true,
      children: [
        Text(
          '確定要刪除「${user.name.isNotEmpty ? user.name : user.email}」嗎？他的帳號、所有驗證碼與群組成員資格都會刪除，無法恢復。擁有群組的使用者要先轉移或刪除群組',
          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
        ),
        const SizedBox(height: 20),
        FieldLabel(user.email.isNotEmpty ? '輸入對方的 Email 以確認' : '輸入使用者 ID 以確認'),
        TextField(
          controller: _typed,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
          decoration: InputDecoration(hintText: _expected),
        ),
      ],
    );
  }
}

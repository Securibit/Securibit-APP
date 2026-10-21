import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_repository.dart' as repo;
import '../widgets/admin_widgets.dart';

// 與資料庫的 check 一致
const groupNameMax = 50;
const groupDescriptionMax = 300;

/*
 * 建立群組（同網站 CreateGroupModal，需要全站「建立群組」）：名稱必填、說明選填。
 * 成功時以新群組的 id 關閉。
 */
class GroupCreateForm extends StatefulWidget {
  const GroupCreateForm({super.key});

  @override
  State<GroupCreateForm> createState() => _GroupCreateFormState();
}

class _GroupCreateFormState extends State<GroupCreateForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '請輸入群組名稱');
      return;
    }
    setState(() => _saving = true);
    final result = await repo.createGroup(_name.text, _description.text);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok(data: final id):
        showToast(context, '已建立群組');
        Navigator.of(context).pop(id);
      case Err(:final message):
        await showErrorDialog(context, '建立群組失敗', message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: '建立群組',
      saving: _saving,
      onSubmit: _create,
      submitLabel: '建立',
      children: [
        const FieldLabel('名稱'),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: groupNameMax,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: InputDecoration(hintText: '例如：工程部共用帳號', errorText: _nameError, counterText: ''),
        ),
        const SizedBox(height: 20),
        const FieldLabel('說明'),
        TextField(
          controller: _description,
          maxLength: groupDescriptionMax,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '這個群組用來放哪些帳號的驗證碼',
            counterText: '',
            helperText: '選填，${_description.text.length} / $groupDescriptionMax',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '建立後你就是擁有者，可以邀請成員、設定身分組，決定誰能看到哪些驗證碼',
          style: TextStyle(fontSize: AppText.caption, color: context.colors.inkMuted),
        ),
      ],
    );
  }
}

/*
 * 刪除群組（同網站 DeleteGroupModal）：要輸入群組名稱才能按刪除。成功時以 true 關閉。
 */
class GroupDeleteForm extends StatefulWidget {
  const GroupDeleteForm({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  State<GroupDeleteForm> createState() => _GroupDeleteFormState();
}

class _GroupDeleteFormState extends State<GroupDeleteForm> {
  final _typed = TextEditingController();
  bool _pending = false;

  bool get _matched => _typed.text.trim() == widget.groupName.trim();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_matched || _pending) return;
    setState(() => _pending = true);
    final result = await repo.deleteGroup(widget.groupId);
    if (!mounted) return;
    setState(() => _pending = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '刪除群組失敗', message);
      return;
    }
    showToast(context, '已刪除「${widget.groupName}」');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: '刪除群組',
      saving: _pending,
      onSubmit: _confirm,
      submitLabel: '刪除群組',
      submitEnabled: _matched,
      danger: true,
      children: [
        Text(
          '刪除後群組的所有驗證碼、金鑰、身分組、成員與邀請都會一併刪除，無法恢復',
          style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted),
        ),
        const SizedBox(height: 20),
        FieldLabel('輸入群組名稱「${widget.groupName}」確認'),
        TextField(
          controller: _typed,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
          decoration: InputDecoration(hintText: widget.groupName),
        ),
      ],
    );
  }
}

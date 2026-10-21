import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../admin/widgets/admin_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/profile.dart';
import 'profile_models.dart';
import 'profile_repository.dart' as repo;

/*
 * 編輯個人資料（同網站 /me/update_info 的「個人資料」）：名稱（必填）、大頭照網址、背景圖網址、電話。
 * 電子郵件來自登入帳號，只顯示不能改。成功時以 true 關閉。
 */
class ProfileEditForm extends StatefulWidget {
  const ProfileEditForm({super.key, required this.profile});

  final Profile profile;

  @override
  State<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends State<ProfileEditForm> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _photo = TextEditingController(text: widget.profile.photoUrl);
  late final _bg = TextEditingController(text: visibleBgPhoto(widget.profile.bgPhotoUrl) ?? '');
  late final _phone = TextEditingController(text: widget.profile.phoneNumber);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _photo.dispose();
    _bg.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _nameInvalid => _name.text.trim().isEmpty;
  bool get _photoInvalid => !isHttpUrl(_photo.text);
  bool get _bgInvalid => !isHttpUrl(_bg.text);
  bool get _canSave => !_nameInvalid && !_photoInvalid && !_bgInvalid;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final result = await repo.updateProfile(
      widget.profile.uid,
      name: _name.text.trim(),
      photoUrl: _photo.text.trim(),
      bgPhotoUrl: _bg.text.trim(),
      phoneNumber: _phone.text.trim(),
    );
    if (!mounted) return;
    if (result case Err(:final message)) {
      setState(() => _saving = false);
      await showErrorDialog(context, '修改失敗', message);
      return;
    }
    await context.read<AuthController>().refreshProfile();
    if (!mounted) return;
    showToast(context, '已儲存');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final email = widget.profile.email;
    return AdminFormScaffold(
      title: '編輯個人資料',
      saving: _saving,
      submitEnabled: _canSave,
      onSubmit: _save,
      children: [
        const FieldLabel('電子郵件'),
        Text(email.isNotEmpty ? email : '無', style: TextStyle(fontSize: AppText.body, color: colors.inkMuted)),
        const SizedBox(height: 20),
        const FieldLabel('名稱'),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(errorText: _nameInvalid ? '請輸入名稱' : null),
        ),
        const SizedBox(height: 20),
        const FieldLabel('大頭照網址'),
        TextField(
          controller: _photo,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: 'https://', errorText: _photoInvalid ? '請輸入 http(s):// 開頭的網址' : null),
        ),
        const SizedBox(height: 20),
        const FieldLabel('背景圖網址'),
        TextField(
          controller: _bg,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: 'https://', errorText: _bgInvalid ? '請輸入 http(s):// 開頭的網址' : null),
        ),
        const SizedBox(height: 20),
        const FieldLabel('電話'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          onSubmitted: (_) => _save(),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          decoration: const InputDecoration(hintText: '0912-345-678'),
        ),
        const SizedBox(height: 16),
        Text(
          '名稱與大頭照會顯示在側欄、個人頁面與群組成員列表。電子郵件來自 Google 帳號，無法修改',
          style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
        ),
      ],
    );
  }
}

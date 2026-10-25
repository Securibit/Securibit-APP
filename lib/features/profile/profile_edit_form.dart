import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../admin/widgets/admin_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/profile.dart';
import 'photo_shrink.dart';
import 'profile_background.dart';
import 'profile_models.dart';
import 'profile_repository.dart' as repo;

/*
 * 編輯個人資料（同網站 /me/update_info 的「個人資料」）：名稱（必填）、電話；
 * 大頭照與背景圖只能從裝置選圖片上傳到網站（轉成 WebP、去掉中繼資料），不接受網址。
 * 圖片按下去就上傳或移除（不用按儲存）；大頭照可以改回 Google 頭像。
 * 電子郵件來自登入帳號，只顯示不能改。按儲存成功時以 true 關閉。
 */
class ProfileEditForm extends StatefulWidget {
  const ProfileEditForm({super.key, required this.profile});

  final Profile profile;

  @override
  State<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends State<ProfileEditForm> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _phone = TextEditingController(text: widget.profile.phoneNumber);
  bool _saving = false;
  // 正在上傳或移除的圖片
  PhotoKind? _photoPending;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _nameInvalid => _name.text.trim().isEmpty;

  Future<void> _save() async {
    if (_nameInvalid || _saving) return;
    setState(() => _saving = true);
    final result = await repo.updateProfile(widget.profile.uid, name: _name.text.trim(), phoneNumber: _phone.text.trim());
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

  // 選一張圖片（8 MB 以下）上傳
  Future<void> _upload(PhotoKind kind) async {
    if (_photoPending != null) return;
    final PlatformFile? file;
    try {
      file = (await FilePicker.pickFiles(type: FileType.image))?.files.firstOrNull;
    } catch (error) {
      if (mounted) await showErrorDialog(context, '無法選擇圖片', '無法開啟選擇檔案的視窗：$error');
      return;
    }
    if (file == null || !mounted) return;
    if (file.size > photoMaxBytes) {
      await showErrorDialog(context, '圖片太大', '請選擇 8 MB 以下的圖片');
      return;
    }
    setState(() => _photoPending = kind);
    List<int>? bytes = file.bytes;
    final path = file.path;
    if (bytes == null && path != null) {
      try {
        bytes = await File(path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _photoPending = null);
      await showErrorDialog(context, '無法讀取圖片', '讀不到這個檔案，請換一張圖片再試一次');
      return;
    }
    // 網站一次只收得下約 4 MB：太大的先在這台裝置縮小
    final shrunk = await shrinkForUpload(Uint8List.fromList(bytes), file.name);
    if (!mounted) return;
    if (shrunk == null) {
      setState(() => _photoPending = null);
      await showErrorDialog(context, '上傳${kind.label}失敗', '圖片太大，請換一張');
      return;
    }
    final result = await repo.uploadProfilePhoto(kind, shrunk.bytes, shrunk.filename);
    await _finish(result, done: '已更換${kind.label}', failed: '上傳${kind.label}失敗');
  }

  // 大頭照改回 Google 頭像、移除背景圖
  Future<void> _remove(PhotoKind kind) async {
    if (_photoPending != null) return;
    setState(() => _photoPending = kind);
    final result = await repo.removeProfilePhoto(kind);
    final avatar = kind == PhotoKind.avatar;
    await _finish(result, done: avatar ? '已改用 Google 頭像' : '已移除背景圖', failed: avatar ? '改用 Google 頭像失敗' : '移除背景圖失敗');
  }

  Future<void> _finish(Result<Object?> result, {required String done, required String failed}) async {
    if (!mounted) return;
    if (result case Err(:final message)) {
      setState(() => _photoPending = null);
      await showErrorDialog(context, failed, message);
      return;
    }
    // 重新讀取 profile，畫面上的圖片跟著換
    await context.read<AuthController>().refreshProfile();
    if (!mounted) return;
    setState(() => _photoPending = null);
    showToast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 圖片上傳後 profile 會重新讀取，用最新的
    final profile = context.select<AuthController, Profile?>((a) => a.profile) ?? widget.profile;
    final email = profile.email;
    return AdminFormScaffold(
      title: '編輯個人資料',
      saving: _saving,
      submitEnabled: !_nameInvalid && _photoPending == null,
      onSubmit: _save,
      children: [
        const FieldLabel('電子郵件'),
        Text(email.isNotEmpty ? email : '無', style: TextStyle(fontSize: AppText.body, color: colors.inkMuted)),
        const SizedBox(height: 20),
        const FieldLabel('名稱'),
        TextField(
          controller: _name,
          maxLength: profileNameMax,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(errorText: _nameInvalid ? '請輸入名稱' : null, counterText: ''),
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
        const SizedBox(height: 28),
        _avatarSection(context, profile),
        const SizedBox(height: 24),
        _backgroundSection(context, profile),
        const SizedBox(height: 16),
        Text(
          '名稱與大頭照會顯示在側欄、個人頁面與群組成員列表。電子郵件來自 Google 帳號，無法修改',
          style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
        ),
      ],
    );
  }

  Widget _spinner() => const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _avatarSection(BuildContext context, Profile profile) {
    final idle = _photoPending == null;
    final source = profile.photoCustom ? '自己上傳的照片' : (profile.photoUrl.isEmpty ? '沒有大頭照' : 'Google 頭像');
    return GroupedList(
      header: '大頭照',
      footer: '選一張 8 MB 以下的圖片，會裁成正方形',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              UserAvatar(name: profile.displayName, photoUrl: profile.photoUrl, size: 56),
              const SizedBox(width: 14),
              Expanded(child: Text(source, style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted))),
              if (_photoPending == PhotoKind.avatar) _spinner(),
            ],
          ),
        ),
        GroupedRow(label: '上傳照片', accent: idle, onTap: idle ? () => _upload(PhotoKind.avatar) : null),
        if (profile.photoCustom)
          GroupedRow(label: '使用 Google 頭像', accent: idle, onTap: idle ? () => _remove(PhotoKind.avatar) : null),
      ],
    );
  }

  Widget _backgroundSection(BuildContext context, Profile profile) {
    final idle = _photoPending == null;
    final hasBg = profile.bgPhotoUrl.isNotEmpty;
    return GroupedList(
      header: '背景圖',
      footer: '顯示在個人頁面上方，8 MB 以下',
      children: [
        // 沒有背景圖時是內建的漸層
        ProfileBackground(url: profile.bgPhotoUrl),
        GroupedRow(
          label: hasBg ? '更換圖片' : '上傳圖片',
          accent: idle,
          onTap: idle ? () => _upload(PhotoKind.background) : null,
          trailing: _photoPending == PhotoKind.background ? _spinner() : null,
        ),
        if (hasBg) GroupedRow(label: '移除背景', danger: true, onTap: idle ? () => _remove(PhotoKind.background) : null),
      ],
    );
  }
}

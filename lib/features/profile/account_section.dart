import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/grouped_list.dart';
import '../admin/admin_models.dart';
import '../admin/site_access.dart';
import '../admin/widgets/admin_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/profile.dart';
import '../auth/reauth.dart';
import 'profile_background.dart';
import 'profile_edit_form.dart';
import 'profile_entry.dart';
import 'profile_repository.dart' as repo;
import 'username_form.dart';

/// 打開「編輯個人資料」
Future<void> openProfileEdit(BuildContext context, Profile profile) =>
    showAdminForm<bool>(context, ProfileEditForm(profile: profile));

/// 打開「@ID」設定
Future<void> openUsernameEdit(BuildContext context, Profile profile) =>
    showAdminForm<bool>(context, UsernameForm(current: profile.username));

/*
 * 設定頁最上面的帳戶資料（同網站個人頁面的 PersonalCard 與 /me/update_info）：
 * 身分卡（背景圖、大頭照、名稱、email、編輯），「帳戶」分組（名稱、@ID、UID、Email、電話、身分組），
 * 再來是編輯、活動紀錄、已登入的裝置與同步 Google 資料。
 */
class AccountSection extends StatelessWidget {
  const AccountSection({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    // 全站身分組跟著權限重新讀取更新
    return ListenableBuilder(
      listenable: SiteAccessController.shared,
      builder: (context, _) => _build(context, SiteAccessController.shared.access.roles),
    );
  }

  Widget _build(BuildContext context, List<RoleBrief> roles) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentityCard(profile: profile),
        const SizedBox(height: 24),
        GroupedList(
          header: '帳戶',
          children: [
            GroupedRow(
              label: '名稱',
              value: profile.name.isEmpty ? '未設定' : profile.name,
              onTap: () => openProfileEdit(context, profile),
            ),
            GroupedRow(
              label: '@ID',
              value: profile.username.isEmpty ? null : '@${profile.username}',
              onTap: () => openUsernameEdit(context, profile),
              trailing: profile.username.isEmpty
                  ? Text('設定', style: TextStyle(fontSize: AppText.body, color: colors.accent, fontWeight: FontWeight.w600))
                  : _CopyButton(text: '@${profile.username}', message: '已複製 @ID'),
            ),
            GroupedRow(label: 'UID', value: profile.uid, trailing: _CopyButton(text: profile.uid, message: '已複製 UID')),
            GroupedRow(label: 'Email', value: profile.email.isNotEmpty ? profile.email : '無'),
            GroupedRow(
              label: '電話',
              value: profile.phoneNumber.isEmpty ? '未設定' : profile.phoneNumber,
              onTap: () => openProfileEdit(context, profile),
            ),
            if (roles.isNotEmpty) _SiteRolesRow(roles: roles),
          ],
        ),
        const SizedBox(height: 24),
        GroupedList(
          footer: '同步會用 Google 帳號的名稱與大頭照蓋掉目前的資料，背景圖、電話與自己上傳的大頭照保留',
          children: [
            GroupedRow(
              label: '活動紀錄',
              onTap: () => openActivity(context),
              trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
            ),
            GroupedRow(
              label: '已登入的裝置',
              onTap: () => openDevices(context),
              trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
            ),
            _SyncGoogleRow(photoCustom: profile.photoCustom),
          ],
        ),
      ],
    );
  }
}

// 身分卡：背景圖（沒有時是內建的漸層）在上面，下面是大頭照、名稱、email 與「編輯」
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: ColoredBox(
        color: colors.surface1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 沒有背景圖時是內建的漸層
            ProfileBackground(url: profile.bgPhotoUrl),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Row(
                children: [
                  UserAvatar(name: profile.displayName, photoUrl: profile.photoUrl, size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700),
                        ),
                        if (profile.email.isNotEmpty)
                          Text(
                            profile.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                          ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => openProfileEdit(context, profile), child: const Text('編輯')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 自己的全站身分組
class _SiteRolesRow extends StatelessWidget {
  const _SiteRolesRow({required this.roles});

  final List<RoleBrief> roles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 3), child: Text('身分組', style: TextStyle(fontSize: AppText.body))),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [for (final role in roles) RoleChip(name: role.name, color: role.color)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncGoogleRow extends StatefulWidget {
  const _SyncGoogleRow({required this.photoCustom});

  // 大頭照是自己上傳的：不蓋掉
  final bool photoCustom;

  @override
  State<_SyncGoogleRow> createState() => _SyncGoogleRowState();
}

class _SyncGoogleRowState extends State<_SyncGoogleRow> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final result = await repo.syncGoogleProfile(photoCustom: widget.photoCustom);
    if (!mounted) return;
    if (result case Err(:final message)) {
      setState(() => _syncing = false);
      await showErrorDialog(context, '同步 Google 資料失敗', message);
      return;
    }
    await context.read<AuthController>().refreshProfile();
    if (!mounted) return;
    setState(() => _syncing = false);
    showToast(context, '已同步 Google 資料');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GroupedRow(
      label: _syncing ? '同步中…' : '同步 Google 資料',
      accent: !_syncing,
      onTap: _syncing ? null : _sync,
      trailing: _syncing
          ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.inkMuted))
          : null,
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text, required this.message});

  final String text;
  final String message;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '複製',
        visualDensity: VisualDensity.compact,
        onPressed: () => copyText(context, text, message: message),
        icon: Icon(Icons.copy_rounded, size: 18, color: context.colors.inkMuted),
      );
}

/// 刪除自己的帳戶：先確認（同網站的文字），成功後登出並回到第一頁
Future<void> confirmDeleteAccount(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    title: '刪除帳戶',
    message: '確定要刪除帳戶嗎？帳戶與所有驗證碼金鑰都會永久刪除，無法恢復',
    confirmLabel: '刪除帳戶',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final auth = context.read<AuthController>();
  // 太久沒登入時先重新登入再刪
  final result = await withReauth(context, auth.deleteAccount);
  if (result case Err(:final message)) {
    if (context.mounted && !isReauthCancelled(result)) await showErrorDialog(context, '刪除帳戶失敗', message);
    return;
  }
  navigator.popUntil((route) => route.isFirst);
  messenger?.showSnackBar(const SnackBar(content: Text('已刪除帳戶'), duration: Duration(milliseconds: 1600)));
}

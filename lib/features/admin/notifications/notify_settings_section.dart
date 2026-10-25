import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../permission_defs.dart';
import '../site_access.dart';
import '../widgets/admin_widgets.dart';
import 'broadcast_models.dart';
import 'broadcast_repository.dart' as repo;

/*
 * 後台「通知設定」（同網站 /admin/settings）：後台修改帳號時要不要通知本人、強制更新的最低 App 版本。
 * 有「進入後台」就能看，要「管理使用者」才能修改（資料庫也會檢查）。
 */
class NotifySettingsSection extends StatefulWidget {
  const NotifySettingsSection({super.key});

  @override
  State<NotifySettingsSection> createState() => _NotifySettingsSectionState();
}

class _NotifySettingsSectionState extends State<NotifySettingsSection> {
  // null：載入中
  SiteSettings? _settings;
  String? _error;
  String? _savingNotify;
  bool _savingVersion = false;
  final _version = TextEditingController();
  final _message = TextEditingController();

  bool get _canEdit => SiteAccessController.shared.can(SitePermission.manageUsers);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _version.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await repo.loadSiteSettings();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _settings = data;
          _error = null;
          _version.text = data.minAppVersion?.version ?? '';
          _message.text = data.minAppVersion?.message ?? '';
        });
      case Err(:final message):
        setState(() => _error = message);
        await showErrorDialog(context, '載入通知設定失敗', message);
    }
  }

  Future<void> _toggleNotify(String key, bool on) async {
    final previous = _settings;
    if (previous == null) return;
    final next = previous.notifyAdminChanges.copyWith(key, on);
    setState(() {
      _settings = SiteSettings(notifyAdminChanges: next, minAppVersion: previous.minAppVersion);
      _savingNotify = key;
    });
    final result = await repo.saveAdminChangeNotify(next);
    if (!mounted) return;
    setState(() => _savingNotify = null);
    if (result case Err(:final message)) {
      setState(() => _settings = previous);
      await showErrorDialog(context, '儲存失敗', message);
    }
  }

  Future<void> _saveVersion() async {
    final settings = _settings;
    if (settings == null) return;
    final value = MinAppVersion(version: _version.text.trim(), message: _message.text.trim());
    setState(() => _savingVersion = true);
    final result = await repo.saveMinAppVersion(value);
    if (!mounted) return;
    setState(() => _savingVersion = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '儲存最低版本失敗', message);
      return;
    }
    setState(() => _settings = SiteSettings(notifyAdminChanges: settings.notifyAdminChanges, minAppVersion: value));
    showToast(context, '已儲存最低版本');
  }

  Future<void> _clearVersion() async {
    final settings = _settings;
    if (settings == null) return;
    final ok = await confirmDialog(
      context,
      title: '清除最低版本',
      message: '清除後所有版本的 App 都能繼續使用，不會再要求強制更新。',
      confirmLabel: '清除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final result = await repo.saveMinAppVersion(null);
    if (!mounted) return;
    if (result case Err(:final message)) {
      await showErrorDialog(context, '清除最低版本失敗', message);
      return;
    }
    setState(() {
      _settings = SiteSettings(notifyAdminChanges: settings.notifyAdminChanges, minAppVersion: null);
      _version.clear();
      _message.clear();
    });
    showToast(context, '已清除最低版本');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = _settings;
    if (settings == null) {
      return AdminScrollBody(
        onRefresh: _load,
        children: [_error == null ? const ListLoading() : const ListEmpty('讀不到設定，請稍後再試')],
      );
    }
    final canEdit = _canEdit;
    final current = settings.minAppVersion;
    final version = _version.text.trim();
    final message = _message.text.trim();
    final versionInvalid = version.isNotEmpty && !isValidVersion(version);
    final messageInvalid = message.length > minVersionMessageMax;
    final changed = version != (current?.version ?? '') || message != (current?.message ?? '');
    final canSave = canEdit && !_savingVersion && version.isNotEmpty && !versionInvalid && !messageInvalid && changed;

    return AdminScrollBody(
      onRefresh: _load,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: MutedText('後台修改帳號時的通知，以及 App 強制更新的最低版本'),
        ),
        GroupedList(
          header: '管理員修改帳號時通知本人',
          footer: '關掉後，管理員在後台做這些修改時不會通知使用者本人。開著的時候，使用者也可以在自己的通知設定關掉',
          children: [
            for (final (key, name, description) in adminChangeRows)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: AppText.body)),
                          Text(description, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: settings.notifyAdminChanges.of(key),
                      onChanged: !canEdit || _savingNotify == key ? null : (on) => _toggleNotify(key, on),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        GroupedList(
          header: '強制更新的最低 App 版本',
          footer: '版本低於這個的 App 打開時會整頁顯示「強制更新」與說明文字，更新前無法使用；App 離線讀不到設定時不會擋。網站不受影響',
          children: [
            GroupedRow(label: '目前', value: current?.version ?? '未設定'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('最低版本'),
                  TextField(
                    controller: _version,
                    readOnly: !canEdit,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: '1.5.0', errorText: versionInvalid ? '版本格式不正確，例如 1.5.0' : null),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('說明文字'),
                  TextField(
                    controller: _message,
                    readOnly: !canEdit,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: canEdit ? minVersionMessageMax : null,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '這個版本修正了重要的安全問題，請更新後再使用',
                      errorText: messageInvalid ? '最多 $minVersionMessageMax 字' : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (canEdit)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: canSave ? _saveVersion : null,
                child: _savingVersion ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('儲存'),
              ),
              if (current != null)
                TextButton(
                  onPressed: _clearVersion,
                  style: TextButton.styleFrom(foregroundColor: colors.alarm),
                  child: const Text('清除最低版本'),
                ),
            ],
          )
        else
          FootNote('需要「${permissionName(sitePermissionDefs, SitePermission.manageUsers)}」權限才能修改'),
      ],
    );
  }
}

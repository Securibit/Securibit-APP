import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/avatar.dart';
import '../admin_format.dart';
import '../admin_models.dart';

/*
 * 後台共用的小元件：身分組標籤（色點）、使用者、分組標題、清單狀態、搜尋框、表單外框。
 * 外觀同網站的 RoleChip / UserChip / ListStates，套 App 的代幣。
 */

/// 身分組的色點；沒有顏色時是灰點
class RoleDot extends StatelessWidget {
  const RoleDot({super.key, required this.color, this.size = 10});

  final String color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = parseRoleColor(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value == null ? context.colors.inkMuted : Color(value),
      ),
    );
  }
}

/// 身分組標籤：軟底圓角藥丸，有顏色就在前面放一個色點（亮色直接當字色在白底上看不清楚）
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.name, required this.color});

  final String name;
  final String color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colors.surface2, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parseRoleColor(color) != null) ...[RoleDot(color: color, size: 8), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 灰底小標籤（擁有者、你、已加密…）
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.accent = false, this.icon});

  final String text;
  final bool accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = accent ? colors.accent : colors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colors.surface2, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// 頭像 + 名稱 + 灰字（@ID 或 email）；使用者已刪除時傳 null
class PersonChip extends StatelessWidget {
  const PersonChip({super.key, required this.person, this.subtitle, this.size = 36});

  final PersonBrief? person;
  // 不給就用 @ID / email
  final String? subtitle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = person;
    final sub = subtitle ?? p?.subtitle;
    return Row(
      children: [
        p == null
            ? Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: colors.surface2, shape: BoxShape.circle),
                child: Icon(Icons.person_rounded, size: size * 0.5, color: colors.inkMuted),
              )
            : UserAvatar(name: p.name.isNotEmpty ? p.name : (p.username ?? '?'), photoUrl: p.photoUrl, size: size),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p == null ? '已刪除的使用者' : (p.name.isNotEmpty ? p.name : '（未命名）'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w600,
                  color: p == null ? colors.inkMuted : colors.ink,
                ),
              ),
              if (sub != null && sub.isNotEmpty)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 分組標題：灰色小字，右邊可以放一個動作（編輯、顯示…）
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.trailing});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: colors.inkMuted)),
          ),
          ?trailing,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// 軟底圓角的卡片（分組清單的單一區塊）
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: context.colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
        child: child,
      );
}

/// 卡片裡的灰字說明
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted),
      );
}

/// 分組清單下方的灰色小字
class FootNote extends StatelessWidget {
  const FootNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(text, style: TextStyle(fontSize: AppText.caption, color: context.colors.inkMuted)),
      );
}

class ListLoading extends StatelessWidget {
  const ListLoading({super.key});

  @override
  Widget build(BuildContext context) => const SoftCard(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
}

class ListEmpty extends StatelessWidget {
  const ListEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: MutedText(text, center: true),
      );
}

/// 「載入更多」
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({super.key, required this.onPressed, required this.loading});

  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: TextButton(
            onPressed: loading ? null : onPressed,
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('載入更多'),
          ),
        ),
      );
}

/// 搜尋框（同網站後台的搜尋列）
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }
}

/// 有進入後台、但沒有這個區塊需要的權限
class NoPermissionView extends StatelessWidget {
  const NoPermissionView({super.key, required this.permission});

  final String permission;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            children: [
              const Text('沒有權限', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              MutedText('這個頁面需要「$permission」權限，請聯絡管理員', center: true),
            ],
          ),
        ),
      );
}

/// 置中、限制最大寬度的捲動內容（寬視窗不要拉滿整條）
class AdminScrollBody extends StatelessWidget {
  const AdminScrollBody({super.key, required this.children, this.maxWidth = 720, this.onRefresh, this.controller});

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        for (final child in children)
          Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child)),
      ],
    );
    return onRefresh == null ? list : RefreshIndicator.adaptive(onRefresh: onRefresh!, child: list);
  }
}

/// 大標題（詳細資料頁的最上面）
class DetailTitle extends StatelessWidget {
  const DetailTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 整列紅字的危險動作（刪除使用者、刪除身分組…）
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppText.body,
                fontWeight: FontWeight.w600,
                color: onPressed == null ? colors.inkMuted : colors.alarm,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表單：寬視窗用對話框，窄螢幕用整頁（同 App 的 showCodeForm）
Future<T?> showAdminForm<T>(BuildContext context, Widget form) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720), child: form),
      ),
    );
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => form));
}

/// 表單外框：上面一列「取消｜標題｜儲存」，下面是欄位
class AdminFormScaffold extends StatelessWidget {
  const AdminFormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    required this.saving,
    this.submitLabel = '儲存',
    this.submitEnabled = true,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSubmit;
  final bool saving;
  final String submitLabel;
  final bool submitEnabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: colors.ink),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: saving || !submitEnabled ? null : onSubmit,
                    style: danger ? TextButton.styleFrom(foregroundColor: colors.alarm) : null,
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(submitLabel),
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
    );
  }
}

/// 表單欄位上方的粗體標籤
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
      );
}

/// 動作選單的一項
class MenuAction<T> {
  const MenuAction(this.value, this.label, this.icon, {this.danger = false, this.enabled = true});

  final T value;
  final String label;
  final IconData icon;
  final bool danger;
  final bool enabled;
}

/// 「更多」按鈕（…），點了跳出選單
class MoreMenuButton<T> extends StatelessWidget {
  const MoreMenuButton({super.key, required this.actions, required this.onSelected});

  final List<MenuAction<T>> actions;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<T>(
      tooltip: '更多',
      icon: Icon(Icons.more_horiz_rounded, color: colors.inkMuted),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<T>(
            value: action.value,
            enabled: action.enabled,
            child: Row(
              children: [
                Icon(action.icon, size: 20, color: action.danger ? colors.alarm : colors.inkMuted),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: AppText.body,
                    color: !action.enabled ? colors.inkMuted : (action.danger ? colors.alarm : colors.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

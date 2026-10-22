import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/sliding_selection.dart';
import '../auth/auth_controller.dart';
import '../auth/profile.dart';
import 'group_actions.dart';
import 'group_models.dart';
import 'groups_controller.dart';

/*
 * 側欄（桌面的左欄、手機的 Drawer）：群組清單（照 my_groups 的順序）、待回覆的邀請，最下面是帳戶。
 * 預設群組標「預設」，加密的群組有鎖頭。群組標題旁的「＋」新增群組或用邀請加入；
 * 群組列按右鍵、「…」或長按（手機）打開管理群組、邀請成員、調整順序。
 * 桌面寬視窗的側欄可以收起來，收起鍵放在最上面一列的右邊（headerAction）。
 */
class GroupSidebar extends StatelessWidget {
  const GroupSidebar({super.key, required this.onOpenSettings, this.onSelected, this.headerAction});

  final VoidCallback onOpenSettings;
  // 選了群組之後（手機要關掉 Drawer）
  final VoidCallback? onSelected;
  // 最上面一列右邊的按鈕（桌面寬視窗的收起側欄）
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = context.watch<GroupsController>();
    final list = groups.groups;
    final selectedId = groups.selectedId;

    return ColoredBox(
      color: colors.surface1,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: headerAction == null
                  ? const EdgeInsets.fromLTRB(20, 16, 16, 12)
                  // 按鈕比 Logo 高，上下少留一點，整列一樣高
                  : const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  const AppLogo(size: 28),
                  const SizedBox(width: 10),
                  const Text('Securibit', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (groups.loading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else if (groups.offline)
                    Tooltip(message: '目前離線', child: Icon(Icons.cloud_off_rounded, size: 18, color: colors.inkMuted)),
                  if (headerAction != null) ...[const SizedBox(width: 4), headerAction!],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _SectionLabel('群組', trailing: AddGroupButton(beforeOpen: onSelected)),
                  if (list == null && groups.error == null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                  if (groups.error != null && list == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(groups.error!, style: TextStyle(fontSize: AppText.secondary, color: colors.alarm)),
                          TextButton(onPressed: groups.reload, child: const Text('重試')),
                        ],
                      ),
                    ),
                  if (list != null && list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: Text(
                        '還沒有群組，按「＋」新增群組或用邀請加入',
                        style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                      ),
                    ),
                  if (list != null && list.isNotEmpty)
                    // 選中的底色會從舊的群組滑到新的群組
                    SlidingSelection(
                      selectedIndex: _indexOf(list, selectedId),
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      spacing: 2,
                      revealPadding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final group in list)
                          _GroupRow(
                            key: ValueKey(group.id),
                            group: group,
                            selected: group.id == selectedId,
                            onTap: () {
                              groups.select(group.id);
                              onSelected?.call();
                            },
                          ),
                      ],
                    ),
                  if (groups.invitations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel('邀請', trailing: CountBadge(count: groups.invitations.length)),
                    for (final invitation in groups.invitations) _InvitationCard(invitation: invitation),
                  ],
                ],
              ),
            ),
            Divider(height: 0.5, color: colors.line.withValues(alpha: 0.6)),
            _AccountTile(onTap: onOpenSettings),
          ],
        ),
      ),
    );
  }
}

int? _indexOf(List<GroupSummary> list, String? id) {
  final index = list.indexWhere((g) => g.id == id);
  return index < 0 ? null : index;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: context.colors.inkMuted));
    if (trailing == null) return Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 6), child: label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 2),
      child: SizedBox(
        height: 36,
        child: Row(children: [Expanded(child: label), trailing!, const SizedBox(width: 4)]),
      ),
    );
  }
}

class _GroupRow extends StatefulWidget {
  const _GroupRow({super.key, required this.group, required this.selected, required this.onTap});

  final GroupSummary group;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  bool _hovered = false;

  // 桌面在按下的位置跳出選單，手機從下面滑出面板
  void _showActions(Offset? globalPosition) {
    showGroupActions(context, widget.group, position: AppPlatform.isMobile ? null : globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = widget.group;
    final selected = widget.selected;
    // 「…」換掉驗證碼數：桌面滑過去時出現；手機（沒有滑鼠）在選中的那一列出現，也可以長按
    final showMore = AppPlatform.isMobile ? selected : _hovered;
    final icon = group.encrypted
        ? Icons.lock_rounded
        : group.isDefault
            ? Icons.person_rounded
            : Icons.people_alt_rounded;
    // 選中的底色由外層的 SlidingSelection 畫，這裡保持透明
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        // 按下去不要閃一塊底色、選中的那一列也不要 hover 底色，看到的才是選取底色滑過去
        highlightColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: selected ? Colors.transparent : colors.surface2.withValues(alpha: 0.45),
        onTap: widget.onTap,
        onHover: (hovered) => setState(() => _hovered = hovered),
        onSecondaryTapUp: (details) => _showActions(details.globalPosition),
        onLongPress: () => _showActions(null),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 10, showMore ? 4 : 10, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? colors.accent : colors.inkMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.body, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              if (group.isDefault) ...[
                const SizedBox(width: 6),
                Text('預設', style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: colors.accent)),
              ],
              const SizedBox(width: 8),
              if (!showMore) Text('${group.accountCount}', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
              if (showMore)
                Builder(
                  builder: (context) => SizedBox(
                    width: 28,
                    height: 24,
                    child: IconButton(
                      tooltip: '更多',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      // 用整列的 context：選單打開後滑鼠離開這一列，「…」會被拿掉，用它的 context 選完就沒反應
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox;
                        _showActions(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                      },
                      icon: Icon(Icons.more_horiz_rounded, color: colors.inkMuted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatefulWidget {
  const _InvitationCard({required this.invitation});

  final Invitation invitation;

  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  bool _pending = false;

  Future<void> _respond(bool accept) async {
    setState(() => _pending = true);
    final error = await context.read<GroupsController>().respond(widget.invitation, accept: accept);
    if (!mounted) return;
    setState(() => _pending = false);
    if (error != null) {
      await showErrorDialog(context, accept ? '無法加入群組' : '無法拒絕邀請', error);
    } else {
      showToast(context, accept ? '已加入「${widget.invitation.groupName}」' : '已拒絕邀請');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final invitation = widget.invitation;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(invitation.groupName, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
          Text(
            invitation.invitedBy == null ? '邀請你加入' : '${invitation.invitedBy!.displayName} 邀請你加入',
            style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _pending ? null : () => _respond(false),
                style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                child: const Text('拒絕'),
              ),
              TextButton(onPressed: _pending ? null : () => _respond(true), child: const Text('接受')),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = context.select<AuthController, Profile?>((a) => a.profile);
    if (profile == null) return const SizedBox.shrink();
    final subtitle = profile.username.isNotEmpty ? '@${profile.username}' : profile.email;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            UserAvatar(name: profile.displayName, photoUrl: profile.photoUrl, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                ],
              ),
            ),
            Tooltip(message: '設定', child: Icon(Icons.settings_rounded, color: colors.inkMuted)),
          ],
        ),
      ),
    );
  }
}

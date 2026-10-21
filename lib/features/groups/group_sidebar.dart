import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/logo.dart';
import '../auth/auth_controller.dart';
import '../auth/profile.dart';
import 'group_models.dart';
import 'groups_controller.dart';

/*
 * 側欄（桌面的左欄、手機的 Drawer）：群組清單（照 my_groups 的順序）、待回覆的邀請，最下面是帳戶。
 * 預設群組標「預設」，加密的群組有鎖頭。
 */
class GroupSidebar extends StatelessWidget {
  const GroupSidebar({super.key, required this.onOpenSettings, this.onSelected});

  final VoidCallback onOpenSettings;
  // 選了群組之後（手機要關掉 Drawer）
  final VoidCallback? onSelected;

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
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
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
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _SectionLabel('群組'),
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
                  for (final group in list ?? const <GroupSummary>[])
                    _GroupRow(
                      group: group,
                      selected: group.id == selectedId,
                      onTap: () {
                        groups.select(group.id);
                        onSelected?.call();
                      },
                    ),
                  if (groups.invitations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel('邀請'),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        child: Text(text, style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: context.colors.inkMuted)),
      );
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.selected, required this.onTap});

  final GroupSummary group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = group.encrypted
        ? Icons.lock_rounded
        : group.isDefault
            ? Icons.person_rounded
            : Icons.people_alt_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                Text('${group.accountCount}', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
              ],
            ),
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

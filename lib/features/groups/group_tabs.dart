import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/sliding_selection.dart';
import 'group_actions.dart';
import 'group_models.dart';
import 'groups_controller.dart';

/*
 * 手機（沒有左側欄時）驗證碼清單上方的群組分頁：可以左右捲動，
 * 選中的底色會滑到新的分頁，並自動捲到看得見的位置。左邊的選單鍵打開側欄（邀請、設定），有未處理的邀請時帶數字；
 * 最後的「＋」新增群組或用邀請加入，長按分頁打開管理群組、邀請成員、調整順序。
 */
class GroupTabBar extends StatelessWidget {
  const GroupTabBar({super.key, required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = context.watch<GroupsController>();
    final list = groups.groups ?? const <GroupSummary>[];
    final selectedId = groups.selectedId;
    final index = list.indexWhere((g) => g.id == selectedId);

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: MenuButtonWithBadge(onPressed: onMenu),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SlidingSelection(
                    direction: Axis.horizontal,
                    selectedIndex: index < 0 ? null : index,
                    color: colors.surface1,
                    spacing: 2,
                    // 捲過去時讓旁邊的分頁露出一點，看得出來還能捲
                    revealPadding: const EdgeInsets.symmetric(horizontal: 40),
                    children: [
                      for (final group in list)
                        _GroupTab(
                          group: group,
                          selected: group.id == selectedId,
                          onTap: () => groups.select(group.id),
                          onLongPress: () => showGroupActions(context, group),
                        ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  const AddGroupButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({required this.group, required this.selected, required this.onTap, required this.onLongPress});

  final GroupSummary group;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : SlidingSelection.duration;
    // 字重固定，只換顏色：寬度不變，底色滑動時旁邊的分頁才不會跟著動
    final color = selected ? colors.ink : colors.inkMuted;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          // 按下去不要閃一塊底色，看到的才是選取底色滑過去
          highlightColor: Colors.transparent,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: duration,
              curve: SlidingSelection.curve,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (group.encrypted) ...[
                    Icon(Icons.lock_rounded, size: 15, color: value),
                    const SizedBox(width: 5),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/lock_backdrop.dart';
import '../../../core/widgets/pill.dart';
import '../../groups/group_models.dart';
import '../../groups/groups_controller.dart';
import '../../groups/manage/group_entry.dart';
import '../../notifications/notification_inbox.dart';
import '../../settings/settings_controller.dart';
import '../../vault/vault_unlock_view.dart';
import '../codes_controller.dart';
import '../transfer/export_entry.dart';
import 'category_order_editor.dart';
import 'code_form.dart';
import 'code_row.dart';

/*
 * 中間欄：選中群組的驗證碼清單（同網站 GroupCodes）。
 * 上面是群組名稱、說明、搜尋與類別篩選；寬視窗點一筆在右欄顯示，窄螢幕開下一頁。
 * 「更多」選單：隱藏驗證碼、調整順序、調整類別順序、全部匯出、群組設定、清空全部。
 * 排序模式時收起搜尋與篩選、顯示全部，每一筆左邊有上下移。
 */
class CodeListPane extends StatefulWidget {
  const CodeListPane({super.key, required this.onOpen, this.onMenu, this.leading, this.highlightSelection = true});

  final ValueChanged<String> onOpen;
  // 窄螢幕：左上角開側欄
  final VoidCallback? onMenu;
  // 沒有 onMenu 時左上角的按鈕（桌面寬視窗收起側欄後的「顯示側邊欄」）
  final Widget? leading;
  // 寬視窗才標出選中的那一筆
  final bool highlightSelection;

  @override
  State<CodeListPane> createState() => _CodeListPaneState();
}

class _CodeListPaneState extends State<CodeListPane> {
  // 在 initState 建好：排序模式時搜尋框不會出現，用到才建的話會在 dispose 時才去讀 context
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: context.read<CodesController>().keyword);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final groups = context.read<GroupsController>();
    final codes = context.read<CodesController>();
    await Future.wait([groups.reload(), if (!codes.locked) codes.load()]);
  }

  Future<void> _move(CodesController controller, int index, int offset) async {
    final error = await controller.reorder(index, offset);
    if (error != null && mounted) await showErrorDialog(context, '排序失敗', error);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CodesController>();
    final group = context.select<GroupsController, GroupSummary?>((g) => g.selected) ?? controller.group;
    final hidden = context.select<SettingsController, bool>((s) => s.hideCodes);
    final colors = context.colors;

    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(group: group, controller: controller, onMenu: widget.onMenu, leading: widget.leading, onRefresh: _refresh),
        Expanded(child: _body(context, controller, group, hidden, colors)),
      ],
    );
    // 加密群組鎖定時整欄換成鎖定畫面的漸層底
    return controller.locked ? LockBackdrop(child: pane) : pane;
  }

  Widget _body(BuildContext context, CodesController controller, GroupSummary group, bool hidden, AppColors colors) {
    if (controller.locked) {
      return VaultUnlockView(group: group);
    }
    final accounts = controller.accounts;
    if (accounts == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final banners = <Widget>[
      if (controller.offline) _Banner(text: '沒有網路，無法同步，顯示的是上次同步的驗證碼'),
      if (controller.error != null) _Banner(text: controller.error!, alarm: true, onClose: controller.clearError),
    ];

    if (accounts.isEmpty) {
      return RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...banners,
            EmptyState(
              title: '還沒有驗證碼',
              message: !controller.canAdd
                  ? '目前沒有你能查看的驗證碼，需要時請群組管理者調整你的身分組權限'
                  : controller.solo
                      ? '到各服務的兩步驟驗證設定拿 QR Code，掃一下就加進來'
                      : '新增第一筆，群組成員就能依身分組權限看到',
              actionLabel: controller.canAdd ? '新增第一筆' : null,
              onAction: controller.canAdd ? () => showCodeForm(context, controller) : null,
            ),
          ],
        ),
      );
    }

    final filtered = controller.filtered;
    final categories = controller.categories;
    final active = controller.activeCategory;
    final sorting = controller.sorting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...banners,
              if (sorting)
                Text(
                  '用箭頭調整順序，釘選的固定排在最上面；順序對所有成員都一樣',
                  style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                )
              else
                TextField(
                  controller: _search,
                  onChanged: controller.setKeyword,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜尋',
                    prefixIcon: Icon(Icons.search_rounded, color: colors.inkMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    suffixIcon: controller.keyword.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: Icon(Icons.close_rounded, size: 18, color: colors.inkMuted),
                            onPressed: () {
                              _search.clear();
                              controller.setKeyword('');
                            },
                          ),
                  ),
                ),
            ],
          ),
        ),
        if (categories.isNotEmpty && !sorting)
          SizedBox(
            height: 44,
            // 選中的反白底色會滑到新點的類別
            child: PillBar(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              labels: ['全部', ...categories],
              selectedIndex: active == null ? 0 : categories.indexOf(active) + 1,
              onSelect: (i) {
                final name = i == 0 ? null : categories[i - 1];
                controller.setCategory(name == active ? null : name);
              },
            ),
          ),
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: _refresh,
            child: filtered.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [EmptyState(title: '沒有符合的驗證碼')],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    itemCount: filtered.length + 1,
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                          child: Text(
                            [
                              filtered.length == accounts.length ? '共 ${accounts.length} 筆' : '顯示 ${filtered.length} 筆，共 ${accounts.length} 筆',
                              if (hidden) '驗證碼已隱藏，點一下才會顯示',
                            ].join('，'),
                            style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                          ),
                        );
                      }
                      final account = filtered[index];
                      return CodeRow(
                        key: ValueKey(account.id),
                        account: account,
                        secret: controller.secretOf(account),
                        server: controller.server,
                        hidden: hidden,
                        selected: widget.highlightSelection && controller.openId == account.id,
                        onOpen: () => widget.onOpen(account.id),
                        sort: sorting
                            ? CodeRowSort(
                                canUp: canSwapAccounts(filtered, index, -1),
                                canDown: canSwapAccounts(filtered, index, 1),
                                onUp: () => _move(controller, index, -1),
                                onDown: () => _move(controller, index, 1),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, required this.controller, required this.onMenu, required this.leading, required this.onRefresh});

  final GroupSummary group;
  final CodesController controller;
  final VoidCallback? onMenu;
  final Widget? leading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsController>();
    final subtitle = [
      if (group.memberCount > 1) '${group.memberCount} 位成員',
      if (group.isDefault) '預設群組',
      if (group.encrypted) '已加密',
    ].join(' · ');
    final lead = onMenu != null
        ? IconButton(tooltip: '群組', onPressed: onMenu, icon: Icon(Icons.menu_rounded, color: colors.ink))
        : leading;

    return Padding(
      padding: EdgeInsets.fromLTRB(lead == null ? 20 : 4, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ?lead,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (group.encrypted) ...[
                          Icon(Icons.lock_rounded, size: 18, color: colors.inkMuted),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                  ],
                ),
              ),
              if (controller.sorting)
                TextButton(
                  onPressed: () => controller.setSorting(false),
                  child: const Text('完成', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
                )
              else ...[
                const NotificationBell(),
                if (controller.canAdd && !controller.locked)
                  IconButton(
                    tooltip: '新增驗證碼',
                    onPressed: () => showCodeForm(context, controller),
                    icon: Icon(Icons.add_rounded, color: colors.accent, size: 26),
                  ),
                _MoreMenu(group: group, controller: controller, settings: settings, onRefresh: onRefresh),
              ],
            ],
          ),
          if (group.description.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: lead == null ? 0 : 16, top: 6),
              child: Tooltip(
                message: group.description,
                child: Text(
                  '說明：${group.description}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ListAction { hide, sort, sortCategories, exportAll, groupSettings, refresh, clear }

// 清單的「更多」選單（同網站 GroupCodes 的「…」）：沒有權限的項目不列出，暫時不能用的變灰
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.group, required this.controller, required this.settings, required this.onRefresh});

  final GroupSummary group;
  final CodesController controller;
  final SettingsController settings;
  final Future<void> Function() onRefresh;

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: '清空所有驗證碼',
      message: controller.solo
          ? '確定要清空「${group.name}」的所有驗證碼嗎？刪除後無法恢復，所有金鑰都會遺失'
          : '確定要清空「${group.name}」裡你能管理的驗證碼嗎？所有成員都會看不到，刪除後無法恢復',
      confirmLabel: '全部清空',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final groups = context.read<GroupsController>();
    final result = await controller.clear();
    if (!context.mounted) return;
    switch (result) {
      case Ok(:final data):
        showToast(context, '已清空 $data 筆驗證碼');
        // 側欄的筆數跟著更新
        unawaited(groups.reload());
      case Err(:final message):
        await showErrorDialog(context, '清空驗證碼失敗', message);
    }
  }

  void _onSelected(BuildContext context, _ListAction action) {
    switch (action) {
      case _ListAction.hide:
        settings.setHideCodes(!settings.hideCodes);
      case _ListAction.sort:
        controller.setSorting(true);
      case _ListAction.sortCategories:
        unawaited(showCategoryOrderEditor(context, controller));
      case _ListAction.exportAll:
        unawaited(showExportAll(context, controller));
      case _ListAction.groupSettings:
        unawaited(openGroupManage(context, group.id));
      case _ListAction.refresh:
        unawaited(onRefresh());
      case _ListAction.clear:
        unawaited(_clear(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ready = !controller.locked && controller.accounts != null;
    final hasAccounts = ready && controller.accounts!.isNotEmpty;

    PopupMenuItem<_ListAction> item(_ListAction value, IconData icon, String label, {bool enabled = true, bool danger = false}) {
      final color = !enabled ? colors.inkMuted : (danger ? colors.alarm : colors.ink);
      return PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Row(children: [
          Icon(icon, size: 20, color: danger && enabled ? colors.alarm : null),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ]),
      );
    }

    return PopupMenuButton<_ListAction>(
      tooltip: '更多',
      icon: Icon(Icons.more_horiz_rounded, color: colors.ink),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        item(
          _ListAction.hide,
          settings.hideCodes ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          settings.hideCodes ? '顯示驗證碼' : '隱藏驗證碼',
        ),
        // 排序要群組層級的「管理驗證碼」，兩筆以上才能用
        if (ready && controller.canAdd) item(_ListAction.sort, Icons.swap_vert_rounded, '調整順序', enabled: controller.canSort),
        // 類別順序同樣要「管理驗證碼」，兩個以上的類別才列出
        if (ready && controller.canSortCategories) item(_ListAction.sortCategories, Icons.sort_rounded, '調整類別順序'),
        // 匯出要拿得到金鑰（有「查看金鑰」）
        if (hasAccounts) item(_ListAction.exportAll, Icons.ios_share_rounded, '全部匯出', enabled: controller.exportable.isNotEmpty),
        item(_ListAction.groupSettings, Icons.settings_rounded, '群組設定…'),
        item(_ListAction.refresh, Icons.refresh_rounded, '重新整理'),
        if (ready && controller.canClear) ...[
          const PopupMenuDivider(),
          item(_ListAction.clear, Icons.delete_sweep_rounded, '清空全部', danger: true),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.alarm = false, this.onClose});

  final String text;
  final bool alarm;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.fromLTRB(14, 10, onClose == null ? 14 : 4, 10),
      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Row(
        children: [
          Icon(alarm ? Icons.error_outline_rounded : Icons.cloud_off_rounded, size: 18, color: alarm ? colors.alarm : colors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppText.secondary, color: alarm ? colors.alarm : colors.inkMuted, fontWeight: FontWeight.w500),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: '關閉',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 18, color: colors.inkMuted),
            ),
        ],
      ),
    );
  }
}

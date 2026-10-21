import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pill.dart';
import '../../groups/group_models.dart';
import '../../groups/groups_controller.dart';
import '../../settings/settings_controller.dart';
import '../../vault/vault_unlock_view.dart';
import '../codes_controller.dart';
import 'code_form.dart';
import 'code_row.dart';

/*
 * 中間欄：選中群組的驗證碼清單（同網站 GroupCodes）。
 * 上面是群組名稱、說明、搜尋與類別篩選；寬視窗點一筆在右欄顯示，窄螢幕開下一頁。
 */
class CodeListPane extends StatefulWidget {
  const CodeListPane({super.key, required this.onOpen, this.onMenu, this.highlightSelection = true});

  final ValueChanged<String> onOpen;
  // 窄螢幕：左上角開側欄
  final VoidCallback? onMenu;
  // 寬視窗才標出選中的那一筆
  final bool highlightSelection;

  @override
  State<CodeListPane> createState() => _CodeListPaneState();
}

class _CodeListPaneState extends State<CodeListPane> {
  late final _search = TextEditingController(text: context.read<CodesController>().keyword);

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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CodesController>();
    final group = context.select<GroupsController, GroupSummary?>((g) => g.selected) ?? controller.group;
    final hidden = context.select<SettingsController, bool>((s) => s.hideCodes);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(group: group, controller: controller, onMenu: widget.onMenu, onRefresh: _refresh),
        Expanded(child: _body(context, controller, group, hidden, colors)),
      ],
    );
  }

  Widget _body(BuildContext context, CodesController controller, GroupSummary group, bool hidden, AppColors colors) {
    if (controller.locked) {
      return ListView(padding: const EdgeInsets.all(16), children: [VaultUnlockView(group: group)]);
    }
    final accounts = controller.accounts;
    if (accounts == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final banners = <Widget>[
      if (controller.offline) _Banner(text: '目前離線，顯示上次載入的驗證碼'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...banners,
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
        if (categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              children: [
                Pill(label: '全部', active: active == null, onTap: () => controller.setCategory(null)),
                for (final name in categories) ...[
                  const SizedBox(width: 6),
                  Pill(label: name, active: active == name, onTap: () => controller.setCategory(active == name ? null : name)),
                ],
              ],
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
  const _Header({required this.group, required this.controller, required this.onMenu, required this.onRefresh});

  final GroupSummary group;
  final CodesController controller;
  final VoidCallback? onMenu;
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

    return Padding(
      padding: EdgeInsets.fromLTRB(onMenu == null ? 20 : 4, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onMenu != null) IconButton(tooltip: '群組', onPressed: onMenu, icon: Icon(Icons.menu_rounded, color: colors.ink)),
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
              if (controller.canAdd && !controller.locked)
                IconButton(
                  tooltip: '新增驗證碼',
                  onPressed: () => showCodeForm(context, controller),
                  icon: Icon(Icons.add_rounded, color: colors.accent, size: 26),
                ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_horiz_rounded, color: colors.ink),
                onSelected: (value) {
                  if (value == 'hide') settings.setHideCodes(!settings.hideCodes);
                  if (value == 'refresh') onRefresh();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'hide',
                    child: Row(children: [
                      Icon(settings.hideCodes ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(settings.hideCodes ? '顯示驗證碼' : '隱藏驗證碼'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(children: [Icon(Icons.refresh_rounded, size: 20), SizedBox(width: 12), Text('重新整理')]),
                  ),
                ],
              ),
            ],
          ),
          if (group.description.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: onMenu == null ? 0 : 16, top: 6),
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

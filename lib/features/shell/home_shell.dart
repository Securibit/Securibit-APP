import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/empty_state.dart';
import '../admin/admin_entry.dart';
import '../admin/admin_page.dart';
import '../codes/codes_controller.dart';
import '../codes/codes_scope.dart';
import '../codes/widgets/code_detail.dart';
import '../codes/widgets/code_list_pane.dart';
import '../groups/group_models.dart';
import '../groups/group_sidebar.dart';
import '../groups/group_tabs.dart';
import '../groups/groups_controller.dart';
import '../settings/settings_view.dart';

/*
 * 主畫面，依視窗寬度排版（參考 Proton Pass 桌面版）：
 * - 寬（≥ 1000）：左側欄（群組、帳戶）｜中間驗證碼清單｜右邊詳細資料
 * - 中（≥ 720）：側欄收進 Drawer｜清單｜詳細資料
 * - 窄（手機）：側欄收進 Drawer，主畫面是清單，點一筆開下一頁
 * 沒有左側欄時，有兩個以上的群組就在最上面放一排可以滑動切換的群組分頁
 */
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const wideBreakpoint = 1000.0;
  static const mediumBreakpoint = 720.0;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = context.select<GroupsController, GroupSummary?>((g) => g.selected);
    final groupCount = context.select<GroupsController, int>((g) => g.groups?.length ?? 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= HomeShell.wideBreakpoint;
        final medium = !wide && width >= HomeShell.mediumBreakpoint;

        void openDrawer() => _scaffoldKey.currentState?.openDrawer();
        void closeDrawer() => _scaffoldKey.currentState?.closeDrawer();
        // 分頁列放在換群組時不會重建的地方，底色才滑得過去；選單鍵也移到分頁列
        final tabs = !wide && group != null && groupCount > 1;
        final listMenu = wide || tabs ? null : openDrawer;

        final sidebar = AdminSidebarEntry(
          onOpen: () {
            if (!wide) closeDrawer();
            openAdmin(context);
          },
          child: GroupSidebar(
            onOpenSettings: () {
              if (!wide) closeDrawer();
              openSettings(context);
            },
            onSelected: wide ? null : closeDrawer,
          ),
        );

        Widget content;
        if (group == null) {
          content = _NoGroup(onMenu: wide ? null : openDrawer);
        } else {
          final vertical = VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6));
          content = CodesScope(
            group: group,
            child: Builder(
              builder: (context) {
                final controller = context.read<CodesController>();
                if (wide || medium) {
                  return Row(
                    children: [
                      SizedBox(
                        width: wide ? ((width - 260) * 0.45).clamp(380.0, 460.0) : 380,
                        child: CodeListPane(onOpen: controller.select, onMenu: listMenu),
                      ),
                      vertical,
                      Expanded(
                        child: Selector<CodesController, String?>(
                          selector: (_, c) => c.locked ? null : c.effectiveSelectedId,
                          builder: (context, id, _) => CodeDetailView(accountId: id),
                        ),
                      ),
                    ],
                  );
                }
                return CodeListPane(
                  onMenu: listMenu,
                  highlightSelection: false,
                  onOpen: (id) {
                    controller.select(id);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider<CodesController>.value(
                        value: controller,
                        child: _DetailPage(accountId: id),
                      ),
                    ));
                  },
                );
              },
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          drawer: wide ? null : Drawer(width: 300, child: sidebar),
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 260, child: sidebar),
                    VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6)),
                    Expanded(child: SafeArea(left: false, child: content)),
                  ],
                )
              : SafeArea(
                  // 一直用 Column：分頁列出現或消失時，下面的清單不會整個重建
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tabs) GroupTabBar(onMenu: openDrawer),
                      Expanded(child: content),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: CodeDetailView(accountId: accountId, onClosed: () => Navigator.of(context).maybePop()),
    );
  }
}

// 還沒有可以顯示的群組：載入中、失敗或一個群組都沒有
class _NoGroup extends StatelessWidget {
  const _NoGroup({this.onMenu});

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsController>();
    final Widget body;
    if (groups.groups == null && groups.error == null) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (groups.error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(title: '載入群組失敗', message: groups.error, actionLabel: '重試', onAction: groups.reload),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          title: '找不到你的驗證碼',
          message: '重新整理試試看；登入時會自動建立預設群組',
          actionLabel: '重新整理',
          onAction: groups.reload,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onMenu != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 0, 0),
              child: IconButton(tooltip: '群組', onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
            ),
          ),
        Expanded(child: Align(alignment: Alignment.topCenter, child: body)),
      ],
    );
  }
}

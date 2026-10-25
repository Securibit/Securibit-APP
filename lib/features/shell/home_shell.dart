import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/feedback.dart';
import '../admin/admin_entry.dart';
import '../admin/admin_page.dart';
import '../admin/permission_defs.dart';
import '../admin/site_access.dart';
import '../auth/auth_controller.dart';
import '../codes/codes_controller.dart';
import '../codes/codes_scope.dart';
import '../codes/widgets/code_detail.dart';
import '../codes/widgets/code_list_pane.dart';
import '../groups/group_actions.dart';
import '../groups/group_models.dart';
import '../groups/group_sidebar.dart';
import '../groups/group_tabs.dart';
import '../groups/groups_controller.dart';
import '../groups/manage/group_entry.dart';
import '../links/deep_link_host.dart';
import '../notifications/notification_inbox.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_view.dart';
import 'collapsible_sidebar.dart';

/*
 * 主畫面，依視窗寬度排版（參考 Proton Pass 桌面版）：
 * - 寬（≥ 1000）：左側欄（群組、帳戶）｜中間驗證碼清單｜右邊詳細資料；桌面版的側欄可以收起來（見 CollapsibleSidebar）
 * - 中（≥ 720）：側欄收進 Drawer｜清單｜詳細資料
 * - 窄（手機）：側欄收進 Drawer，主畫面是清單，點一筆開下一頁
 * 沒有左側欄時，有兩個以上的群組（或有待回覆的邀請，選單鍵才看得到數字）就在最上面放一排可以滑動切換的群組分頁
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
  late final GroupsController _groups = context.read<GroupsController>();
  late bool _offline = _groups.offline;

  @override
  void initState() {
    super.initState();
    _groups.addListener(_onGroupsChanged);
  }

  @override
  void dispose() {
    _groups.removeListener(_onGroupsChanged);
    super.dispose();
  }

  // 斷線或連回來時提示一次（每分鐘的同步與回到前景時發現）。
  // 連回來時重新讀全站權限：離線時讀失敗的話「後台」入口會一直不見
  void _onGroupsChanged() {
    final offline = _groups.offline;
    final access = SiteAccessController.shared;
    if (!offline && (offline != _offline || !access.loaded)) unawaited(access.reload());
    if (offline == _offline) return;
    _offline = offline;
    if (!mounted) return;
    showToast(context, offline ? '沒有網路，無法同步，先顯示上次同步的資料' : '已重新連線，資料已同步');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = context.select<GroupsController, GroupSummary?>((g) => g.selected);
    final groupCount = context.select<GroupsController, int>((g) => g.groups?.length ?? 0);
    final pendingInvitations = context.select<GroupsController, int>((g) => g.pendingInvitations);
    final sidebarCollapsed = context.select<SettingsController, bool>((s) => s.sidebarCollapsed);
    // 手機的側欄收在 Drawer 裡（打開才建立），全站權限（能不能建立群組）在這裡先讀
    final uid = context.select<AuthController, String?>((a) => a.profile?.uid);
    final access = SiteAccessController.shared;
    if (uid != access.uid) scheduleMicrotask(() => access.attach(uid));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= HomeShell.wideBreakpoint;
        final medium = !wide && width >= HomeShell.mediumBreakpoint;

        void openDrawer() => _scaffoldKey.currentState?.openDrawer();
        void closeDrawer() => _scaffoldKey.currentState?.closeDrawer();
        // 分頁列放在換群組時不會重建的地方，底色才滑得過去；選單鍵也移到分頁列
        final tabs = !wide && group != null && (groupCount > 1 || pendingInvitations > 0);
        final listMenu = wide || tabs ? null : openDrawer;
        // 桌面寬視窗的側欄可以收起來；收起來時清單左上角放「顯示側邊欄」
        final collapsible = wide && AppPlatform.isDesktop;
        final showSidebarButton = collapsible && sidebarCollapsed ? SidebarToggleButton(badgeCount: pendingInvitations) : null;

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
            headerAction: collapsible ? const SidebarToggleButton() : null,
          ),
        );

        Widget content;
        if (group == null) {
          content = _NoGroup(onMenu: wide ? null : openDrawer, leading: showSidebarButton);
        } else {
          final vertical = VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6));
          content = CodesScope(
            group: group,
            // 從 otpauth 連結新增驗證碼：選好群組後在這裡打開新增表單（見 CodeLinkHost）
            child: CodeLinkHost(
              child: Builder(
                builder: (context) {
                  final controller = context.read<CodesController>();
                  if (wide || medium) {
                    // 右欄預設收起來，清單佔滿；點了一筆才從右邊往左滑進來，按關閉或刪掉那筆就往右滑回去
                    final listWidth = wide ? ((width - 260) * 0.45).clamp(380.0, 460.0) : 380.0;
                    return Selector<CodesController, String?>(
                      selector: (_, c) => c.locked ? null : c.openId,
                      builder: (context, id, _) {
                        final split = _SplitPane(
                          openId: id,
                          listWidth: listWidth,
                          divider: vertical,
                          list: CodeListPane(onOpen: controller.select, onMenu: listMenu, leading: showSidebarButton),
                          detailBuilder: (shownId) => CodeDetailView(
                            accountId: shownId,
                            onClose: () => controller.select(null),
                            onClosed: () => controller.select(null),
                          ),
                        );
                        // 一直包著同一層，打開或收起時 _SplitPane 才不會被重建（重建就沒有動畫）
                        return _EscapeToClose(enabled: id != null, onEscape: () => controller.select(null), child: split);
                      },
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
            ),
          );
        }

        final Widget body;
        if (collapsible) {
          body = CollapsibleSidebar(sidebar: sidebar, child: SafeArea(left: false, child: content));
        } else if (wide) {
          // 平板的寬版面：側欄一直顯示
          body = Row(
            children: [
              SizedBox(width: 260, child: sidebar),
              VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6)),
              Expanded(child: SafeArea(left: false, child: content)),
            ],
          );
        } else {
          body = SafeArea(
            // 一直用 Column：分頁列出現或消失時，下面的清單不會整個重建
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tabs) GroupTabBar(onMenu: openDrawer),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          drawer: wide ? null : Drawer(width: 300, child: sidebar),
          body: body,
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
  const _NoGroup({this.onMenu, this.leading});

  final VoidCallback? onMenu;
  // 沒有 onMenu 時左上角的按鈕（收起側欄後的「顯示側邊欄」）
  final Widget? leading;

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
        child: ListenableBuilder(
          listenable: SiteAccessController.shared,
          builder: (context, _) {
            final canCreate = SiteAccessController.shared.can(SitePermission.createGroups);
            return Column(
              children: [
                EmptyState(
                  title: '找不到你的驗證碼',
                  message: canCreate
                      ? '重新整理試試看；登入時會自動建立預設群組，也可以新增群組或用邀請加入別人的群組'
                      : '重新整理試試看；登入時會自動建立預設群組，也可以用邀請加入別人的群組',
                  actionLabel: '重新整理',
                  onAction: groups.reload,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (canCreate)
                      FilledButton.icon(
                        onPressed: () => openCreateGroup(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增群組'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => openJoinByInvite(context),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('用邀請加入'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 8, 0),
          child: Row(
            children: [
              if (onMenu != null) MenuButtonWithBadge(onPressed: onMenu!) else ?leading,
              const Spacer(),
              const NotificationBell(),
            ],
          ),
        ),
        Expanded(child: Align(alignment: Alignment.topCenter, child: body)),
      ],
    );
  }
}

/// 右欄打開時按 Esc 收起來；上面還疊著對話框或其他頁面時不處理，讓 Esc 先關那個
class _EscapeToClose extends StatefulWidget {
  const _EscapeToClose({required this.enabled, required this.onEscape, required this.child});

  final bool enabled;
  final VoidCallback onEscape;
  final Widget child;

  @override
  State<_EscapeToClose> createState() => _EscapeToCloseState();
}

class _EscapeToCloseState extends State<_EscapeToClose> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    widget.onEscape();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 寬視窗的清單｜右欄：右欄用固定寬度排版，從右邊滑進來時清單同步縮窄；收起時反過來
class _SplitPane extends StatefulWidget {
  const _SplitPane({
    required this.openId,
    required this.listWidth,
    required this.divider,
    required this.list,
    required this.detailBuilder,
  });

  final String? openId;
  final double listWidth;
  final Widget divider;
  final Widget list;
  final Widget Function(String id) detailBuilder;

  @override
  State<_SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<_SplitPane> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.openId != null ? 1 : 0,
  )..addStatusListener((status) {
      // 收完才把右欄拿掉，滑出去的途中還看得到原本那一筆
      if (status == AnimationStatus.dismissed && mounted) setState(() => _shownId = null);
    });
  late final Animation<double> _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  // 右欄正在顯示的那一筆；收起動畫期間 openId 已經是 null，這裡還留著
  late String? _shownId = widget.openId;

  @override
  void didUpdateWidget(covariant _SplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openId == oldWidget.openId) return;
    final instant = MediaQuery.of(context).disableAnimations;
    if (widget.openId != null) {
      _shownId = widget.openId;
      instant ? _controller.value = 1 : _controller.forward();
    } else {
      instant ? _controller.value = 0 : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final detailWidth = available - widget.listWidth;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _progress,
            child: widget.list,
            builder: (context, list) {
              final t = _progress.value;
              final listWidth = available - detailWidth * t;
              final shownId = _shownId;
              return Stack(
                children: [
                  Positioned(left: 0, top: 0, bottom: 0, width: listWidth, child: list!),
                  if (t > 0 && shownId != null)
                    Positioned(
                      left: listWidth,
                      top: 0,
                      bottom: 0,
                      width: detailWidth,
                      child: Row(
                        children: [
                          widget.divider,
                          Expanded(child: widget.detailBuilder(shownId)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../settings/settings_controller.dart';

/*
 * 桌面寬視窗（macOS、Windows、Linux）的群組側欄可以收起來，記在這台裝置（SettingsController.sidebarCollapsed）。
 * 打開時側欄上方有收起鍵，收起來時清單左上角有打開鍵；快捷鍵 macOS ⌃⌘S（同系統的「顯示／隱藏側邊欄」）、
 * Windows 與 Linux Ctrl+Shift+S。macOS 上方的「顯示方式」選單也有同一個項目（見 MenuBarService）。
 * 手機與窄視窗的側欄在 Drawer 裡，不受影響。
 */

/// 現在有沒有可以收起來的側欄（桌面寬視窗）：Mac 選單的項目沒有時變灰
class SidebarCommands {
  SidebarCommands._();

  static final available = ValueNotifier<bool>(false);

  // 換版面時新的可能比舊的先建立，用計數才不會被舊的拿掉時蓋成 false
  static int _mounted = 0;

  static void _attach() => available.value = ++_mounted > 0;

  static void _detach() => available.value = --_mounted > 0;
}

/// 快捷鍵：macOS ⌃⌘S，Windows、Linux Ctrl+Shift+S（不能多按其他修飾鍵）
bool isSidebarShortcut(KeyEvent event, {bool? mac}) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyS) return false;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isAltPressed) return false;
  if (mac ?? Platform.isMacOS) return keyboard.isControlPressed && keyboard.isMetaPressed && !keyboard.isShiftPressed;
  return keyboard.isControlPressed && keyboard.isShiftPressed && !keyboard.isMetaPressed;
}

/// 快捷鍵的顯示文字（放在按鈕的提示裡）
String sidebarShortcutLabel({bool? mac}) => (mac ?? Platform.isMacOS) ? '⌃⌘S' : 'Ctrl+Shift+S';

/// 左側欄｜分隔線｜內容；收起時側欄往左滑出去並淡出，內容跟著變寬
class CollapsibleSidebar extends StatefulWidget {
  const CollapsibleSidebar({super.key, required this.sidebar, required this.child, this.width = 260});

  final Widget sidebar;
  final Widget child;
  final double width;

  static const duration = Duration(milliseconds: 220);

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    SidebarCommands._attach();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    SidebarCommands._detach();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || !isSidebarShortcut(event)) return false;
    context.read<SettingsController>().toggleSidebar();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collapsed = context.select<SettingsController, bool>((s) => s.sidebarCollapsed);
    final instant = MediaQuery.of(context).disableAnimations;
    // 側欄加上分隔線的寬度；收起動畫期間側欄照原本的寬度排版，只是被裁掉，不會擠壓變形
    final full = widget.width + 0.5;
    final panel = Row(
      children: [
        SizedBox(width: widget.width, child: widget.sidebar),
        VerticalDivider(width: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6)),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 0 : 1),
          duration: instant ? Duration.zero : CollapsibleSidebar.duration,
          curve: Curves.easeOutCubic,
          child: panel,
          builder: (context, t, panel) => SizedBox(
            width: full * t,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: full,
                maxWidth: full,
                // 收起來後不畫、不能點、也不會被 Tab 選到，但保留捲動位置
                child: Visibility(visible: t > 0, maintainState: true, child: Opacity(opacity: t.clamp(0.0, 1.0), child: panel)),
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// 收起／打開側欄的按鈕；collapsed 時是「顯示側邊欄」，有待回覆的邀請時右上角帶數字（側欄收起來看不到）
class SidebarToggleButton extends StatelessWidget {
  const SidebarToggleButton({super.key, this.badgeCount = 0});

  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsController>();
    final collapsed = settings.sidebarCollapsed;
    final label = collapsed ? '顯示側邊欄' : '隱藏側邊欄';
    final count = collapsed ? badgeCount : 0;
    // Material 的 view_sidebar 欄位在右邊，翻過來變成左側欄
    final icon = Transform.flip(flipX: true, child: Icon(Icons.view_sidebar_outlined, size: 20, color: collapsed ? colors.ink : colors.inkMuted));
    return IconButton(
      tooltip: '$label（${sidebarShortcutLabel()}）${count > 0 ? '，$count 個邀請' : ''}',
      visualDensity: VisualDensity.compact,
      onPressed: settings.toggleSidebar,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: colors.brand,
        textColor: colors.accentInk,
        child: icon,
      ),
    );
  }
}

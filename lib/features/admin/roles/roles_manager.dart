import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../hierarchy.dart';
import '../widgets/admin_widgets.dart';
import 'role_editor.dart';

/*
 * 身分組清單（同網站 RoleEditor 的左半邊）：由高到低、@everyone 固定在最後；
 * 有「管理身分組」時可以上下移動（只能移動管得到的、不能越過管不到的）與新增。
 * split 時右邊直接顯示編輯器，否則點一列開編輯頁。
 */
class RolesManager extends StatefulWidget {
  const RolesManager({
    super.key,
    required this.roles,
    required this.config,
    required this.onCreate,
    required this.onReorder,
    required this.split,
    this.intro,
  });

  final List<Role> roles;
  final RoleEditorConfig config;
  final Future<Result<String>> Function(RoleInput input) onCreate;
  // 由高到低的完整順序（不含 @everyone）
  final Future<Result<void>> Function(List<String> roleIds) onReorder;
  final bool split;
  // 清單上方的說明
  final Widget? intro;

  @override
  State<RolesManager> createState() => _RolesManagerState();
}

class _RolesManagerState extends State<RolesManager> {
  String? _selectedId;
  List<String>? _orderOverride;
  bool _creating = false;
  bool _editorDirty = false;

  RoleEditorConfig get _config => widget.config;

  // 排序中先用新的順序顯示（重新載入完才換回外層傳進來的資料）
  List<Role> get _ordered {
    final list = sortRoles(widget.roles).where((r) => !r.isDefault).toList();
    final order = _orderOverride;
    if (order == null) return list;
    int index(Role role) {
      final i = order.indexOf(role.id);
      return i == -1 ? order.length : i;
    }

    list.sort((a, b) => index(a) - index(b));
    return list;
  }

  Role? get _everyone => widget.roles.where((r) => r.isDefault).firstOrNull;

  List<Role> get _list => [..._ordered, ?_everyone];

  Role? get _selected {
    final list = _list;
    return list.where((r) => r.id == _selectedId).firstOrNull ?? list.firstOrNull;
  }

  Future<bool> _confirmDiscard() async {
    if (!_editorDirty) return true;
    final discard = await confirmDialog(
      context,
      title: '放棄未儲存的變更',
      message: '這個身分組還有沒儲存的變更，離開後會遺失',
      confirmLabel: '放棄變更',
      danger: true,
    );
    if (discard) _editorDirty = false;
    return discard;
  }

  Future<void> _open(Role role) async {
    if (widget.split) {
      if (role.id == _selected?.id) return;
      if (!await _confirmDiscard() || !mounted) return;
      setState(() => _selectedId = role.id);
      return;
    }
    await pushAdminPage<void>(
      context,
      _RoleEditorPage(roleId: role.id, initial: role, config: _config, rolesOf: () => widget.roles),
    );
  }

  Future<void> _create() async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _creating = true);
    final result = await widget.onCreate(const RoleInput(name: '新身分組', color: '', permissions: 0));
    if (!mounted) return;
    switch (result) {
      case Err(:final message):
        setState(() => _creating = false);
        await showErrorDialog(context, '建立身分組失敗', message);
      case Ok(data: final id):
        final roles = await _config.onChanged();
        if (!mounted) return;
        setState(() {
          _creating = false;
          _selectedId = id;
        });
        showToast(context, '已建立身分組');
        final created = roles?.where((r) => r.id == id).firstOrNull;
        if (!widget.split && created != null) await _open(created);
    }
  }

  Future<void> _move(int index, int offset) async {
    final ordered = _ordered;
    if (_orderOverride != null || !canMoveRole(_config.actor, ordered, index, offset)) return;
    final next = moveRole(ordered, index, offset);
    // 先換畫面，失敗再重新載入還原
    setState(() => _orderOverride = next);
    final result = await widget.onReorder(next);
    if (!mounted) return;
    if (result case Err(:final message)) await showErrorDialog(context, '調整順序失敗', message);
    await _config.onChanged();
    if (!mounted) return;
    setState(() => _orderOverride = null);
  }

  @override
  Widget build(BuildContext context) {
    final list = _listCard(context);
    if (!widget.split) return list;
    final selected = _selected;
    final line = Theme.of(context).dividerTheme.color;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [list]),
        ),
        VerticalDivider(width: 0.5, thickness: 0.5, color: line),
        Expanded(
          child: selected == null
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: ListEmpty('還沒有任何身分組')))
              : RoleEditorView(
                  key: ValueKey(selected.id),
                  role: selected,
                  config: _config,
                  onDirtyChanged: (dirty) => _editorDirty = dirty,
                  onDeleted: () => setState(() => _selectedId = null),
                ),
        ),
      ],
    );
  }

  Widget _listCard(BuildContext context) {
    final colors = context.colors;
    final ordered = _ordered;
    final list = _list;
    final selectedId = widget.split ? _selected?.id : null;
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      final role = list[i];
      final index = ordered.indexOf(role);
      if (i > 0) rows.add(Divider(indent: 38, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(_RoleRow(
        role: role,
        selected: role.id == selectedId,
        showMove: _config.canManage && !role.isDefault,
        canUp: _orderOverride == null && canMoveRole(_config.actor, ordered, index, -1),
        canDown: _orderOverride == null && canMoveRole(_config.actor, ordered, index, 1),
        onTap: () => _open(role),
        onUp: () => _move(index, -1),
        onDown: () => _move(index, 1),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.intro,
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
        ),
        if (_config.canManage)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _creating ? null : _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(_creating ? '建立中' : '新增身分組'),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.role,
    required this.selected,
    required this.showMove,
    required this.canUp,
    required this.canDown,
    required this.onTap,
    required this.onUp,
    required this.onDown,
  });

  final Role role;
  final bool selected;
  final bool showMove;
  final bool canUp;
  final bool canDown;
  final VoidCallback onTap;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, showMove ? 4 : 12, 4),
            child: Row(
              children: [
                _dot(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    role.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppText.body, fontWeight: selected ? FontWeight.w700 : FontWeight.w600),
                  ),
                ),
                Text(
                  '${role.memberCount}',
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    color: colors.inkMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (showMove) ...[
                  const SizedBox(width: 4),
                  _MoveButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: '往上移', onPressed: canUp ? onUp : null),
                  _MoveButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: '往下移', onPressed: canDown ? onDown : null),
                ] else
                  Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(BuildContext context) => RoleDot(color: role.color, size: 10);
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: Icon(icon),
      );
}

// 整頁的身分組編輯（窄螢幕）：外層重新載入後從 rolesOf 拿最新的值
class _RoleEditorPage extends StatefulWidget {
  const _RoleEditorPage({required this.roleId, required this.initial, required this.config, required this.rolesOf});

  final String roleId;
  final Role initial;
  final RoleEditorConfig config;
  final List<Role> Function() rolesOf;

  @override
  State<_RoleEditorPage> createState() => _RoleEditorPageState();
}

class _RoleEditorPageState extends State<_RoleEditorPage> {
  late Role _role = widget.initial;

  // 儲存後重新載入，換成最新的資料（人數、權限）
  late final RoleEditorConfig _config = RoleEditorConfig(
    definitions: widget.config.definitions,
    actor: widget.config.actor,
    actorPermissions: widget.config.actorPermissions,
    canManage: widget.config.canManage,
    onUpdate: widget.config.onUpdate,
    onDelete: widget.config.onDelete,
    onChanged: () async {
      final roles = await widget.config.onChanged();
      final latest = (roles ?? widget.rolesOf()).where((r) => r.id == widget.roleId).firstOrNull;
      if (mounted && latest != null) setState(() => _role = latest);
      return roles;
    },
  );

  @override
  Widget build(BuildContext context) => RoleEditorView(
        role: _role,
        config: _config,
        guardPop: true,
        onDeleted: () => Navigator.of(context).maybePop(),
      );
}

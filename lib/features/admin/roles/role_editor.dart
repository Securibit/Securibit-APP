import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../hierarchy.dart';
import '../permission_defs.dart';
import '../widgets/admin_widgets.dart';

// 預設色票（存小寫 #rrggbb），幣友品牌色排第一（同網站 RoleEditor）
const rolePresetColors = [
  '#17ffac',
  '#ef4444',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#14b8a6',
  '#28c8c7',
  '#3b82f6',
  '#6366f1',
  '#a855f7',
  '#ec4899',
  '#64748b',
];

/// 身分組編輯需要的資料與動作（全站與群組共用）
class RoleEditorConfig {
  const RoleEditorConfig({
    required this.definitions,
    required this.actor,
    required this.actorPermissions,
    required this.canManage,
    required this.onUpdate,
    required this.onDelete,
    required this.onChanged,
  });

  final List<PermissionDef> definitions;
  final Actor actor;
  // 自己已展開的權限：只能開啟自己也有的
  final int actorPermissions;
  // 有「管理身分組」
  final bool canManage;
  final Future<Result<void>> Function(String roleId, RoleInput input) onUpdate;
  final Future<Result<void>> Function(String roleId) onDelete;
  // 修改後重新載入，回傳最新的身分組（失敗為 null）
  final Future<List<Role>?> Function() onChanged;
}

/*
 * 編輯一個身分組：名稱、顏色、權限；修改先存在草稿，按「儲存」才送出（同網站 RoleEditor 的右半邊）。
 * 唯讀時（沒有權限、或身分組不低於自己）所有欄位停用並說明原因。
 */
class RoleEditorView extends StatefulWidget {
  const RoleEditorView({
    super.key,
    required this.role,
    required this.config,
    required this.onDeleted,
    this.onDirtyChanged,
    this.guardPop = false,
  });

  final Role role;
  final RoleEditorConfig config;
  final VoidCallback onDeleted;
  final ValueChanged<bool>? onDirtyChanged;
  // 整頁開啟時：有未儲存變更要先確認才能返回
  final bool guardPop;

  @override
  State<RoleEditorView> createState() => _RoleEditorViewState();
}

class _RoleEditorViewState extends State<RoleEditorView> {
  late RoleInput _base = widget.role.input;
  late RoleInput _value = _base;
  late final _name = TextEditingController(text: _base.name);
  bool _saving = false;

  RoleEditorConfig get _config => widget.config;
  bool get _dirty => !_base.sameAs(_value);
  bool get _readOnly => !_config.canManage || !canManageRole(_config.actor, widget.role);

  String? get _readOnlyReason {
    if (!_config.canManage) return '你沒有「管理身分組」權限，只能查看';
    if (!canManageRole(_config.actor, widget.role)) return '這個身分組不低於你的最高身分組，無法編輯';
    return null;
  }

  @override
  void didUpdateWidget(RoleEditorView old) {
    super.didUpdateWidget(old);
    // 外層重新載入：沒有草稿時換成最新的值
    if (!_dirty && !old.role.input.sameAs(widget.role.input)) {
      _base = widget.role.input;
      _value = _base;
      _name.text = _base.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _patch(RoleInput next) {
    if (_readOnly) return;
    final wasDirty = _dirty;
    setState(() => _value = next);
    if (wasDirty != _dirty) widget.onDirtyChanged?.call(_dirty);
  }

  void _reset() {
    setState(() {
      _value = _base;
      _name.text = _base.name;
    });
    widget.onDirtyChanged?.call(false);
  }

  Future<void> _save() async {
    final name = _value.name.trim();
    if (name.isEmpty) {
      await showErrorDialog(context, '無法儲存', '身分組名稱不能是空的');
      return;
    }
    final input = _value.copyWith(name: name);
    setState(() => _saving = true);
    final result = await _config.onUpdate(widget.role.id, input);
    if (!mounted) return;
    if (result case Err(:final message)) {
      setState(() => _saving = false);
      await showErrorDialog(context, '儲存身分組失敗', message);
      return;
    }
    await _config.onChanged();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _base = input;
      _value = input;
      _name.text = input.name;
    });
    widget.onDirtyChanged?.call(false);
    showToast(context, '已儲存');
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '刪除身分組',
      message: '確定要刪除「${widget.role.name}」嗎？擁有這個身分組的人會失去它的權限，刪除後無法恢復',
      confirmLabel: '刪除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final result = await _config.onDelete(widget.role.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '刪除身分組失敗', message);
      return;
    }
    setState(() => _value = _base);
    widget.onDirtyChanged?.call(false);
    showToast(context, '已刪除身分組');
    await _config.onChanged();
    if (!mounted) return;
    widget.onDeleted();
  }

  Future<void> _pickCustomColor() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CustomColorDialog(initial: _value.color),
    );
    if (picked != null && mounted) _patch(_value.copyWith(color: picked));
  }

  Future<void> _handlePop(bool didPop, Object? _) async {
    if (didPop) return;
    final discard = await confirmDialog(
      context,
      title: '放棄未儲存的變更',
      message: '這個身分組還有沒儲存的變更，離開後會遺失',
      confirmLabel: '放棄變更',
      danger: true,
    );
    if (discard && mounted) {
      _reset();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final role = widget.role;
    final defs = _config.definitions;
    final adminDef = defs.where((d) => d.bit == adminBit).firstOrNull;
    final others = defs.where((d) => d.bit != adminBit).toList();
    final adminOn = (_value.permissions & adminBit) != 0;
    final enabled = adminOn ? defs.length : countBits(_value.permissions, defs);
    final reason = _readOnlyReason;
    final disabled = _readOnly || _saving;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailTitle(
                  title: role.name,
                  subtitle: role.isDefault ? '每個人都有的身分組・${role.memberCount} 人' : '${role.memberCount} 人',
                ),
                if (reason != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, size: 16, color: colors.inkMuted),
                        const SizedBox(width: 6),
                        Expanded(child: MutedText(reason)),
                      ],
                    ),
                  ),
                const FieldLabel('名稱'),
                TextField(
                  controller: _name,
                  enabled: !role.isDefault && !disabled,
                  maxLength: 50,
                  onChanged: (text) => _patch(_value.copyWith(name: text)),
                  decoration: InputDecoration(
                    counterText: '',
                    helperText: role.isDefault ? '@everyone 是所有人都有的身分組，不能改名' : null,
                  ),
                ),
                const SizedBox(height: 24),
                if (!role.isDefault) ...[
                  const SectionHeader('顏色'),
                  SoftCard(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ColorDot(
                          tooltip: '無顏色',
                          selected: _value.color.isEmpty,
                          onTap: disabled ? null : () => _patch(_value.copyWith(color: '')),
                          child: Icon(Icons.block_rounded, size: 18, color: colors.inkMuted),
                        ),
                        for (final preset in rolePresetColors)
                          _ColorDot(
                            tooltip: preset,
                            color: Color(parseRoleColor(preset)!),
                            selected: _value.color.toLowerCase() == preset,
                            onTap: disabled ? null : () => _patch(_value.copyWith(color: preset)),
                          ),
                        _ColorDot(
                          tooltip: '自訂顏色',
                          selected: _value.color.isNotEmpty && !rolePresetColors.contains(_value.color.toLowerCase()),
                          color: _value.color.isNotEmpty && !rolePresetColors.contains(_value.color.toLowerCase())
                              ? Color(parseRoleColor(_value.color) ?? 0xFF6E6E73)
                              : null,
                          onTap: disabled ? null : _pickCustomColor,
                          child: Icon(Icons.palette_rounded, size: 18, color: colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                SectionHeader(
                  '權限',
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '已開啟 $enabled / ${defs.length}',
                      style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  child: ColoredBox(
                    color: colors.surface1,
                    child: Column(
                      children: [
                        for (final (i, def) in [?adminDef, ...others].indexed) ...[
                          if (i > 0) Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)),
                          _permissionRow(def, adminOn, disabled),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_config.canManage && !role.isDefault && !_readOnly) ...[
                  const SizedBox(height: 28),
                  DangerButton(label: '刪除身分組', onPressed: _saving ? null : _delete),
                  const FootNote('擁有這個身分組的人會失去它的權限，刪除後無法恢復'),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    final content = Column(
      children: [
        Expanded(child: body),
        if (_dirty) _UnsavedBar(saving: _saving, onReset: _reset, onSave: _save),
      ],
    );

    if (!widget.guardPop) return content;
    return PopScope(canPop: !_dirty, onPopInvokedWithResult: _handlePop, child: content);
  }

  Widget _permissionRow(PermissionDef def, bool adminOn, bool disabled) {
    final colors = context.colors;
    final isAdminRow = def.bit == adminBit;
    // ADMINISTRATOR 開啟時其他列顯示為開啟並鎖住，但草稿保留原本的勾選值
    final lockedByAdmin = !isAdminRow && adminOn;
    final selected = lockedByAdmin || (_value.permissions & def.bit) != 0;
    final actorIsAdmin = (_config.actorPermissions & adminBit) != 0;
    final missing = !actorIsAdmin && (_config.actorPermissions & def.bit) == 0;
    final adminName = _config.definitions.where((d) => d.bit == adminBit).firstOrNull?.name ?? '管理員';
    final hint = _readOnly
        ? null
        : missing
            ? '你沒有這個權限，無法給別人'
            : lockedByAdmin
                ? '已包含在「$adminName」裡'
                : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(def.name, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600))),
                    if (isAdminRow) ...[
                      const SizedBox(width: 8),
                      Text('最高權限', style: TextStyle(fontSize: AppText.caption, color: colors.alarm, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(def.description, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 12, color: colors.inkMuted),
                      const SizedBox(width: 4),
                      Flexible(child: Text(hint, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: selected,
            onChanged: disabled || missing || lockedByAdmin
                ? null
                : (on) => _patch(_value.copyWith(permissions: toggleBit(_value.permissions, def.bit, on))),
          ),
        ],
      ),
    );
  }
}

// 圓形色點：選中的外圈一圈綠
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.tooltip, required this.selected, required this.onTap, this.color, this.child});

  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = color;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? colors.accent : Colors.transparent, width: 2.5),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill ?? colors.surface,
                border: fill == null ? Border.all(color: colors.line) : null,
              ),
              alignment: Alignment.center,
              child: selected && fill != null
                  ? Icon(Icons.check_rounded, size: 18, color: fill.computeLuminance() > 0.5 ? colors.accentInk : Colors.white)
                  : (fill == null ? child : null),
            ),
          ),
        ),
      ),
    );
  }
}

// 自訂顏色：輸入 #rrggbb，旁邊即時預覽
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});

  final String initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late final _controller = TextEditingController(text: widget.initial.isEmpty ? '#' : widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final color = normalizeRoleColor(_controller.text);
    if (color == null) {
      setState(() => _error = '請輸入 6 位十六進位色碼，例如 #17FFAC');
      return;
    }
    Navigator.of(context).pop(color);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = normalizeRoleColor(_controller.text);
    return AlertDialog(
      title: const Text('自訂顏色'),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: preview == null ? colors.surface1 : Color(parseRoleColor(preview)!),
                border: Border.all(color: colors.line),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(hintText: '#17FFAC', errorText: _error),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('套用')),
      ],
    );
  }
}

// 未儲存變更列（同網站：有未儲存的變更｜重設｜儲存）
class _UnsavedBar extends StatelessWidget {
  const _UnsavedBar({required this.saving, required this.onReset, required this.onSave});

  final bool saving;
  final VoidCallback onReset;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: colors.line.withValues(alpha: 0.7), width: 0.5),
        ),
        child: Row(
          children: [
            const Expanded(child: Text('有未儲存的變更', style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: saving ? null : onReset,
              style: TextButton.styleFrom(foregroundColor: colors.ink),
              child: const Text('重設'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: saving ? null : onSave,
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }
}

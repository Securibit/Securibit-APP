import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_models.dart';
import '../hierarchy.dart';
import '../widgets/admin_widgets.dart';

/*
 * 指派身分組（同網站 RoleAssignModal）：列出 @everyone 以外的身分組（由高到低），送出完整的新清單。
 * 管不到的（不低於自己）與權限超過自己的（還沒有的）鎖住；鎖住但原本就有的會一起送出。
 * 成功時以 true 關閉。
 */
class RoleAssignForm extends StatefulWidget {
  const RoleAssignForm({
    super.key,
    required this.title,
    required this.roles,
    required this.selected,
    required this.actor,
    required this.actorPermissions,
    required this.onSave,
  });

  final String title;
  final List<Role> roles;
  final List<String> selected;
  final Actor actor;
  final int actorPermissions;
  final Future<Result<void>> Function(List<String> roleIds) onSave;

  @override
  State<RoleAssignForm> createState() => _RoleAssignFormState();
}

class _RoleAssignFormState extends State<RoleAssignForm> {
  late final List<String> _checked = [...widget.selected];
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await widget.onSave([..._checked]);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '指派身分組失敗', message);
      return;
    }
    showToast(context, '已更新身分組');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // @everyone 每個人本來就有，不能指派
    final roles = sortRoles(widget.roles).where((r) => !r.isDefault).toList();
    final rows = <Widget>[];
    for (var i = 0; i < roles.length; i++) {
      final role = roles[i];
      final manageable = canManageRole(widget.actor, role);
      // 還沒有的身分組：權限超過自己的不能加（原本就有的可以照常移除）
      final tooStrong = !widget.selected.contains(role.id) && !canGrantRole(widget.actorPermissions, role);
      final disabled = !manageable || tooStrong || _saving;
      final checked = _checked.contains(role.id);
      if (i > 0) rows.add(Divider(indent: 52, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(InkWell(
        onTap: disabled ? null : () => setState(() => checked ? _checked.remove(role.id) : _checked.add(role.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: disabled ? null : (on) => setState(() => on == true ? _checked.add(role.id) : _checked.remove(role.id)),
              ),
              RoleDot(color: role.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  role.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: disabled && !_saving ? colors.inkMuted : colors.ink),
                ),
              ),
              if (!manageable)
                Text('比你的身分組高', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted))
              else if (tooStrong)
                Text('權限超過你', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
            ],
          ),
        ),
      ));
    }

    return AdminFormScaffold(
      title: widget.title,
      saving: _saving,
      onSubmit: _save,
      children: [
        if (roles.isEmpty)
          const ListEmpty('還沒有任何身分組')
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
          ),
      ],
    );
  }
}

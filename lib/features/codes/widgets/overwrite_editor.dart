import 'package:flutter/material.dart';

import '../../../core/permissions.dart';
import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/sliding_selection.dart';
import '../../admin/admin_models.dart';
import '../../admin/hierarchy.dart';
import '../../admin/permission_defs.dart';
import '../../admin/site_access.dart';
import '../../admin/widgets/admin_widgets.dart';
import '../code_models.dart';
import '../codes_controller.dart';
import '../codes_repository.dart' as repo;

/*
 * 單筆驗證碼的權限覆寫（同網站 src/components/permissions/OverwriteEditor.tsx）。
 * 左邊是覆寫的對象（@everyone → 身分組 → 成員，後面的優先），右邊是每個權限的「允許／繼承／拒絕」。
 * 每次點擊直接寫入，沒有「儲存」按鈕；關掉後清單重新讀取（有變更才讀，讀金鑰會記一筆紀錄）。
 * 只有「查看驗證碼」「查看金鑰」「管理驗證碼」可以覆寫（資料庫的 group_set_overwrite 只收 2、4、8）。
 */

/// 打開權限設定：寬視窗用對話框，窄螢幕用整頁
Future<void> showOverwriteEditor(BuildContext context, CodesController controller, GroupAccount account) async {
  var changed = false;
  final editor = OverwriteEditor(controller: controller, account: account, onChanged: () => changed = true);
  if (MediaQuery.sizeOf(context).width >= 720) {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720), child: editor),
      ),
    );
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => editor));
  }
  // 覆寫可能改變我能不能看金鑰，清單和金鑰一起重讀
  if (changed) await controller.load();
}

// ---------- 規則（純函式，見 test/overwrite_test.dart） ----------

/// 一個權限在某個對象上的設定
enum OverwriteState {
  allow('允許'),
  inherit('繼承'),
  deny('拒絕');

  const OverwriteState(this.label);

  final String label;
}

/// 可以對單筆驗證碼覆寫的權限位元（同網站 GROUP_OVERWRITABLE）
const overwritableBits = GroupPermission.viewCodes | GroupPermission.viewSecrets | GroupPermission.manageCodes;

/// 可以覆寫的權限（依位元由小到大：查看驗證碼、查看金鑰、管理驗證碼）
final overwritePermissionDefs = groupPermissionDefs.where((def) => def.bit & overwritableBits != 0).toList();

/// 覆寫的對象
@immutable
class OverwriteTarget {
  const OverwriteTarget(this.type, this.id);

  final repo.OverwriteTargetType type;
  final String id;

  @override
  bool operator ==(Object other) => other is OverwriteTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

OverwriteTarget targetOf(repo.Overwrite overwrite) => OverwriteTarget(overwrite.targetType, overwrite.targetId);

/// 某個對象的某個權限現在是允許、繼承還是拒絕（拒絕優先）
OverwriteState overwriteState(repo.Overwrite? overwrite, int bit) {
  if (overwrite == null) return OverwriteState.inherit;
  if (overwrite.deny & bit != 0) return OverwriteState.deny;
  if (overwrite.allow & bit != 0) return OverwriteState.allow;
  return OverwriteState.inherit;
}

/// 把一個權限改成 state 後的 allow、deny（兩邊不會同時有同一個位元）
({int allow, int deny}) applyOverwriteState({required int allow, required int deny, required int bit, required OverwriteState state}) => (
      allow: state == OverwriteState.allow ? allow | bit : allow & ~bit,
      deny: state == OverwriteState.deny ? deny | bit : deny & ~bit,
    );

/// 這個對象有幾個權限不是「繼承」
int overwriteCount(repo.Overwrite? overwrite) =>
    overwritePermissionDefs.where((def) => overwriteState(overwrite, def.bit) != OverwriteState.inherit).length;

/// 左邊列出的對象：@everyone 一定在最前面，再來是有設定（或剛加進來）的身分組（由高到低）與成員
List<OverwriteTarget> overwriteTargets({
  required List<Role> roles,
  required List<GroupMember> members,
  required List<repo.Overwrite> overwrites,
  required List<OverwriteTarget> added,
}) {
  final shown = {...overwrites.map(targetOf), ...added};
  final everyone = roles.where((role) => role.isDefault).firstOrNull;
  return [
    if (everyone != null) OverwriteTarget(repo.OverwriteTargetType.role, everyone.id),
    for (final role in sortRoles(roles))
      if (!role.isDefault && shown.contains(OverwriteTarget(repo.OverwriteTargetType.role, role.id)))
        OverwriteTarget(repo.OverwriteTargetType.role, role.id),
    for (final member in members)
      if (shown.contains(OverwriteTarget(repo.OverwriteTargetType.member, member.id)))
        OverwriteTarget(repo.OverwriteTargetType.member, member.id),
  ];
}

/// 管得到才能改：@everyone 一律可以；身分組、成員要比自己最高的身分組低（擁有者、全站管理不受限）
bool canEditOverwriteTarget(Actor actor, OverwriteTarget target, {required List<Role> roles, required List<GroupMember> members}) {
  if (actor.unrestricted) return true;
  if (target.type == repo.OverwriteTargetType.role) {
    final role = roles.where((r) => r.id == target.id).firstOrNull;
    return role != null && (role.isDefault || role.position < actor.topPosition);
  }
  final member = members.where((m) => m.id == target.id).firstOrNull;
  return member != null && member.topPosition < actor.topPosition;
}

/// 自己在這筆驗證碼沒有的權限不能變更（允許、拒絕都一樣；擁有者、全站管理例外）
bool canChangeOverwriteBit(Actor actor, int accountPermissions, int bit) => actor.unrestricted || accountPermissions & bit != 0;

/// 還能加進來的身分組（不含 @everyone、不含已列出的，由高到低）
List<Role> addableRoles(List<Role> roles, List<OverwriteTarget> shown) => sortRoles(roles)
    .where((role) => !role.isDefault && !shown.contains(OverwriteTarget(repo.OverwriteTargetType.role, role.id)))
    .toList();

/// 還能加進來的成員（擁有者不受覆寫影響，不列出）
List<GroupMember> addableMembers(List<GroupMember> members, List<OverwriteTarget> shown) => members
    .where((member) => !member.isOwner && !shown.contains(OverwriteTarget(repo.OverwriteTargetType.member, member.id)))
    .toList();

// ---------- 畫面 ----------

class OverwriteEditor extends StatefulWidget {
  const OverwriteEditor({super.key, required this.controller, required this.account, required this.onChanged});

  final CodesController controller;
  final GroupAccount account;
  // 寫入成功一次就呼叫（關掉後要重新讀取清單）
  final VoidCallback onChanged;

  @override
  State<OverwriteEditor> createState() => _OverwriteEditorState();
}

class _OverwriteEditorState extends State<OverwriteEditor> {
  AdminGroupDetail? _detail;
  List<repo.Overwrite>? _overwrites;
  String? _error;
  // 剛從選單加進來、還沒設定任何權限的對象（第一次點按鈕後才會寫進資料庫）
  List<OverwriteTarget> _added = const [];
  OverwriteTarget? _selected;
  bool _saving = false;

  GroupAccount get _account => widget.account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final results = await Future.wait([
      repo.loadGroupDetail(widget.controller.group.id),
      repo.loadOverwrites(_account.id),
    ]);
    if (!mounted) return;
    final detail = results[0] as Result<AdminGroupDetail>;
    final overwrites = results[1] as Result<List<repo.Overwrite>>;
    setState(() {
      switch ((detail, overwrites)) {
        case (Ok(data: final d), Ok(data: final o)):
          _detail = d;
          _overwrites = o;
        case (Err(:final message), _) || (_, Err(:final message)):
          _error = message;
      }
    });
  }

  Future<void> _reloadOverwrites() async {
    final result = await repo.loadOverwrites(_account.id);
    if (!mounted) return;
    if (result case Ok(:final data)) setState(() => _overwrites = data);
  }

  Actor _actor(AdminGroupDetail detail) {
    final access = SiteAccessController.shared;
    // 擁有者、全站管理員 / 管理所有群組：不受階層限制
    return Actor(
      unrestricted: detail.isOwner || access.can(SitePermission.administrator) || access.can(SitePermission.manageGroups),
      topPosition: detail.topPosition,
    );
  }

  repo.Overwrite? _find(OverwriteTarget target) => _overwrites?.where((o) => targetOf(o) == target).firstOrNull;

  Future<void> _set(OverwriteTarget target, int bit, OverwriteState state) async {
    final list = _overwrites;
    if (list == null || _saving) return;
    final old = _find(target) ?? repo.Overwrite(targetType: target.type, targetId: target.id, allow: 0, deny: 0);
    final next = applyOverwriteState(allow: old.allow, deny: old.deny, bit: bit, state: state);
    if (next.allow == old.allow && next.deny == old.deny) return;

    // 先換畫面，失敗再重新載入；全部改回繼承時資料庫會刪掉這筆，但左邊先保留，方便繼續設定
    final others = list.where((o) => targetOf(o) != target).toList();
    setState(() {
      _overwrites = next.allow == 0 && next.deny == 0 ? others : [...others, old.copyWith(allow: next.allow, deny: next.deny)];
      if (!_added.contains(target)) _added = [..._added, target];
      _saving = true;
    });

    final result = await repo.setOverwrite(_account.id, target.type, target.id, allow: next.allow, deny: next.deny);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '變更權限失敗', message);
      await _reloadOverwrites();
      return;
    }
    widget.onChanged();
  }

  Future<void> _pickTarget(AdminGroupDetail detail, Actor actor, List<OverwriteTarget> shown) async {
    final picked = await showDialog<OverwriteTarget>(
      context: context,
      builder: (context) => _TargetPicker(
        roles: addableRoles(detail.roles, shown),
        members: addableMembers(detail.members, shown),
        canEdit: (target) => canEditOverwriteTarget(actor, target, roles: detail.roles, members: detail.members),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _added = [..._added, picked];
      _selected = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('權限設定', style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final colors = context.colors;
    final detail = _detail;
    final overwrites = _overwrites;
    final intro = Text(
      '只影響「${_account.name}」這一筆驗證碼，會蓋過身分組本身的權限。順序：@everyone → 身分組 → 成員，後面的優先',
      style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
    );

    if (detail == null || overwrites == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          intro,
          const SizedBox(height: 24),
          if (_error == null)
            const Center(child: CircularProgressIndicator.adaptive())
          else ...[
            Text('載入權限設定失敗：$_error', style: TextStyle(fontSize: AppText.body, color: colors.alarm)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _load, child: const Text('重試'))),
          ],
        ],
      );
    }

    final actor = _actor(detail);
    final targets = overwriteTargets(roles: detail.roles, members: detail.members, overwrites: overwrites, added: _added);
    final current = targets.contains(_selected) ? _selected : targets.firstOrNull;
    final canAddTarget = addableRoles(detail.roles, targets).isNotEmpty || addableMembers(detail.members, targets).isNotEmpty;

    final targetList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canAddTarget ? () => _pickTarget(detail, actor, targets) : null,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('新增身分組或成員'),
          ),
        ),
        const SizedBox(height: 4),
        for (final target in targets)
          _TargetTile(
            label: _TargetLabel(target: target, detail: detail),
            count: overwriteCount(_find(target)),
            selected: target == current,
            onTap: () => setState(() => _selected = target),
          ),
      ],
    );

    final permissions = current == null
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
            child: Text('找不到 @everyone 身分組', textAlign: TextAlign.center, style: TextStyle(color: colors.inkMuted)),
          )
        : _PermissionPanel(
            key: ValueKey(current),
            overwrite: _find(current),
            editable: canEditOverwriteTarget(actor, current, roles: detail.roles, members: detail.members),
            canChange: (bit) => canChangeOverwriteBit(actor, _account.permissions, bit),
            saving: _saving,
            onSet: (bit, state) => _set(current, bit, state),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 寬的時候左右兩欄，窄的時候對象在上、權限在下
        if (constraints.maxWidth >= 600) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              intro,
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 230, child: targetList),
                  const SizedBox(width: 24),
                  Expanded(child: permissions),
                ],
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: intro),
            const SizedBox(height: 16),
            targetList,
            const SizedBox(height: 20),
            permissions,
          ],
        );
      },
    );
  }
}

// 對象的名稱：身分組是色點 + 名稱，成員是頭像 + 名稱
class _TargetLabel extends StatelessWidget {
  const _TargetLabel({required this.target, required this.detail});

  final OverwriteTarget target;
  final AdminGroupDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (target.type == repo.OverwriteTargetType.member) {
      final member = detail.members.where((m) => m.id == target.id).firstOrNull;
      return PersonChip(person: member?.person, size: 28);
    }
    final role = detail.roles.where((r) => r.id == target.id).firstOrNull;
    return Row(
      children: [
        RoleDot(color: role?.color ?? ''),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            role?.name ?? '已刪除的身分組',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: role == null ? colors.inkMuted : colors.ink),
          ),
        ),
      ],
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.label, required this.count, required this.selected, required this.onTap});

  final Widget label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.surface1 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(child: label),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Text('$count', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 右邊：每個可以覆寫的權限一列，右邊是「允許／繼承／拒絕」
class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    super.key,
    required this.overwrite,
    required this.editable,
    required this.canChange,
    required this.saving,
    required this.onSet,
  });

  final repo.Overwrite? overwrite;
  final bool editable;
  final bool Function(int bit) canChange;
  final bool saving;
  final void Function(int bit, OverwriteState state) onSet;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (final def in overwritePermissionDefs) {
      if (rows.isNotEmpty) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      final owned = canChange(def.bit);
      rows.add(_PermissionRow(
        def: def,
        state: overwriteState(overwrite, def.bit),
        note: editable && !owned ? '你在這筆驗證碼沒有這個權限，無法變更' : null,
        onSelect: !editable || !owned || saving ? null : (state) => onSet(def.bit, state),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!editable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('這個對象的身分組不低於你的最高身分組，無法修改', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(children: rows)),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.def, required this.state, required this.note, required this.onSelect});

  final PermissionDef def;
  final OverwriteState state;
  final String? note;
  // null 代表不能變更
  final ValueChanged<OverwriteState>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(def.name, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(def.description, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
        if (note != null) Text(note!, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
      ],
    );
    final control = _StateSwitch(state: state, onSelect: onSelect);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 窄的時候切換放到說明下面
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 10), control],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 16),
              control,
            ],
          );
        },
      ),
    );
  }
}

// 三段切換：選中的底色會滑過去（同 App 的類別藥丸）
class _StateSwitch extends StatelessWidget {
  const _StateSwitch({required this.state, required this.onSelect});

  final OverwriteState state;
  final ValueChanged<OverwriteState>? onSelect;

  Color _selectedColor(AppColors colors) => switch (state) {
        OverwriteState.allow => colors.accent,
        OverwriteState.deny => colors.alarm,
        OverwriteState.inherit => colors.ink,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onSelect != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: colors.surface2, borderRadius: BorderRadius.circular(999)),
        child: SlidingSelection(
          direction: Axis.horizontal,
          selectedIndex: OverwriteState.values.indexOf(state),
          color: colors.surface,
          children: [
            for (final option in OverwriteState.values)
              Semantics(
                button: true,
                selected: option == state,
                enabled: enabled,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? () => onSelect!(option) : null,
                  child: MouseRegion(
                    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Text(
                        option.label,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          fontWeight: FontWeight.w600,
                          color: option == state ? _selectedColor(colors) : colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 新增對象：可以搜尋的身分組與成員清單；管不到的變灰不能選
class _TargetPicker extends StatefulWidget {
  const _TargetPicker({required this.roles, required this.members, required this.canEdit});

  final List<Role> roles;
  final List<GroupMember> members;
  final bool Function(OverwriteTarget target) canEdit;

  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  String _query = '';

  bool _match(String text) => text.toLowerCase().contains(_query.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final roles = widget.roles.where((role) => _match(role.name)).toList();
    final members = widget.members
        .where((m) => _match('${m.person.name} ${m.person.username ?? ''} ${m.person.email ?? ''}'))
        .toList();

    Widget tile(OverwriteTarget target, Widget label) {
      final enabled = widget.canEdit(target);
      return Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: enabled ? () => Navigator.of(context).pop(target) : null,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: label),
        ),
      );
    }

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(text, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontWeight: FontWeight.w600)),
        );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: const Text('新增身分組或成員', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜尋',
                  prefixIcon: Icon(Icons.search_rounded, color: colors.inkMuted),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                children: [
                  if (roles.isEmpty && members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('沒有符合的對象', textAlign: TextAlign.center, style: TextStyle(color: colors.inkMuted)),
                    ),
                  if (roles.isNotEmpty) header('身分組'),
                  for (final role in roles)
                    tile(
                      OverwriteTarget(repo.OverwriteTargetType.role, role.id),
                      Row(children: [
                        RoleDot(color: role.color),
                        const SizedBox(width: 10),
                        Expanded(child: Text(role.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body))),
                      ]),
                    ),
                  if (members.isNotEmpty) header('成員'),
                  for (final member in members)
                    tile(OverwriteTarget(repo.OverwriteTargetType.member, member.id), PersonChip(person: member.person, size: 28)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: colors.ink),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

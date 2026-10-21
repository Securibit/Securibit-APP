import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../admin_repository.dart' as repo;
import '../permission_defs.dart';
import '../site_access.dart';
import '../widgets/admin_widgets.dart';
import 'group_detail.dart';
import 'group_forms.dart';

/*
 * 所有群組（同網站 /admin/groups，需要「管理所有群組」）：搜尋名稱或說明，點一個開後台的群組管理。
 * 有「建立群組」時右上角可以建立新群組（同網站 /groups 的規則），建立後直接打開。
 */
class GroupsSection extends StatefulWidget {
  const GroupsSection({super.key});

  @override
  State<GroupsSection> createState() => _GroupsSectionState();
}

class _GroupsSectionState extends State<GroupsSection> {
  final _keyword = TextEditingController();
  Timer? _debounce;
  String _search = '';
  int _seq = 0;

  List<AdminGroup>? _groups;
  bool _loading = false;
  String? _selectedId;
  bool _split = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  void _onKeyword(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next == _search) return;
      _search = next;
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final result = await repo.loadAdminGroups(_search);
    if (!mounted || seq != _seq) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _groups = data;
          _loading = false;
        });
      case Err(:final message):
        setState(() {
          _groups ??= const [];
          _loading = false;
        });
        await showErrorDialog(context, '載入群組失敗', message);
    }
  }

  void _open(String id) {
    if (_split) {
      setState(() => _selectedId = id);
      return;
    }
    unawaited(pushAdminPage<void>(
      context,
      AdminGroupDetailView(groupId: id, onChanged: _reload, onDeleted: () => Navigator.of(context).maybePop()),
    ));
  }

  Future<void> _create() async {
    final id = await showAdminForm<String>(context, const GroupCreateForm());
    if (id == null || !mounted) return;
    await _reload();
    if (mounted) _open(id);
  }

  @override
  Widget build(BuildContext context) {
    return MasterDetail(
      selectedId: _selectedId,
      placeholder: const Center(child: MutedText('選一個群組查看詳細資料')),
      detail: (context, id) => AdminGroupDetailView(
        groupId: id,
        onChanged: _reload,
        onDeleted: () {
          setState(() => _selectedId = null);
          unawaited(_reload());
        },
      ),
      list: (context, split) {
        _split = split;
        return _list(context, split);
      },
    );
  }

  Widget _list(BuildContext context, bool split) {
    final colors = context.colors;
    final groups = _groups;
    final canCreate = SiteAccessController.shared.can(SitePermission.createGroups);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(child: AdminSearchField(controller: _keyword, hint: '搜尋群組名稱', onChanged: _onKeyword)),
            if (canCreate) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '建立群組',
                onPressed: _create,
                style: IconButton.styleFrom(backgroundColor: colors.brand, foregroundColor: colors.accentInk),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ],
        ),
      ),
    ];
    if (groups == null) {
      children.add(const ListLoading());
    } else if (groups.isEmpty) {
      children.add(ListEmpty(_search.isEmpty ? '還沒有群組' : '沒有符合的群組'));
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < groups.length; i++) {
        if (i > 0) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
        rows.add(_GroupRow(group: groups[i], selected: split && groups[i].id == _selectedId, onTap: () => _open(groups[i].id)));
      }
      children
        ..add(AnimatedOpacity(
          opacity: _loading ? 0.6 : 1,
          duration: const Duration(milliseconds: 150),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
          ),
        ))
        ..add(FootNote('共 ${groups.length} 個群組'));
    }
    return RefreshIndicator.adaptive(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: children,
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.selected, required this.onTap});

  final AdminGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const tabular = [FontFeature.tabularFigures()];
    final owner = group.owner;
    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                    if (group.description.isNotEmpty)
                      Text(group.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                    Text(
                      '擁有者 ${owner == null ? '已刪除的使用者' : owner.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${group.memberCount} 人・${group.accountCount} 筆', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted, fontFeatures: tabular)),
                  Text(formatDate(group.createdAt), style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: tabular)),
                ],
              ),
              Icon(Icons.chevron_right_rounded, color: colors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

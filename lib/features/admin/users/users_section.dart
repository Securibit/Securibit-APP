import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/feedback.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_nav.dart';
import '../admin_repository.dart' as repo;
import '../widgets/admin_widgets.dart';
import 'user_detail.dart';

const _pageSize = 20;

/*
 * 後台使用者（同網站 /admin/users）：搜尋 Email、名稱或 @ID，一次載入 20 位、往下「載入更多」。
 * 寬的時候右邊是詳細資料，窄的時候點一位開下一頁。
 */
class UsersSection extends StatefulWidget {
  const UsersSection({super.key});

  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  final _keyword = TextEditingController();
  Timer? _debounce;
  String _search = '';
  // 只採用最後一次請求
  int _seq = 0;

  List<AdminUser>? _users;
  // 全站擁有者的 id（清單上標「擁有者」）
  String? _ownerId;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _selectedId;

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

  // 停止輸入 300ms 後才送出
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
    final search = _search;
    setState(() => _loading = true);
    final result = await repo.loadAdminUsers(search, 0, _pageSize);
    if (!mounted || seq != _seq) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _users = data.users;
          _total = data.total;
          _ownerId = data.siteOwnerId;
          _loading = false;
        });
      case Err(:final message):
        setState(() {
          _users ??= const [];
          _loading = false;
        });
        await showErrorDialog(context, '載入使用者失敗', message);
    }
  }

  Future<void> _loadMore() async {
    final users = _users;
    if (users == null || _loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    final result = await repo.loadAdminUsers(_search, users.length, _pageSize);
    if (!mounted || seq != _seq) return;
    setState(() => _loadingMore = false);
    switch (result) {
      case Ok(:final data):
        final seen = {for (final u in users) u.id};
        setState(() {
          _users = [...users, ...data.users.where((u) => !seen.contains(u.id))];
          _total = data.total;
        });
      case Err(:final message):
        await showErrorDialog(context, '載入使用者失敗', message);
    }
  }

  void _open(String id, bool split) {
    if (split) {
      setState(() => _selectedId = id);
      return;
    }
    unawaited(pushAdminPage<void>(
      context,
      UserDetailView(userId: id, onChanged: _reload, onDeleted: () => Navigator.of(context).maybePop()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MasterDetail(
      selectedId: _selectedId,
      placeholder: const Center(child: MutedText('選一位使用者查看詳細資料')),
      detail: (context, id) => UserDetailView(
        userId: id,
        onChanged: _reload,
        onDeleted: () {
          setState(() => _selectedId = null);
          unawaited(_reload());
        },
      ),
      list: (context, split) => _list(context, split),
    );
  }

  Widget _list(BuildContext context, bool split) {
    final colors = context.colors;
    final users = _users;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AdminSearchField(controller: _keyword, hint: '搜尋 Email、名稱或 @ID', onChanged: _onKeyword),
      ),
    ];
    if (users == null) {
      children.add(const ListLoading());
    } else if (users.isEmpty) {
      children.add(ListEmpty(_search.isEmpty ? '還沒有使用者' : '沒有符合的使用者'));
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < users.length; i++) {
        if (i > 0) rows.add(Divider(indent: 64, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
        rows.add(_UserRow(user: users[i], isOwner: users[i].isOwner ?? (_ownerId != null && _ownerId == users[i].id), selected: split && users[i].id == _selectedId, onTap: () => _open(users[i].id, split)));
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
        ..add(FootNote('共 $_total 位使用者'));
      if (users.length < _total) children.add(LoadMoreButton(onPressed: _loadMore, loading: _loadingMore));
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

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.isOwner, required this.selected, required this.onTap});

  final AdminUser user;
  // 全站擁有者
  final bool isOwner;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const tabular = [FontFeature.tabularFigures()];
    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              UserAvatar(name: user.name.isNotEmpty ? user.name : user.email, photoUrl: user.photoUrl, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名稱一定要看得到：欄位窄時「擁有者」縮成一個圖示，名稱太長就截成「…」
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 160;
                        return Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.name.isNotEmpty ? user.name : '（未命名）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isOwner) ...[
                              const SizedBox(width: 6),
                              compact
                                  ? Tooltip(message: '擁有者', child: Icon(Icons.workspace_premium_rounded, size: 16, color: colors.accent))
                                  : const Tag('擁有者', accent: true),
                            ],
                          ],
                        );
                      },
                    ),
                    Text(
                      user.email.isNotEmpty ? user.email : (user.username != null ? '@${user.username}' : '沒有電子郵件'),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.vaultEnabled) ...[
                        Tooltip(message: '已設定加密密碼', child: Icon(Icons.lock_rounded, size: 14, color: colors.inkMuted)),
                        const SizedBox(width: 4),
                      ],
                      Text('${user.totpCount} 筆', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted, fontFeatures: tabular)),
                    ],
                  ),
                  // 同網站的清單：最後登入與最後活動（沒有就是「無」）
                  Text('最後登入 ${formatDate(user.lastLoginAt)}', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: tabular)),
                  Text('最後活動 ${formatDate(user.lastActiveAt)}', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontFeatures: tabular)),
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

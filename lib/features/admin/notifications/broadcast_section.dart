import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../notifications/notification_models.dart' show safeNotificationLink;
import '../../profile/session_models.dart';
import '../admin_format.dart';
import '../admin_models.dart';
import '../admin_repository.dart' as admin;
import '../hierarchy.dart';
import '../permission_defs.dart';
import '../site_access.dart';
import '../widgets/admin_widgets.dart';
import 'broadcast_models.dart';
import 'broadcast_repository.dart' as repo;

/*
 * 後台「發送通知」（同網站 /admin/notifications）：類別、內容（標題、內文、連結）、對象條件
 * （所有使用者、指定使用者與他們的裝置、網站身分組、平台、版本範圍、最近幾天用過），
 * 條件停下來 0.5 秒後預覽人數與裝置數，確認後送出；下面是發送紀錄。
 * 要「發送通知」權限；搜尋使用者、列出裝置另外要「查看使用者」。權限都由資料庫再檢查一次。
 */
class BroadcastSection extends StatefulWidget {
  const BroadcastSection({super.key});

  @override
  State<BroadcastSection> createState() => _BroadcastSectionState();
}

class _BroadcastSectionState extends State<BroadcastSection> {
  // 內容
  BroadcastKind _kind = BroadcastKind.update;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController();

  // 對象
  bool _allUsers = false;
  List<AdminUser> _users = const [];
  final Set<String> _roleIds = {};
  final Set<String> _platforms = {};
  final Set<String> _sessionIds = {};
  final _versionMin = TextEditingController();
  final _versionMax = TextEditingController();
  final _lastSeenDays = TextEditingController();

  List<Role> _roles = const [];

  // 預覽：結果和它對應的條件
  Timer? _previewTimer;
  String? _previewKey;
  BroadcastPreview? _preview;
  String? _previewError;
  int _previewSeq = 0;
  bool _sending = false;

  // 發送紀錄（null：載入中）
  List<BroadcastRecord>? _records;
  bool _moreRecords = false;
  bool _loadingMore = false;

  bool get _canPickUsers => SiteAccessController.shared.can(SitePermission.viewUsers);

  @override
  void initState() {
    super.initState();
    for (final c in [_versionMin, _versionMax, _lastSeenDays]) {
      c.addListener(_onFilterChanged);
    }
    unawaited(_loadRoles());
    unawaited(_loadRecords());
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    for (final c in [_title, _body, _link, _versionMin, _versionMax, _lastSeenDays]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRoles() async {
    final result = await admin.loadSiteRoles();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() => _roles = sortRoles(data));
      case Err(:final message):
        await showErrorDialog(context, '載入身分組失敗', message);
    }
  }

  Future<void> _loadRecords() async {
    final result = await repo.loadBroadcasts();
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() {
          _records = data;
          _moreRecords = data.length >= repo.broadcastPageSize;
        });
      case Err(:final message):
        setState(() => _records = const []);
        await showErrorDialog(context, '載入發送紀錄失敗', message);
    }
  }

  Future<void> _loadMoreRecords() async {
    final records = _records;
    if (records == null || records.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    final result = await repo.loadBroadcasts(before: records.last.id);
    if (!mounted) return;
    setState(() => _loadingMore = false);
    switch (result) {
      case Ok(:final data):
        final seen = {for (final r in records) r.id};
        setState(() {
          _records = [...records, ...data.where((r) => !seen.contains(r.id))];
          _moreRecords = data.length >= repo.broadcastPageSize;
        });
      case Err(:final message):
        await showErrorDialog(context, '載入發送紀錄失敗', message);
    }
  }

  // ---------- 檢查與條件 ----------

  String get _trimmedTitle => _title.text.trim();
  String get _trimmedLink => _link.text.trim();
  bool get _titleInvalid => _trimmedTitle.length > broadcastTitleMax;
  bool get _bodyInvalid => _body.text.trim().length > broadcastBodyMax;
  bool get _linkInvalid => _trimmedLink.isNotEmpty && (_trimmedLink.length > broadcastLinkMax || safeNotificationLink(_trimmedLink) == null);
  bool get _versionMinInvalid => _versionMin.text.trim().isNotEmpty && !isValidVersion(_versionMin.text);
  bool get _versionMaxInvalid => _versionMax.text.trim().isNotEmpty && !isValidVersion(_versionMax.text);

  int? get _days => _lastSeenDays.text.trim().isEmpty ? null : int.tryParse(_lastSeenDays.text.trim());
  bool get _daysInvalid => _lastSeenDays.text.trim().isNotEmpty && (_days == null || _days! < 1 || _days! > 3650);
  bool get _conditionsInvalid => _versionMinInvalid || _versionMaxInvalid || _daysInvalid;

  BroadcastFilter get _filter => BroadcastFilter(
        allUsers: _allUsers,
        userIds: [for (final u in _users) u.id],
        siteRoleIds: _roleIds.toList(),
        platforms: [for (final p in broadcastPlatforms) if (_platforms.contains(p.$1)) p.$1],
        sessionIds: _sessionIds.toList(),
        versionMin: _versionMin.text,
        versionMax: _versionMax.text,
        lastSeenDays: _daysInvalid ? null : _days,
      );

  String get _filterKey => jsonEncode(_filter.toJson());

  void _onFilterChanged() {
    setState(() {});
    _previewTimer?.cancel();
    final filter = _filter;
    if (!filter.hasTarget || _conditionsInvalid) return;
    final key = _filterKey;
    _previewTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_runPreview(key, filter)));
  }

  Future<void> _runPreview(String key, BroadcastFilter filter) async {
    final seq = ++_previewSeq;
    final result = await repo.previewBroadcast(filter);
    if (!mounted || seq != _previewSeq) return;
    setState(() {
      _previewKey = key;
      switch (result) {
        case Ok(:final data):
          _preview = data;
          _previewError = null;
        case Err(:final message):
          _preview = null;
          _previewError = message;
      }
    });
  }

  // 預覽的結果是不是目前的條件
  bool get _previewCurrent => _previewKey != null && _previewKey == _filterKey;

  bool get _canSend {
    final preview = _previewCurrent ? _preview : null;
    return !_sending &&
        _trimmedTitle.isNotEmpty &&
        !_titleInvalid &&
        !_bodyInvalid &&
        !_linkInvalid &&
        _filter.hasTarget &&
        !_conditionsInvalid &&
        preview != null &&
        preview.users > 0 &&
        !preview.tooMany;
  }

  Future<void> _send() async {
    final preview = _preview;
    if (!_canSend || preview == null) return;
    final kind = _kind;
    final ok = await confirmDialog(
      context,
      title: '發送${kind.label}',
      message: '將「${kind.label}」發送給 ${preview.users} 位使用者，其中 ${preview.pushDevices} 台裝置會收到推播。送出後無法收回。'
          '${kind == BroadcastKind.important ? '重要公告使用者無法關閉，登入網站時也會在頂端顯示。' : ''}',
      confirmLabel: '發送',
      danger: kind == BroadcastKind.important,
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    final result = await repo.sendBroadcast(kind, _title.text, _body.text, _trimmedLink, _filter);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result) {
      case Ok(:final data):
        showToast(context, '已發送給 $data 位使用者');
        setState(() {
          _title.clear();
          _body.clear();
          _link.clear();
        });
        unawaited(_loadRecords());
      case Err(:final message):
        await showErrorDialog(context, '發送失敗', message);
    }
  }

  void _setUsers(List<AdminUser> users) {
    _users = users;
    // 被移除的人，他的裝置也拿掉（列出裝置時也會再清一次）
    if (users.isEmpty) _sessionIds.clear();
    _onFilterChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (!SiteAccessController.shared.can(SitePermission.sendNotifications)) {
      return NoPermissionView(permission: permissionName(sitePermissionDefs, SitePermission.sendNotifications));
    }
    final colors = context.colors;
    final preview = _previewCurrent ? _preview : null;
    final previewError = _previewCurrent ? _previewError : null;
    final filter = _filter;

    Widget previewRow(String label, int? value) => GroupedRow(label: label, value: value == null ? '計算中…' : '$value');

    return AdminScrollBody(
      onRefresh: _loadRecords,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: MutedText('發送公告與推廣通知，會出現在鈴鐺裡，並推播到符合條件的裝置'),
        ),
        // 類別
        GroupedList(
          header: '類別',
          footer: '使用者可以在設定關掉重要公告以外的類別，關掉的人不會收到推播，但鈴鐺裡還是看得到',
          children: [
            for (final kind in BroadcastKind.values)
              CheckRow(
                label: kind.label,
                description: kind.description,
                checked: _kind == kind,
                onTap: () => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 24),
        // 內容
        GroupedList(
          header: '內容',
          footer: '不要在通知裡放驗證碼、金鑰、密碼或其他敏感資料',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('標題'),
                  TextField(
                    controller: _title,
                    maxLength: broadcastTitleMax,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(errorText: _titleInvalid ? '最多 $broadcastTitleMax 字' : null),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('內文'),
                  TextField(
                    controller: _body,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: broadcastBodyMax,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(errorText: _bodyInvalid ? '最多 $broadcastBodyMax 字' : null),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('連結'),
                  TextField(
                    controller: _link,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '/download',
                      errorText: _linkInvalid ? '只能填站內路徑，例如 /download' : null,
                      helperText: '選填。點通知時開啟的站內頁面，要用 / 開頭',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 對象
        GroupedList(
          header: '對象',
          footer: _allUsers ? '下面的平台、版本與最近使用的條件仍然會套用' : '沒有開的話，至少要選一個條件；所有條件同時符合才會收到',
          children: [
            GroupedRow(
              label: '所有使用者',
              trailing: Switch.adaptive(
                value: _allUsers,
                onChanged: (on) {
                  _allUsers = on;
                  _onFilterChanged();
                },
              ),
            ),
          ],
        ),
        if (!_allUsers) ...[
          const SizedBox(height: 24),
          if (_canPickUsers)
            _UserPicker(selected: _users, onChanged: _setUsers)
          else
            GroupedList(
              header: '使用者',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: MutedText('需要「${permissionName(sitePermissionDefs, SitePermission.viewUsers)}」權限才能指定使用者'),
                ),
              ],
            ),
          if (_users.isNotEmpty) ...[
            const SizedBox(height: 24),
            _DevicePicker(
              users: _users,
              selected: _sessionIds,
              onChanged: (ids) {
                _sessionIds
                  ..clear()
                  ..addAll(ids);
                _onFilterChanged();
              },
            ),
          ],
          if (_roles.isNotEmpty) ...[
            const SizedBox(height: 24),
            GroupedList(
              header: '網站身分組',
              footer: '有任一個勾選的身分組就算符合；@everyone 是所有人',
              children: [
                for (final role in _roles)
                  CheckRow(
                    labelWidget: Align(alignment: Alignment.centerLeft, child: RoleChip(name: role.name, color: role.color)),
                    checked: _roleIds.contains(role.id),
                    onTap: () {
                      _roleIds.contains(role.id) ? _roleIds.remove(role.id) : _roleIds.add(role.id);
                      _onFilterChanged();
                    },
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
        GroupedList(
          header: '平台',
          footer: '都沒勾就是不限平台',
          children: [
            for (final (key, name) in broadcastPlatforms)
              CheckRow(
                label: name,
                description: key == 'web' ? '沒有登入中的 App、只用過網站的人；只會出現在鈴鐺，沒有推播' : null,
                checked: _platforms.contains(key),
                onTap: () {
                  _platforms.contains(key) ? _platforms.remove(key) : _platforms.add(key);
                  _onFilterChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        GroupedList(
          header: '版本與使用時間',
          footer: '版本範圍包含兩端，只看 App 的版本；留空就是不限',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('最低版本'),
                            TextField(
                              controller: _versionMin,
                              autocorrect: false,
                              decoration: InputDecoration(hintText: '1.4.0', errorText: _versionMinInvalid ? '例如 1.4.0' : null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('最高版本'),
                            TextField(
                              controller: _versionMax,
                              autocorrect: false,
                              decoration: InputDecoration(hintText: '1.5.0', errorText: _versionMaxInvalid ? '例如 1.5.0' : null),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('最近幾天用過'),
                  TextField(
                    controller: _lastSeenDays,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '30',
                      suffixText: '天',
                      errorText: _daysInvalid ? '請輸入 1 到 3650' : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 預覽與送出
        GroupedList(
          header: '預覽',
          children: [
            if (!filter.hasTarget)
              const GroupedRow(label: '請選擇通知對象')
            else if (_conditionsInvalid)
              const GroupedRow(label: '條件格式不正確')
            else if (previewError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(previewError, style: TextStyle(fontSize: AppText.body, color: colors.alarm)),
              )
            else ...[
              previewRow('使用者', preview?.users),
              previewRow('App 裝置', preview?.devices),
              previewRow('收得到推播的裝置', preview?.pushDevices),
            ],
          ],
        ),
        if (preview != null && preview.tooMany)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('一次最多 ${preview.limit} 位使用者，請縮小範圍', style: TextStyle(fontSize: AppText.caption, color: colors.alarm)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _canSend ? _send : null,
            child: _sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('發送'),
          ),
        ),
        const SizedBox(height: 32),
        // 發送紀錄
        const SectionHeader('發送紀錄'),
        if (_records == null)
          const ListLoading()
        else if (_records!.isEmpty)
          const ListEmpty('還沒有發送過通知')
        else ...[
          GroupedList(children: [for (final record in _records!) _RecordRow(record: record, roles: _roles)]),
          if (_moreRecords) LoadMoreButton(onPressed: _loadMoreRecords, loading: _loadingMore),
        ],
      ],
    );
  }
}

/// 選擇清單的一列：整列可點，選中時右邊打勾（同網站 CheckRow）
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, this.label, this.labelWidget, this.description, required this.checked, required this.onTap});

  final String? label;
  final Widget? labelWidget;
  final String? description;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      checked: checked,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      labelWidget ?? Text(label ?? '', style: const TextStyle(fontSize: AppText.body)),
                      if (description != null) Text(description!, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, color: checked ? colors.accent : Colors.transparent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 使用者多選（同網站 UserPicker）：上面是已選的人，下面搜尋 Email、名稱或 @ID 加入
class _UserPicker extends StatefulWidget {
  const _UserPicker({required this.selected, required this.onChanged});

  final List<AdminUser> selected;
  final ValueChanged<List<AdminUser>> onChanged;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  static const _resultLimit = 8;

  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  // 搜尋結果與它對應的搜尋字
  String? _resultKey;
  List<AdminUser> _results = const [];
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = value.trim();
      setState(() => _query = query);
      if (query.isNotEmpty) unawaited(_run(query));
    });
  }

  Future<void> _run(String query) async {
    final seq = ++_seq;
    final result = await admin.loadAdminUsers(query, 0, _resultLimit);
    if (!mounted || seq != _seq) return;
    setState(() {
      _resultKey = query;
      _results = result is Ok<AdminUserPage> ? result.data.users : const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedIds = {for (final u in widget.selected) u.id};
    final loading = _query.isNotEmpty && _resultKey != _query;
    final shown = _query.isNotEmpty && _resultKey == _query ? _results.where((u) => !selectedIds.contains(u.id)).toList() : const <AdminUser>[];
    final full = widget.selected.length >= broadcastUserPickMax;

    return GroupedList(
      header: '使用者',
      children: [
        for (final user in widget.selected)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: PersonChip(person: user.brief, subtitle: user.email, size: 32)),
                IconButton(
                  tooltip: '移除 ${user.displayName}',
                  onPressed: () => widget.onChanged(widget.selected.where((u) => u.id != user.id).toList()),
                  icon: Icon(Icons.close_rounded, color: colors.inkMuted),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: AbsorbPointer(
            absorbing: full,
            child: AdminSearchField(
              controller: _search,
              hint: full ? '最多指定 $broadcastUserPickMax 位' : '搜尋 Email、名稱或 @ID',
              onChanged: _onSearch,
            ),
          ),
        ),
        if (loading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (_query.isNotEmpty && shown.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: MutedText('沒有符合的使用者'))
        else
          for (final user in shown)
            InkWell(
              onTap: full ? null : () => widget.onChanged([...widget.selected, user]),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(child: PersonChip(person: user.brief, subtitle: user.email, size: 32)),
                    Icon(Icons.add_rounded, color: colors.accent),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// 指定裝置（同網站 DevicePicker）：列出已選使用者登入中的裝置，勾選的才收得到推播；都沒勾就是他們所有裝置
class _DevicePicker extends StatefulWidget {
  const _DevicePicker({required this.users, required this.selected, required this.onChanged});

  final List<AdminUser> users;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  // 使用者 id → 裝置；沒有這個 key 是還在載入，null 是讀不到
  final Map<String, List<SessionRecord>?> _sessions = {};

  @override
  void initState() {
    super.initState();
    _loadMissing();
  }

  @override
  void didUpdateWidget(covariant _DevicePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadMissing();
    _dropRemoved();
  }

  void _loadMissing() {
    for (final user in widget.users) {
      if (!_sessions.containsKey(user.id)) unawaited(_load(user.id));
    }
  }

  final Set<String> _loading = {};

  Future<void> _load(String userId) async {
    if (!_loading.add(userId)) return;
    final result = await admin.loadAdminUserSessions(userId);
    _loading.remove(userId);
    if (!mounted) return;
    setState(() => _sessions[userId] = result is Ok<List<SessionRecord>> ? result.data : null);
    _dropRemoved();
  }

  // 使用者被移除後，拿掉他已勾選的裝置
  void _dropRemoved() {
    if (widget.users.any((u) => !_sessions.containsKey(u.id))) return;
    final valid = {
      for (final u in widget.users) ...?_sessions[u.id]?.map((s) => s.id),
    };
    if (widget.selected.any((id) => !valid.contains(id))) {
      final next = widget.selected.where(valid.contains).toSet();
      scheduleMicrotask(() => widget.onChanged(next));
    }
  }

  Widget _row(SessionRecord session) {
    final display = sessionDisplay(session);
    return CheckRow(
      label: display.name,
      description: '${display.platform} · ${display.client} · 最後活動 ${formatDateTime(session.lastActiveAt)}',
      checked: widget.selected.contains(session.id),
      onTap: () {
        final next = {...widget.selected};
        next.contains(session.id) ? next.remove(session.id) : next.add(session.id);
        widget.onChanged(next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, user) in widget.users.indexed) ...[
          if (index > 0) const SizedBox(height: 16),
          GroupedList(
            header: index == 0 ? '指定裝置 · ${user.displayName}' : user.displayName,
            footer: index == widget.users.length - 1 ? '都沒勾就是這些人的所有裝置；勾了只推播到勾選的裝置' : null,
            children: switch (_sessions[user.id]) {
              null when !_sessions.containsKey(user.id) => [
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                ],
              null => [const Padding(padding: EdgeInsets.all(16), child: MutedText('讀不到這位使用者的裝置'))],
              final list when list.isEmpty => [const Padding(padding: EdgeInsets.all(16), child: MutedText('沒有登入中的裝置'))],
              final list => [
                  for (final session in list) _row(session),
                ],
            },
          ),
        ],
      ],
    );
  }
}

/// 發送紀錄的一筆（同網站 BroadcastHistory）
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.roles});

  final BroadcastRecord record;
  final List<Role> roles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = record.filter.describe({for (final r in roles) r.id: r.name});
    final by = record.createdBy;
    final who = by == null ? '已刪除的使用者' : (by.name.isNotEmpty ? by.name : (by.username != null ? '@${by.username}' : '管理員'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tag(BroadcastKind.nameOf(record.kind)),
              const SizedBox(width: 8),
              Expanded(child: Text(record.title, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text(formatDateTime(record.createdAt), style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
            ],
          ),
          if (record.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
          ],
          if (record.link != null) ...[
            const SizedBox(height: 4),
            Text('連結：${record.link}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ],
          const SizedBox(height: 4),
          Text(
            '$who · ${record.userCount} 位使用者 · ${record.deviceCount} 台裝置${target.isEmpty ? '' : ' · $target'}',
            style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

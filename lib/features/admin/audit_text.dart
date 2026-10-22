import 'admin_models.dart';

/*
 * 操作紀錄的中文說明（同網站 src/lib/permissions/auditActions.ts、src/lib/users/activity.ts、
 * src/components/permissions/AuditLogList.tsx）
 */

const auditActionTexts = <String, String>{
  'site.role.create': '建立身分組',
  'site.role.update': '編輯身分組',
  'site.role.delete': '刪除身分組',
  'site.role.reorder': '調整身分組順序',
  'site.user.roles': '變更使用者身分組',
  'site.user.update': '修改使用者資料',
  'site.user.delete': '刪除使用者',
  'site.user.totp.view': '查看使用者的 2FA',
  'site.user.totp.update': '修改使用者的 2FA',
  'site.user.totp.delete': '刪除使用者的 2FA',
  'group.create': '建立群組',
  'group.update': '修改群組資料',
  'group.transfer': '轉移擁有權',
  'group.role.create': '建立身分組',
  'group.role.update': '編輯身分組',
  'group.role.delete': '刪除身分組',
  'group.role.reorder': '調整身分組順序',
  'group.member.roles': '變更成員身分組',
  'group.member.kick': '移除成員',
  'group.member.join': '加入群組',
  'group.member.add': '直接加入成員',
  'group.member.leave': '離開群組',
  'group.invite.create': '建立邀請連結',
  'group.invite.revoke': '撤銷邀請連結',
  'group.invite.email': '邀請使用者',
  'group.account.create': '新增驗證碼',
  'group.account.update': '編輯驗證碼',
  'group.account.delete': '刪除驗證碼',
  'group.account.overwrite': '變更驗證碼權限',
  'group.account.secret.view': '查看金鑰',
  'group.account.clear': '清空驗證碼',
  'group.category.reorder': '調整類別順序',
  'group.encryption.enable': '開啟加密',
  'group.encryption.disable': '關閉加密',
  'user.username': '變更 @ID',
  'user.name': '變更名稱',
  'user.photo': '變更大頭照',
  'user.background': '變更背景圖',
  'user.phone': '變更電話',
  'user.email': '變更電子郵件',
  'user.vault.enable': '啟用金鑰加密',
  'user.vault.password': '變更加密密碼',
  'user.vault.disable': '停用金鑰加密',
  'user.vault.reset': '重設加密密碼',
  'user.default_group': '變更預設群組',
};

String auditActionText(String action) => auditActionTexts[action] ?? action;

// 帳號變更（user.*）的「舊值 → 新值」；圖片網址太長不顯示
const _changeActions = {'user.username', 'user.name', 'user.phone', 'user.email', 'user.default_group'};

String? auditChangeText(String action, Map<String, dynamic> detail) {
  if (!_changeActions.contains(action) || detail.isEmpty) return null;
  String show(Object? value) => value is String && value.isNotEmpty ? value : '（無）';
  return '${show(detail['old'])} → ${show(detail['new'])}';
}

const _targetTypeTexts = <String, String>{
  'role': '身分組',
  'user': '使用者',
  'member': '成員',
  'account': '驗證碼',
  'invite': '邀請',
  'group': '群組',
};

/// 目標的簡短說明：類型 +（detail.name 或縮短的 id）
String? auditTargetText(AuditLog log) {
  if (log.targetType == null && log.targetId == null) return null;
  final type = log.targetType == null ? '' : (_targetTypeTexts[log.targetType] ?? log.targetType!);
  final rawName = log.detail['name'];
  final name = rawName is String && rawName.isNotEmpty ? '「$rawName」' : '';
  final id = log.targetId;
  final shortId = name.isEmpty && id != null ? (id.length > 12 ? '${id.substring(0, 8)}…' : id) : '';
  return [type, name.isNotEmpty ? name : shortId].where((s) => s.isNotEmpty).join(' ');
}

// ---------- 登入紀錄 ----------

const _providerTexts = {'google': 'Google', 'email': 'Email'};

/// 登入方式的顯示文字
String providerText(String? provider) => provider == null ? '未知方式' : (_providerTexts[provider] ?? provider);

/// 登入紀錄的 IP：null 是管不到對方（資料庫不給），空字串是沒有紀錄
String loginIpText(String? ip) => ip == null ? 'IP 不公開' : (ip.isEmpty ? '未知 IP' : ip);

// ---------- 帳號操作紀錄 ----------

String? _str(Object? value) => value is String && value.isNotEmpty ? value : null;

List<String> _names(Object? value) => value is List ? value.whereType<String>().where((v) => v.isNotEmpty).toList() : [];

String _quoted(List<String> list) => list.map((name) => '「$name」').join('、');

// 操作者的稱呼：名稱 → @ID → email
String _actorName(PersonBrief? actor) {
  if (actor == null) return '系統';
  if (actor.name.isNotEmpty) return actor.name;
  if (actor.username != null) return '@${actor.username}';
  return actor.email ?? '某位使用者';
}

// 「X 從 a 改成 b」；沒有舊值時是「設定 X 為 b」，沒有新值時是「清除 X（原本是 a）」
String _changeText(String label, String? oldValue, String? newValue, {bool quote = false}) {
  String v(String value) => quote ? '「$value」' : ' $value ';
  if (oldValue != null && newValue != null) return '$label從${v(oldValue)}改成${v(newValue)}'.trim();
  if (newValue != null) return '設定$label為${v(newValue)}'.trim();
  if (oldValue != null) return '清除$label（原本是${quote ? v(oldValue) : oldValue}）';
  return '變更$label';
}

String _usernameText(String? oldValue, String? newValue) {
  if (oldValue != null && newValue != null) return '@ID 從 $oldValue 改成 $newValue';
  if (newValue != null) return '設定 @ID 為 $newValue';
  if (oldValue != null) return '清除 @ID（原本是 $oldValue）';
  return '變更 @ID';
}

/// 一筆帳號操作紀錄的中文描述；subjectId 是這些紀錄的主人，self：本人看用「你」，後台看用「他」
String describeActivity(AccountActivity activity, String subjectId, {bool self = false}) {
  final log = activity.log;
  final d = log.detail;
  final you = self ? '你' : '他';
  final actor = log.actor;
  final byOther = actor != null && actor.id != subjectId;
  final name = _actorName(actor);
  // 本人做的不加；別人（管理員）做的、系統做的在後面註明
  final suffix = actor == null ? '（系統）' : (byOther ? '（由 $name）' : '');
  final admin = '管理員 $name';
  final group = activity.groupName ?? _str(d['name']) ?? '已刪除的群組';

  switch (log.action) {
    case 'user.username':
      return _usernameText(_str(d['old']), _str(d['new'])) + suffix;
    case 'user.name':
      return _changeText('名稱', _str(d['old']), _str(d['new']), quote: true) + suffix;
    case 'user.photo':
      return (_str(d['new']) != null ? '更換了大頭照' : '移除了大頭照') + suffix;
    case 'user.background':
      return (_str(d['new']) != null ? '更換了背景圖' : '移除了背景圖') + suffix;
    case 'user.phone':
      return _changeText('電話', _str(d['old']), _str(d['new'])) + suffix;
    case 'user.email':
      return _changeText('電子郵件', _str(d['old']), _str(d['new'])) + (actor != null ? suffix : '（從登入帳號同步）');
    case 'user.vault.enable':
      return '啟用金鑰加密$suffix';
    case 'user.vault.password':
      return '變更加密密碼$suffix';
    case 'user.vault.disable':
      return '停用金鑰加密$suffix';
    case 'user.vault.reset':
      return '忘記加密密碼並重設（已加密的驗證碼一併刪除）$suffix';
    case 'user.default_group':
      return _changeText('預設群組', _str(d['old']), _str(d['new']), quote: true) + suffix;
    case 'site.user.update':
      final parts = [
        if (_str(d['old_name']) != _str(d['name'])) _changeText('名稱', _str(d['old_name']), _str(d['name']), quote: true),
        if (_str(d['old_username']) != _str(d['username'])) _usernameText(_str(d['old_username']), _str(d['username'])),
      ];
      return '$admin 修改了$you的資料${parts.isEmpty ? '' : '：${parts.join('、')}'}';
    case 'site.user.roles':
      final added = _names(d['added_names']);
      final removed = _names(d['removed_names']);
      final who = actor != null ? admin : '系統';
      final parts = [
        if (added.isNotEmpty) '指派身分組 ${_quoted(added)}',
        if (removed.isNotEmpty) '移除身分組 ${_quoted(removed)}',
      ];
      return parts.isEmpty ? '$who 變更了$you的身分組' : '$who ${parts.join('，並')}';
    case 'site.user.totp.view':
      return '$admin 查看了$you的 2FA';
    case 'site.user.totp.update':
      return '$admin 修改了$you的 2FA${_str(d['item_name']) != null ? '「${_str(d['item_name'])}」' : ''}';
    case 'site.user.totp.delete':
      return '$admin 刪除了$you的 2FA${_str(d['item_name']) != null ? '「${_str(d['item_name'])}」' : ''}';
    case 'group.member.join':
      return '加入群組「$group」';
    case 'group.member.add':
      return '$admin 把$you加入群組「$group」';
    case 'group.member.leave':
      return '離開群組「$group」';
    case 'group.member.kick':
      return '被 $name 移出群組「$group」';
    case 'group.encryption.enable':
      return '開啟群組「$group」的加密';
    case 'group.encryption.disable':
      return d['reset'] == true ? '重設加密密碼，群組「$group」改成不加密' : '關閉群組「$group」的加密';
    default:
      return auditActionText(log.action);
  }
}

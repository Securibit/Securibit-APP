// 後台的顯示與檢查小工具（同網站 src/lib/utils.ts 的 formatDateTime、src/lib/totp/account.ts 的 @ID 規則）

String _pad(int value) => value.toString().padLeft(2, '0');

/// 「2026/10/21 14:03:09」（本機時區）；沒有值顯示「無」，解析不了就照原樣
String formatDateTime(String? value) {
  if (value == null || value.isEmpty) return '無';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final d = parsed.toLocal();
  return '${d.year}/${_pad(d.month)}/${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';
}

/// 「2026/10/21」（清單裡放不下時間時）
String formatDate(String? value) {
  if (value == null || value.isEmpty) return '無';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final d = parsed.toLocal();
  return '${d.year}/${_pad(d.month)}/${_pad(d.day)}';
}

// ---------- @ID ----------

// 3～32 字，小寫英數、底線、點
final _usernamePattern = RegExp(r'^[a-z0-9_.]{3,32}$');
final _uuidLike32 = RegExp(r'^[0-9a-f]{32}$', caseSensitive: false);
final _uuidLikeDashed = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false);

// 不能當 @ID 的字（同資料庫 0013 的 username_reserved）
const _reservedUsernames = {
  'admin', 'administrator', 'root', 'system', 'securibit', 'everyone',
  'here', 'support', 'help', 'null', 'undefined',
  'me', 'u', 'api', 'auth', 'about', 'disclaimer', 'code', 'codes', 'addcode',
  'groups', 'group', 'invite', 'invites', 'invitation', 'invitations',
  'settings', 'setting', 'new', 'edit', 'login', 'logout', 'signin', 'signout', 'signup', 'register',
  'user', 'users', 'profile', 'profiles', 'mypage', 'update_info', 'account', 'accounts',
  'notifications', 'roles', 'audit', 'callback', 'static', 'public', 'assets',
  '_next', 'favicon.ico', 'robots.txt', 'sitemap.xml', 'manifest.json',
};

/// 去掉開頭的 @、轉小寫（資料庫也會再處理一次）
String normalizeUsername(String value) => value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

/// 不查資料庫就能判斷的問題（格式、UUID 樣式、保留字）；name 要先正規化。沒問題回傳 null
String? usernameProblem(String name) {
  if (!_usernamePattern.hasMatch(name)) return '@ID 只能使用 3～32 個英文小寫字母、數字、底線（_）或句點（.）';
  if (_uuidLike32.hasMatch(name) || _uuidLikeDashed.hasMatch(name)) return '@ID 不能是 UUID 的格式（32 位英數字）';
  if (_reservedUsernames.contains(name)) return '這個 @ID 是保留字，不能使用';
  return null;
}

/// 身分組顏色：'#rrggbb' 轉成 ARGB；空字串或格式不對回傳 null
int? parseRoleColor(String color) {
  final hex = color.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return 0xFF000000 | int.parse(hex, radix: 16);
}

/// 自訂顏色的輸入：接受「17ffac」「#17FFAC」，回傳小寫 '#rrggbb'；格式不對回傳 null
String? normalizeRoleColor(String input) {
  final hex = input.trim().replaceFirst('#', '').toLowerCase();
  return RegExp(r'^[0-9a-f]{6}$').hasMatch(hex) ? '#$hex' : null;
}

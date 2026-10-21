import '../codes/code_models.dart';
import '../codes/otp_snapshot.dart';
import '../codes/secret_handle.dart';
import '../codes/totp/otp.dart';
import '../groups/group_models.dart';

/*
 * 桌面常駐選單的內容（macOS 選單列、Linux 系統匣共用；純資料，方便測試）：
 * 依群組分段、釘選的在前，每一筆是名稱、驗證碼與剩餘秒數。
 * 原生端只拿到這裡算好的顯示文字；金鑰留在 Rust（這裡只有 SecretHandle），點了要複製時再回來用 codeFor 算當下的碼。
 * macOS 用 name、code、remaining 排成對齊的欄位；Linux 的 AppIndicator 選單只能顯示一行純文字，用 label。
 */

// 驗證碼加起來超過這個數量就每個群組收成一個子選單，選單才不會長到超出螢幕
const menuBarInlineLimit = 20;

// 名稱太長時截斷，選單才不會被撐得很寬
const _nameLimit = 32;

// 一行純文字的欄位間隔（全形空白，比半形空白明顯）
const _labelGap = '\u3000';

enum MenuBarStatus { signedOut, loading, locked, ready }

/// 一個群組讀到的資料（同 CodesController 的清單、金鑰與伺服器產碼）
class MenuGroupData {
  const MenuGroupData({this.accounts, this.secrets = const {}, this.server, this.error});

  // null 代表還在載入
  final List<GroupAccount>? accounts;
  // { 驗證碼 id: 指向 Rust 裡金鑰的 handle }
  final Map<String, SecretHandle> secrets;
  final ServerCodes? server;
  final String? error;
}

class MenuBarItem {
  const MenuBarItem({
    required this.id,
    required this.name,
    required this.code,
    required this.remaining,
    required this.expiring,
    required this.copyable,
  });

  // 「群組 id/驗證碼 id」
  final String id;
  final String name;
  // 已排版的驗證碼（123 456）、遮住的碼或狀態文字
  final String code;
  // 「12 秒」；沒有驗證碼時是 null
  final String? remaining;
  final bool expiring;
  final bool copyable;

  /// 一行純文字（不能排欄位、不能上色的選單用）：「名稱　驗證碼　剩餘秒數」，快到期時秒數前加「剩」
  String get label {
    final parts = [name, code, if (remaining != null) expiring ? '剩 $remaining' : remaining!];
    return parts.join(_labelGap);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'remaining': remaining,
        'expiring': expiring,
        'copyable': copyable,
        'label': label,
      };
}

class MenuBarSection {
  const MenuBarSection({required this.id, required this.title, required this.items, this.note});

  final String id;
  final String title;
  final List<MenuBarItem> items;
  // 沒有可列出的驗證碼時顯示的說明（需要解鎖、載入中…）
  final String? note;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'note': note,
        'items': [for (final item in items) item.toMap()],
      };
}

// 點了要複製時用來算當下驗證碼的資料（不送到原生端）
class _CopySource {
  const _CopySource(this.account, this.secret, this.server);

  final GroupAccount account;
  final SecretHandle? secret;
  final ServerCodes? server;
}

class MenuBarModel {
  const MenuBarModel._({
    required this.status,
    this.message,
    this.sections = const [],
    this.submenus = false,
    Map<String, _CopySource> sources = const {},
  }) : _sources = sources;

  final MenuBarStatus status;
  // 最上面的說明（尚未登入、已鎖定…）
  final String? message;
  final List<MenuBarSection> sections;
  // 每個群組收成一個子選單
  final bool submenus;
  final Map<String, _CopySource> _sources;

  // 有登入時才放「設定…」
  bool get showSettings => status == MenuBarStatus.ready || status == MenuBarStatus.locked;

  Iterable<MenuBarItem> get items => sections.expand((s) => s.items);

  /// 點了某一筆時要複製的驗證碼（同 App：複製目前這一組，不含空白）；不能複製時是 null
  String? codeFor(String id, int nowMs) {
    final source = _sources[id];
    if (source == null) return null;
    final snapshot = OtpSnapshot.at(account: source.account, secret: source.secret, server: source.server, nowMs: nowMs);
    return snapshot.state == OtpState.ready ? snapshot.code : null;
  }

  Map<String, Object?> toMap() => {
        'status': status.name,
        'message': message,
        'submenus': submenus,
        'showSettings': showSettings,
        'sections': [for (final section in sections) section.toMap()],
      };
}

/// 依登入、App 鎖定、群組與各群組的資料算出選單內容。
/// withCodes 為 false 時只放結構（選單關著時先送給原生端），驗證碼一律是佔位文字
MenuBarModel buildMenuBarModel({
  required bool signedIn,
  required bool profileReady,
  required bool appLocked,
  required bool hideCodes,
  required bool vaultUnlocked,
  required List<GroupSummary>? groups,
  String? groupsError,
  required Map<String, MenuGroupData> data,
  required int nowMs,
  bool withCodes = true,
}) {
  if (!signedIn) return const MenuBarModel._(status: MenuBarStatus.signedOut, message: '尚未登入');
  if (appLocked) return const MenuBarModel._(status: MenuBarStatus.locked, message: '已鎖定，打開 Securibit 解鎖');
  if (!profileReady) return const MenuBarModel._(status: MenuBarStatus.loading, message: '載入中');
  if (groups == null) {
    return MenuBarModel._(status: MenuBarStatus.loading, message: groupsError == null ? '載入中' : '載入群組失敗');
  }
  if (groups.isEmpty) return const MenuBarModel._(status: MenuBarStatus.ready, message: '沒有驗證碼');

  final sections = <MenuBarSection>[];
  final sources = <String, _CopySource>{};
  for (final group in groups) {
    // 加密群組只有擁有者解鎖後才看得到（同 CodesController.locked）
    if (group.encrypted && (!group.isOwner || !vaultUnlocked)) {
      sections.add(MenuBarSection(id: group.id, title: group.name, items: const [], note: '需要解鎖'));
      continue;
    }
    final entry = data[group.id];
    final accounts = entry?.accounts;
    if (accounts == null) {
      sections.add(MenuBarSection(
        id: group.id,
        title: group.name,
        items: const [],
        note: entry?.error == null ? '載入中' : '無法載入',
      ));
      continue;
    }
    // 釘選的排最上面，其餘維持儲存的順序（同 CodesController.ordered）
    final ordered = [...accounts.where((a) => a.pinned), ...accounts.where((a) => !a.pinned)];
    final items = <MenuBarItem>[];
    for (final account in ordered) {
      final id = '${group.id}/${account.id}';
      final secret = entry!.secrets[account.id];
      sources[id] = _CopySource(account, secret, entry.server);
      items.add(_item(id, account, secret, entry.server, nowMs: nowMs, hideCodes: hideCodes, withCodes: withCodes));
    }
    sections.add(MenuBarSection(
      id: group.id,
      title: group.name,
      items: items,
      note: items.isEmpty ? '沒有驗證碼' : null,
    ));
  }

  final total = sections.fold<int>(0, (sum, s) => sum + s.items.length);
  return MenuBarModel._(
    status: MenuBarStatus.ready,
    sections: sections,
    submenus: total > menuBarInlineLimit,
    sources: withCodes ? sources : const {},
  );
}

MenuBarItem _item(
  String id,
  GroupAccount account,
  SecretHandle? secret,
  ServerCodes? server, {
  required int nowMs,
  required bool hideCodes,
  required bool withCodes,
}) {
  final name = _truncate(account.name.trim().isEmpty ? '未命名' : account.name.trim());
  final placeholder = formatOtp('-' * account.digits);
  if (!withCodes) return MenuBarItem(id: id, name: name, code: placeholder, remaining: null, expiring: false, copyable: false);

  final snapshot = OtpSnapshot.at(account: account, secret: secret, server: server, nowMs: nowMs);
  final remaining = '${snapshot.secondsLeft} 秒';
  switch (snapshot.state) {
    case OtpState.pending:
      return MenuBarItem(id: id, name: name, code: placeholder, remaining: remaining, expiring: false, copyable: false);
    case OtpState.invalid:
      return MenuBarItem(id: id, name: name, code: '金鑰錯誤', remaining: null, expiring: false, copyable: false);
    case OtpState.ready:
      final code = snapshot.code!;
      // 隱藏驗證碼時只顯示圓點，點了一樣複製
      final shown = hideCodes ? formatOtp('•' * code.length) : formatOtp(code);
      return MenuBarItem(id: id, name: name, code: shown, remaining: remaining, expiring: snapshot.expiring, copyable: true);
  }
}

String _truncate(String name) {
  final chars = name.runes.toList();
  if (chars.length <= _nameLimit) return name;
  return '${String.fromCharCodes(chars.take(_nameLimit - 1))}…';
}

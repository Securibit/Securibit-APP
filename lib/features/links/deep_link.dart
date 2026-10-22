import '../../core/env.dart';
import '../../core/permissions.dart';
import '../codes/totp/import_text.dart';
import '../groups/group_models.dart';
import '../groups/manage/group_rules.dart';

/*
 * 點連結打開 App 時要做什麼（連結從系統經 app_links 進來，見 DeepLinkService）：
 * - https://2fa.bityo.tw/invite/<code>（網站網址見 Env.webUrl）、securibit://invite/<code> → 用邀請加入群組
 * - otpauth://totp/… → 新增驗證碼（同貼上 otpauth 連結）
 * - otpauth-migration://offline?data=… → 整批匯入（Google Authenticator 匯出）
 * - securibit://login-callback → Google 登入轉回來的，由 supabase_flutter 處理，這裡略過
 * 看不懂的連結回傳 InvalidLink，畫面上跳出中文錯誤訊息。
 */
sealed class DeepLink {
  const DeepLink();
}

/// 用邀請加入群組
class InviteLink extends DeepLink {
  const InviteLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is InviteLink && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'InviteLink($code)';
}

/// 新增驗證碼：text 是原本的連結（交給新增表單，跟貼上一樣解析）；bulk 是整批匯入（otpauth-migration）
class CodeLink extends DeepLink {
  const CodeLink(this.text, {required this.bulk});

  final String text;
  final bool bulk;

  @override
  bool operator ==(Object other) => other is CodeLink && other.text == text && other.bulk == bulk;

  @override
  int get hashCode => Object.hash(text, bulk);

  @override
  String toString() => 'CodeLink(${bulk ? 'bulk' : 'single'})';
}

/// 格式不對的連結：跳出錯誤對話框
class InvalidLink extends DeepLink {
  const InvalidLink(this.title, this.message);

  final String title;
  final String message;

  @override
  bool operator ==(Object other) => other is InvalidLink && other.title == title && other.message == message;

  @override
  int get hashCode => Object.hash(title, message);

  @override
  String toString() => 'InvalidLink($title：$message)';
}

const _inviteInvalid = InvalidLink('無法開啟邀請連結', '看不出這是邀請連結，請確認連結是否完整');
const _unknownLink = InvalidLink('無法開啟這個連結', 'Securibit 看不懂這個連結，請確認連結是否完整，或把 App 更新到最新版本');

// 網站的主機名稱（設定的網址和正式站都接受，Android 的 App Links 只認正式站）
Set<String> _webHosts(String webUrl) => {
      '2fa.bityo.tw',
      if (Uri.tryParse(webUrl)?.host case final host? when host.isNotEmpty) host.toLowerCase(),
    };

/// 解析連結；null 代表不用處理（登入轉回來的連結、空字串）
DeepLink? parseDeepLink(String raw, {String webUrl = Env.webUrl}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return _unknownLink;

  switch (uri.scheme.toLowerCase()) {
    case 'securibit':
      final host = uri.host.toLowerCase();
      // Google 登入（PKCE）轉回 App，supabase_flutter 自己會處理
      if (host == 'login-callback') return null;
      if (host != 'invite') return _unknownLink;
      return _invite(text);
    case 'https' || 'http':
      if (!_webHosts(webUrl).contains(uri.host.toLowerCase()) || !uri.path.startsWith('/invite/')) return _unknownLink;
      return _invite(text);
    case 'otpauth':
      return _code(text, bulk: false);
    case 'otpauth-migration':
      return _code(text, bulk: true);
  }
  return _unknownLink;
}

DeepLink _invite(String text) {
  final code = parseInviteCode(text);
  return code == null ? _inviteInvalid : InviteLink(code);
}

// 先解析一次：完全不能用就直接報錯，不用打開表單；能用的交給表單再解析（同貼上）
DeepLink _code(String text, {required bool bulk}) {
  final result = parseImportText(text);
  if (result.items.isEmpty) {
    final reason = result.errors.isEmpty ? '連結裡沒有可以新增的驗證碼' : result.errors.join('\n');
    return InvalidLink(bulk ? '無法匯入驗證碼' : '無法新增驗證碼', reason);
  }
  return CodeLink(text, bulk: bulk);
}

/// 可以從連結新增驗證碼的群組：要有「管理驗證碼」；加密的群組只有擁有者解鎖後才能新增
List<GroupSummary> groupsForNewCode(List<GroupSummary> groups, {required bool vaultUnlocked}) => [
      for (final group in groups)
        if (hasPermission(group.permissions, GroupPermission.manageCodes) && (!group.encrypted || (group.isOwner && vaultUnlocked))) group,
    ];

/// 沒有可以新增的群組時的說明
String noGroupForNewCodeReason(List<GroupSummary> groups) {
  final lockedVault = groups.any((g) => g.encrypted && g.isOwner && hasPermission(g.permissions, GroupPermission.manageCodes));
  return lockedVault ? '你只能在加密的群組新增驗證碼，請先解鎖加密再點一次連結' : '你在所有群組都沒有「管理驗證碼」權限，請聯絡群組管理員';
}

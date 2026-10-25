import 'admin_models.dart';

/*
 * 「能不能管理」的判斷（同網站 src/lib/permissions/hierarchy.ts），只用來決定按鈕要不要顯示；
 * 真正的檢查在資料庫的 RPC。
 * 規則（Discord）：群組擁有者（或全站管理）、全站擁有者不受限（還沒有全站擁有者時是「最高位身分組的持有者」）；
 * 其他人（包含全站 ADMINISTRATOR）只能管理 position 比自己最高身分組低的身分組與成員。沒有人能管理全站擁有者。
 */
class Actor {
  const Actor({required this.unrestricted, required this.topPosition});

  // 群組：擁有者 / 全站 ADMINISTRATOR / MANAGE_GROUPS；全站：全站擁有者（見 siteUnrestricted）
  final bool unrestricted;
  final int topPosition;
}

/// 全站：是不是「最高位身分組的持有者」（同 SQL 的 site_is_root）。
/// 自己有身分組，而且沒有任何「有人持有」的身分組比自己的最高身分組還高
bool isSiteRoot(int topPosition, List<Role> roles) =>
    topPosition > 0 && !roles.any((role) => !role.isDefault && role.memberCount > 0 && role.position > topPosition);

/// 全站：不受階層限制的人（同網站 siteUnrestricted、SQL 的 site_is_root）。有全站擁有者時只有擁有者；
/// 還沒有擁有者（ownerKnown 而且 ownerId 是 null）時才看「最高位身分組的持有者」。還沒讀到擁有者或身分組時當作受限
bool siteUnrestricted({
  required bool isOwner,
  required bool ownerKnown,
  required String? ownerId,
  required int topPosition,
  required List<Role>? roles,
}) =>
    isOwner || (ownerKnown && ownerId == null && roles != null && isSiteRoot(topPosition, roles));

/// 指派身分組時：新加入的身分組權限不能超過自己（actorPermissions 是已展開的權限）
bool canGrantRole(int actorPermissions, Role role) => (role.permissions & ~actorPermissions) == 0;

/// 能不能編輯 / 刪除 / 指派這個身分組（@everyone 只能改權限，指派另外排除）
bool canManageRole(Actor actor, Role role) => actor.unrestricted || role.isDefault || role.position < actor.topPosition;

/// 能不能管理這個成員（踢出、改身分組、改資料）
bool canManageMember(Actor actor, {required int topPosition, bool isOwner = false}) =>
    !isOwner && (actor.unrestricted || topPosition < actor.topPosition);

/// 使用者擁有的身分組中最高的 position（沒有就 0）
int topPositionOf(List<String> roleIds, List<Role> roles) =>
    roles.fold(0, (top, role) => roleIds.contains(role.id) && role.position > top ? role.position : top);

/// 依 position 由高到低排序（@everyone 在最後）
List<Role> sortRoles(List<Role> roles) {
  final list = [...roles];
  list.sort((a, b) {
    final byDefault = (a.isDefault ? 1 : 0) - (b.isDefault ? 1 : 0);
    return byDefault != 0 ? byDefault : b.position - a.position;
  });
  return list;
}

/// 上下移動身分組：只能移動管得到的，而且不能越過管不到的（相鄰的也要管得到）。
/// ordered 是不含 @everyone、由高到低的清單
bool canMoveRole(Actor actor, List<Role> ordered, int index, int offset) {
  final target = index + offset;
  if (index < 0 || index >= ordered.length || target < 0 || target >= ordered.length) return false;
  return canManageRole(actor, ordered[index]) && canManageRole(actor, ordered[target]);
}

/// 把第 index 個身分組和相鄰的交換，回傳新的 id 順序（由高到低）
List<String> moveRole(List<Role> ordered, int index, int offset) {
  final ids = ordered.map((role) => role.id).toList();
  final target = index + offset;
  final tmp = ids[index];
  ids[index] = ids[target];
  ids[target] = tmp;
  return ids;
}

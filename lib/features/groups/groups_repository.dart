import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import 'group_models.dart';

// 我所在的全部群組，照我自己排的順序（預設群組在我沒排過時排第一）
Future<Result<List<Map<String, dynamic>>>> loadMyGroupsRaw() => rpc('my_groups', asMapList);

List<GroupSummary> parseGroups(List<Map<String, dynamic>> rows) => rows.map(GroupSummary.fromJson).toList();

// 寄給我（email）的群組邀請
Future<Result<List<Invitation>>> loadMyInvitations() =>
    rpc('my_invitations', (data) => asMapList(data).map(Invitation.fromJson).toList());

// 接受時回傳群組 id，拒絕回傳 null
Future<Result<String?>> respondInvitation(String inviteId, {required bool accept}) =>
    rpc('respond_invitation', (data) => data is String ? data : null, {'invite_id': inviteId, 'accept': accept});

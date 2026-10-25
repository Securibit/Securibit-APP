import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import 'admin_models.dart';
import 'admin_repository.dart' as repo;
import 'hierarchy.dart';
import 'permission_defs.dart';

/*
 * 自己的全站權限（同網站 AuthProvider 的 me_permissions）：決定要不要顯示「後台」與後台裡的每個區塊。
 * 全 App 共用一份；登入的使用者換了就重新讀，進後台、改了身分組後也會重新讀。
 * 讀取失敗（離線、資料庫還沒有全站權限功能）時保留原本的值，第一次就失敗就當作沒有任何全站權限。
 */
class SiteAccessController extends ChangeNotifier {
  SiteAccessController();

  static final shared = SiteAccessController();

  String? _uid;
  SiteAccess access = SiteAccess.none;
  bool loaded = false;
  int _seq = 0;
  // 全站擁有者的 id（site_owner()，要「進入後台」）；ownerLoaded 是 false 時還不知道
  String? ownerId;
  bool ownerLoaded = false;

  String? get uid => _uid;

  int get permissions => access.permissions;
  int get topPosition => access.topPosition;

  bool can(int bit) => hasBit(access.permissions, bit);

  bool get canViewAdmin => can(SitePermission.viewAdmin);

  bool get isOwner => access.isOwner;

  /// 這個人是不是全站擁有者（還沒讀到時當作不是）
  bool isOwnerId(String userId) => ownerLoaded && ownerId != null && ownerId == userId;

  /// 我在全站是不是不受階層限制；roles 是全站身分組（還沒讀到是 null）
  bool unrestricted(List<Role>? roles) => siteUnrestricted(
        isOwner: access.isOwner,
        ownerKnown: ownerLoaded,
        ownerId: ownerId,
        topPosition: access.topPosition,
        roles: roles,
      );

  /// 換了登入的使用者（登出時是 null）
  void attach(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    access = SiteAccess.none;
    loaded = false;
    ownerId = null;
    ownerLoaded = false;
    notifyListeners();
    if (uid != null) unawaited(reload());
  }

  Future<void> reload() async {
    final uid = _uid;
    if (uid == null) return;
    final seq = ++_seq;
    final result = await repo.loadSiteAccess();
    if (uid != _uid || seq != _seq) return;
    if (result case Ok(:final data)) {
      access = data;
      loaded = true;
      notifyListeners();
      if (data.isOwner) {
        ownerId = uid;
        ownerLoaded = true;
        notifyListeners();
      } else if (canViewAdmin) {
        await _loadOwner(uid, seq);
      }
    }
  }

  Future<void> _loadOwner(String uid, int seq) async {
    final result = await repo.loadSiteOwner();
    if (uid != _uid || seq != _seq) return;
    if (result case Ok(:final data)) {
      ownerId = data;
      ownerLoaded = true;
      notifyListeners();
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../cache/offline_cache.dart';
import '../groups/group_models.dart';
import '../vault/vault_controller.dart';
import 'codes_controller.dart';

/// 為選中的群組建立 CodesController；換群組、解鎖或鎖定時整個換新的
class CodesScope extends StatelessWidget {
  const CodesScope({super.key, required this.group, required this.child});

  final GroupSummary group;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthController, String?>((a) => a.profile?.uid) ?? '';
    final keyId = context.select<VaultController, int?>((v) => v.keyId);
    final vaultKeyId = group.encrypted ? keyId : null;
    return ChangeNotifierProvider<CodesController>(
      key: ValueKey('${group.id}|${group.permissions}|${group.encrypted}|$vaultKeyId'),
      create: (context) => CodesController(
        group: group,
        uid: uid,
        vaultKeyId: vaultKeyId,
        cache: context.read<OfflineCache>(),
      ),
      child: child,
    );
  }
}

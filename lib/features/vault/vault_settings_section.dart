import 'package:flutter/material.dart';

/*
 * 加密密碼的設定區塊與群組加密開關（工作包 E 實作）
 */

/// 設定頁的「加密」區塊：設定、變更、停用、重設加密密碼
class VaultSettingsSection extends StatelessWidget {
  const VaultSettingsSection({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 開關群組加密；成功回傳 null，失敗回傳錯誤訊息
Future<String?> setGroupEncryption(BuildContext context, String groupId, bool encrypted) async => '尚未實作';

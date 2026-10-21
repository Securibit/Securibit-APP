import 'package:flutter/material.dart';

import '../code_models.dart';
import '../codes_controller.dart';

/*
 * 驗證碼匯出的入口（工作包 B 實作）
 */

/// 匯出目前群組的全部驗證碼（Google Authenticator 分批 QR 或文字備份）
Future<void> showExportAll(BuildContext context, CodesController controller) async {}

/// 把一筆驗證碼匯出成 QR
Future<void> showExportItem(BuildContext context, CodesController controller, GroupAccount account) async {}

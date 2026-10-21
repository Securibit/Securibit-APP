import 'package:flutter/material.dart';

import '../../../core/widgets/feedback.dart';
import '../code_models.dart';
import '../codes_controller.dart';
import 'export_data.dart';
import 'export_pages.dart';
import 'transfer_widgets.dart';

/*
 * 驗證碼匯出的入口（清單選單呼叫）。
 * 只有我有「查看金鑰」、金鑰也解得開的項目能匯出；金鑰在按下匯出時才從 Rust 取出來。
 */

/// 匯出目前群組的全部驗證碼（Google Authenticator 分批 QR 或文字備份）
Future<void> showExportAll(BuildContext context, CodesController controller) async {
  if (controller.locked) {
    await showErrorDialog(context, '無法匯出', '這個群組已加密，請先解鎖');
    return;
  }
  final (:items, :missing) = exportableItems(controller);
  if (items.isEmpty) {
    await showErrorDialog(
      context,
      '沒有可以匯出的驗證碼',
      missing > 0 ? '你在這個群組沒有任何驗證碼的「查看金鑰」權限，無法匯出' : '這個群組還沒有驗證碼',
    );
    return;
  }
  await showTransferPage<void>(context, ExportAllPage(items: items, missing: missing));
}

/// 把一筆驗證碼匯出成 QR
Future<void> showExportItem(BuildContext context, CodesController controller, GroupAccount account) async {
  final handle = controller.secretOf(account);
  final secret = handle != null && handle.valid ? handle.reveal() : null;
  if (secret == null || secret.isEmpty) {
    await showErrorDialog(
      context,
      '無法匯出',
      handle == null ? '你沒有這筆驗證碼的「查看金鑰」權限，無法匯出' : '這筆驗證碼的金鑰錯誤，無法匯出',
    );
    return;
  }
  await showTransferPage<void>(context, ExportItemPage(item: exportInput(account, secret)));
}

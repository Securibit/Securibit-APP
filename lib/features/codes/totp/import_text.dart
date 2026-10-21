import '../../../core/result.dart';
import 'migration.dart';
import 'otpauth.dart';
import 'totp_params.dart';

/// 解析的結果：可以匯入的驗證碼，與無法匯入的行和原因（HOTP、格式錯誤等）
class ImportTextResult {
  ImportTextResult({List<TotpInput>? items, List<String>? errors, this.batch})
      : items = items ?? [],
        errors = errors ?? [];

  final List<TotpInput> items;
  final List<String> errors;
  // Google Authenticator 分批匯出時，這是第幾批
  MigrationBatch? batch;

  /// 只有一筆而且沒有任何問題：直接帶入表單，不用開整批匯入
  bool get isSingle => items.length == 1 && errors.isEmpty && batch == null;
}

/// 解析貼上的文字、QR Code 內容或備份檔（同網站 src/lib/totp/importText.ts）：
/// 每行一個 otpauth:// 或 otpauth-migration:// 連結，空行與 # 開頭的註解略過
ImportTextResult parseImportText(String text) {
  final result = ImportTextResult();
  final lines = text.split(RegExp(r'\r?\n')).map((line) => line.trim()).where((line) => line.isNotEmpty && !line.startsWith('#')).toList();

  for (final line in lines) {
    if (line.startsWith('otpauth-migration://')) {
      switch (parseMigrationUri(line)) {
        case Ok(:final data):
          result.items.addAll(data.items);
          if (data.skipped > 0) result.errors.add('略過 ${data.skipped} 筆 HOTP（計數型）驗證碼');
          result.batch = data.batch;
        case Err(:final message):
          result.errors.add(message);
      }
      continue;
    }

    switch (parseOtpauthUri(line)) {
      case Ok(:final data):
        result.items.add(data);
      case Err(:final message):
        result.errors.add(lines.length > 1 ? '${line.length > 40 ? '${line.substring(0, 40)}…' : line}：$message' : message);
    }
  }

  if (lines.isEmpty) result.errors.add('沒有可匯入的內容');
  return result;
}

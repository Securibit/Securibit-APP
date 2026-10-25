import '../../../core/result.dart';
import 'migration.dart';
import 'otpauth.dart';
import 'totp_params.dart';

/// 無法讀取的一行：line 是原始文字的行號（1 起算）
class ImportLineError {
  const ImportLineError(this.line, this.reason);

  final int line;
  final String reason;

  @override
  String toString() => '第 $line 行：$reason';

  @override
  bool operator ==(Object other) => other is ImportLineError && other.line == line && other.reason == reason;

  @override
  int get hashCode => Object.hash(line, reason);
}

/// 解析的結果：可以匯入的驗證碼、無法讀取的行與原因（一行壞掉不影響其他行），
/// 以及讀得到但有部分略過的說明（例如匯出 QR Code 裡的 HOTP、讀不到的檔案）
class ImportTextResult {
  ImportTextResult({List<TotpInput>? items, List<ImportLineError>? errors, List<String>? notes, this.batch})
      : items = items ?? [],
        errors = errors ?? [],
        notes = notes ?? [];

  final List<TotpInput> items;
  final List<ImportLineError> errors;
  final List<String> notes;
  // Google Authenticator 分批匯出時，這是第幾批
  MigrationBatch? batch;

  /// 只有一筆而且沒有任何問題：直接帶入表單，不用開整批匯入
  bool get isSingle => items.length == 1 && errors.isEmpty && notes.isEmpty && batch == null;

  /// 什麼都讀不到時的說明（只有一行時不用行號；同網站 QrImport）
  String get failureText {
    if (errors.length == 1 && notes.isEmpty) return errors.single.reason;
    return [errors.isNotEmpty ? formatImportErrors(errors) : '沒有可匯入的內容', ...notes].join('\n');
  }
}

/// 解析貼上的文字、QR Code 內容或備份檔（同網站 src/lib/totp/importText.ts）：
/// 每行一個 otpauth:// 或 otpauth-migration:// 連結，空行與 # 開頭的註解略過。
/// 某一行解析失敗（甚至丟出例外）只記下行號與原因，繼續讀下一行
ImportTextResult parseImportText(String text) {
  final result = ImportTextResult();
  final lines = text.split(RegExp(r'\r?\n'));

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    final number = i + 1;
    if (line.isEmpty || line.startsWith('#')) continue;
    try {
      if (line.startsWith('otpauth-migration://')) {
        switch (parseMigrationUri(line)) {
          case Ok(:final data):
            result.items.addAll(data.items);
            if (data.skipped > 0) result.notes.add('第 $number 行略過 ${data.skipped} 筆 HOTP（計數型）驗證碼');
            result.batch = data.batch;
          case Err(:final message):
            result.errors.add(ImportLineError(number, message));
        }
        continue;
      }
      switch (parseOtpauthUri(line)) {
        case Ok(:final data):
          result.items.add(data);
        case Err(:final message):
          result.errors.add(ImportLineError(number, message));
      }
    } catch (_) {
      result.errors.add(ImportLineError(number, '無法讀取這一行'));
    }
  }
  return result;
}

/// 「第 3 行：原因」一行一筆，給錯誤對話框與匯入畫面顯示
String formatImportErrors(List<ImportLineError> errors) => errors.join('\n');

/// 匯入後的摘要
String importSummary(int imported, List<ImportLineError> errors) =>
    errors.isNotEmpty ? '已匯入 $imported 筆，${errors.length} 行無法讀取' : '已匯入 $imported 筆驗證碼';

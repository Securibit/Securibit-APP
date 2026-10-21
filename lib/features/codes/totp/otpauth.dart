import '../../../core/result.dart';
import '../../../src/rust/api/totp.dart' as core;
import 'categories.dart';
import 'totp_params.dart';

/*
 * otpauth:// 連結（Key URI Format，各服務綁定用的 QR Code 內容就是這個），同網站 src/lib/totp/otpauth.ts：
 * otpauth://totp/Issuer:account?secret=...&issuer=...&digits=6&period=30&algorithm=SHA1
 * 解析與產生在 Rust 安全核心（rust/core/src/otpauth.rs），錯誤訊息同網站；類別的整理在這裡做。
 */

Result<TotpInput> parseOtpauthUri(String text) {
  final parsed = core.parseOtpauth(text: text);
  final link = parsed.link;
  if (link == null) return Err(parsed.error ?? '不是有效的 otpauth:// 連結');
  return Ok(TotpInput(
    name: link.name,
    secret: link.secret,
    // category 不是標準參數，是網站匯出備份時加上的（多個類別用「,」串起來），其他 App 會忽略
    category: normalizeCategories(link.category),
    digits: link.digits,
    period: link.period,
    algorithm: TotpAlgorithm.fromLabel(link.algorithm),
  ));
}

/// 產生 otpauth:// 連結（可轉成 QR Code 給其他驗證器 App 掃）
String buildOtpauthUri(TotpInput item) => core.buildOtpauth(
      link: core.OtpauthLink(
        name: item.name,
        secret: item.secret,
        category: item.category,
        digits: item.digits,
        period: item.period,
        algorithm: item.algorithm.label,
      ),
    );

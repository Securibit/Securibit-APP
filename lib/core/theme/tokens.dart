import 'package:flutter/material.dart';

/*
 * 設計代幣，跟網站 src/styles/globals.css 的 Apple 配方一致：
 * 純白底（深色 #1C1C1E，不用純黑）、#F5F5F7 軟底、墨色 #1D1D1F、灰字、髮絲線；
 * 幣友綠 #17FFAC 只給主要按鈕底色，亮色底上的動作文字用加深的 #0B9F6B。
 * 圓角 12 / 18 / 22，幾乎沒有陰影，留白當層次。
 */
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.surface1,
    required this.surface2,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.brand,
    required this.alarm,
  });

  // 底色
  final Color surface;
  // 軟底：輸入框、藥丸、側欄
  final Color surface1;
  // 再深一階：側欄選中的列
  final Color surface2;
  // 文字 / 灰字
  final Color ink;
  final Color inkMuted;
  // 髮絲線
  final Color line;
  // 綠：動作文字（亮色加深）
  final Color accent;
  // 主要按鈕上的字（深綠）
  final Color accentInk;
  // 主要按鈕底色
  final Color brand;
  // 紅：快到期的驗證碼、危險操作
  final Color alarm;

  static const light = AppColors(
    surface: Color(0xFFFFFFFF),
    surface1: Color(0xFFF5F5F7),
    surface2: Color(0xFFE8E8ED),
    ink: Color(0xFF1D1D1F),
    inkMuted: Color(0xFF6E6E73),
    line: Color(0xFFD2D2D7),
    accent: Color(0xFF0B9F6B),
    accentInk: Color(0xFF04261A),
    brand: Color(0xFF17FFAC),
    alarm: Color(0xFFE30000),
  );

  static const dark = AppColors(
    surface: Color(0xFF1C1C1E),
    surface1: Color(0xFF2A2A2D),
    surface2: Color(0xFF3A3A3E),
    ink: Color(0xFFF5F5F7),
    inkMuted: Color(0xFFA8A8AE),
    line: Color(0xFF424246),
    accent: Color(0xFF17FFAC),
    accentInk: Color(0xFF04261A),
    brand: Color(0xFF17FFAC),
    alarm: Color(0xFFFF453A),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      alarm: Color.lerp(alarm, other.alarm, t)!,
    );
  }
}

// 圓角：小（輸入框、藥丸列）、中（清單、卡片）、大（對話框、底部面板）
class AppRadius {
  AppRadius._();

  static const small = 12.0;
  static const medium = 18.0;
  static const large = 22.0;
}

// 字級：內文 17、次要 15、最小 13，不再更小
class AppText {
  AppText._();

  static const title = 22.0;
  static const body = 17.0;
  static const secondary = 15.0;
  static const caption = 13.0;
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

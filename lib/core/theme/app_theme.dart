import 'package:flutter/material.dart';

import '../platform.dart';
import 'tokens.dart';

// Material 元件套上網站的色票；字體用系統字（Apple 上就是 SF / 蘋方，Linux 另外指定中文字型的備援，見 AppPlatform）
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  // 按鈕、輸入框等元件的文字樣式不會繼承 textTheme，要各自帶上字型備援
  final fallback = AppPlatform.fontFamilyFallback;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: brightness == Brightness.dark ? c.accentInk : Colors.white,
    secondary: c.brand,
    onSecondary: c.accentInk,
    error: c.alarm,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.inkMuted,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface1,
    surfaceContainer: c.surface1,
    surfaceContainerHigh: c.surface1,
    surfaceContainerHighest: c.surface2,
    outline: c.line,
    outlineVariant: c.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: c.surface,
    splashFactory: NoSplash.splashFactory,
    fontFamilyFallback: fallback,
    extensions: [c],
  );

  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: AppText.title, fontWeight: FontWeight.w700, color: c.ink),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: AppText.body, fontWeight: FontWeight.w600, color: c.ink),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: AppText.body, color: c.ink),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: AppText.secondary, color: c.ink),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: AppText.caption, color: c.inkMuted),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: AppText.body, fontWeight: FontWeight.w600),
      );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.small),
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    textTheme: text,
    dividerTheme: DividerThemeData(color: c.line.withValues(alpha: 0.6), thickness: 0.5, space: 0.5),
    iconTheme: IconThemeData(color: c.inkMuted, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: AppText.body, fontWeight: FontWeight.w600),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.surface1,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.large)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.accent.withValues(alpha: 0.6), width: 1.5)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.alarm, width: 1)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.alarm, width: 1.5)),
      hintStyle: TextStyle(color: c.inkMuted, fontSize: AppText.body, fontFamilyFallback: fallback),
      helperStyle: TextStyle(color: c.inkMuted, fontSize: AppText.caption, fontFamilyFallback: fallback),
      errorStyle: TextStyle(color: c.alarm, fontSize: AppText.caption, fontFamilyFallback: fallback),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.accentInk,
        disabledBackgroundColor: c.surface2,
        disabledForegroundColor: c.inkMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
        textStyle: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, fontFamilyFallback: fallback),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: const Size(44, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
        textStyle: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, fontFamilyFallback: fallback),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: c.line),
        shape: const StadiumBorder(),
        textStyle: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, fontFamilyFallback: fallback),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      contentTextStyle: text.bodyLarge?.copyWith(color: c.inkMuted, fontSize: AppText.secondary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.surface, fontSize: AppText.secondary, fontWeight: FontWeight.w600, fontFamilyFallback: fallback),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        side: BorderSide(color: c.line.withValues(alpha: 0.6), width: 0.5),
      ),
      textStyle: TextStyle(color: c.ink, fontSize: AppText.body, fontFamilyFallback: fallback),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surface2),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.25),
      selectionHandleColor: c.accent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large))),
    ),
  );
}

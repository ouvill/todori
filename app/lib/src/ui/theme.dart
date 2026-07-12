import 'package:flutter/material.dart';

/// Shared spacing rhythm for production UI.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Radius is reserved for controls whose shape communicates interaction.
/// Rows, sections, and task streams intentionally do not use these values.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 12;
}

/// Binding production palette from UI Spec section 0.
abstract final class AppColors {
  static const canvas = Color(0xFFF8F5EC);
  static const ink = Color(0xFF182019);
  static const muted = Color(0xFF73786F);
  static const forest = Color(0xFF1D6048);
  static const sage = Color(0xFFBFD7C8);
  static const subtleSage = Color(0xFFE9EFE8);
  static const hairline = Color(0xFFD9DDD3);
  static const coral = Color(0xFFC96357);
  static const amber = Color(0xFFC08B3E);
}

/// Future Focus-only inverse surface. These tokens are deliberately not wired
/// into the normal application theme: Home, Lists, Detail, Account, and sheets
/// remain on the light canvas regardless of the platform brightness.
abstract final class AppFocusColors {
  static const surface = Color(0xFF183E31);
  static const text = Color(0xFFF5F0E4);
  static const muted = Color(0xFFAFC8BA);
  static const hairline = Color(0xFF416A59);
  static const error = Color(0xFFF3A398);
}

/// Inter does not bundle CJK glyphs, so production explicitly falls back to a
/// platform sans face. No serif fallback is part of the production hierarchy.
const _cjkFontFamilyFallback = <String>[
  'Hiragino Sans',
  'Noto Sans CJK JP',
  'Noto Sans JP',
];

/// Builds Todori's normal, light-only product theme.
///
/// [brightness] remains in the signature for existing callers. Normal screens
/// intentionally stay on the warm light canvas; Focus owns its future inverse
/// surface instead of inheriting a platform-wide dark theme.
ThemeData buildTodoriTheme(Brightness brightness) {
  const colorScheme = ColorScheme.light(
    primary: AppColors.forest,
    onPrimary: Color(0xFFF8F5EC),
    primaryContainer: AppColors.subtleSage,
    onPrimaryContainer: AppColors.ink,
    secondary: Color(0xFF526A5D),
    onSecondary: Color(0xFFF8F5EC),
    secondaryContainer: Color(0xFFECEFE8),
    onSecondaryContainer: AppColors.ink,
    error: AppColors.coral,
    onError: Color(0xFFF8F5EC),
    surface: AppColors.canvas,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: Color(0xFFAEB4AA),
    outlineVariant: AppColors.hairline,
    surfaceContainerLowest: AppColors.canvas,
    surfaceContainerLow: AppColors.canvas,
    surfaceContainer: AppColors.canvas,
    surfaceContainerHigh: AppColors.subtleSage,
    surfaceContainerHighest: Color(0xFFE2E8E0),
    shadow: Colors.transparent,
    scrim: Color(0x66182019),
  );

  final base = ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    fontFamilyFallback: _cjkFontFamilyFallback,
  );
  final textTheme = base.textTheme.copyWith(
    displayLarge: base.textTheme.displayLarge?.copyWith(
      color: AppColors.ink,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      letterSpacing: -1.4,
      height: 1.05,
    ),
    displayMedium: base.textTheme.displayMedium?.copyWith(
      color: AppColors.ink,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      letterSpacing: -1.1,
      height: 1.08,
    ),
    displaySmall: base.textTheme.displaySmall?.copyWith(
      color: AppColors.ink,
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      height: 1.1,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.15,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.35,
      height: 1.2,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.28,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      color: AppColors.ink,
      height: 1.45,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      color: AppColors.ink,
      height: 1.45,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      color: AppColors.muted,
      height: 1.4,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
    ),
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
  );
  final sheetShape = RoundedRectangleBorder(
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadius.lg),
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    splashColor: AppColors.forest.withValues(alpha: 0.08),
    highlightColor: AppColors.forest.withValues(alpha: 0.06),
    hoverColor: AppColors.forest.withValues(alpha: 0.04),
    focusColor: AppColors.forest.withValues(alpha: 0.08),
    shadowColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      space: 1,
      thickness: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.canvas,
      modalBackgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: sheetShape,
      dragHandleColor: AppColors.hairline,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.forest,
      foregroundColor: Color(0xFFF8F5EC),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 58,
      elevation: 0,
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 20,
          color: states.contains(WidgetState.selected)
              ? AppColors.forest
              : AppColors.muted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return textTheme.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? AppColors.forest
              : AppColors.muted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          letterSpacing: 0.1,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.forest, width: 1.25),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.coral),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.coral, width: 1.25),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.ink,
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      shape: RoundedRectangleBorder(),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.transparent,
      selectedColor: AppColors.subtleSage,
      disabledColor: Colors.transparent,
      side: const BorderSide(color: AppColors.hairline),
      labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.ink),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
        color: AppColors.forest,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      shape: controlShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.hairline),
      ),
      titleTextStyle: textTheme.titleLarge,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.canvas,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: const BorderSide(color: AppColors.hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF24382D),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: const Color(0xFFF8F5EC),
      ),
      actionTextColor: const Color(0xFFF6E7B7),
      elevation: 0,
      shape: controlShape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        elevation: 0,
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        side: const BorderSide(color: AppColors.hairline),
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        shape: controlShape,
      ),
    ),
  );
}

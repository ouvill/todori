import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

const _seedColor = Color(0xFF285E46);
const _lightSurface = Color(0xFFFFFDF8);
const _lightSurfaceContainer = Color(0xFFF8F7F2);
const _lightSurfaceContainerHigh = Color(0xFFEDF2EA);
const _lightCoral = Color(0xFFE8755A);
const _darkSurface = Color(0xFF141915);
const _darkSurfaceContainer = Color(0xFF101411);
const _darkSurfaceContainerHigh = Color(0xFF202820);

/// The bundled brand fonts (`assets/fonts/Newsreader`, `assets/fonts/Inter`)
/// only ship Latin glyphs, per the 2026-07-06 typography ruling (see
/// `docs/design/ui-spec.md` 裁定済み事項) that Japanese continues to render
/// through the platform's own fallback rather than bundling a new Japanese
/// font. This list makes that fallback explicit rather than implicit: real
/// devices normally resolve missing glyphs to a system CJK font
/// automatically even without this, but declaring it here is harmless when
/// the family isn't present (Flutter simply skips it) and it is also what
/// lets the `visual_qa` screenshot harness -- which runs in an isolated
/// `flutter test` environment with no automatic system font fallback --
/// render Japanese seed data by registering a real Hiragino font under the
/// `Hiragino Sans` family name (see
/// `test/visual_qa/visual_qa_screenshots_test.dart`).
///
/// This is the sans-serif fallback used for the `Inter` base font family
/// (every text role except [displayMedium]'s Today heading).
const _cjkFontFamilyFallback = <String>[
  'Hiragino Sans',
  'Noto Sans CJK JP',
  'Noto Sans JP',
];

/// Japanese fallback for the `Newsreader` display serif used by the
/// `displayMedium` text style (the Today heading) only. Apple platforms
/// resolve this to the serif ヒラギノ明朝 ProN; OSes without a bundled
/// Japanese serif (e.g. stock Android) fall through to their own default
/// body font, which is an accepted degradation per the 2026-07-06
/// typography ruling.
const _serifCjkFontFamilyFallback = <String>[
  'Hiragino Mincho ProN',
  'Noto Serif CJK JP',
  'Noto Serif JP',
];

ThemeData buildTodoriTheme(Brightness brightness) {
  final generatedScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final colorScheme = generatedScheme.copyWith(
    primary: brightness == Brightness.light
        ? const Color(0xFF285E46)
        : const Color(0xFF9CD8B3),
    onPrimary: brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF0D1C13),
    primaryContainer: brightness == Brightness.light
        ? const Color(0xFFE3EEE4)
        : const Color(0xFF1B4A31),
    onPrimaryContainer: brightness == Brightness.light
        ? const Color(0xFF163B28)
        : const Color(0xFFDDF3E2),
    secondaryContainer: brightness == Brightness.light
        ? const Color(0xFFF0F0E8)
        : const Color(0xFF2B372E),
    surface: brightness == Brightness.light ? _lightSurface : _darkSurface,
    surfaceContainer: brightness == Brightness.light
        ? _lightSurfaceContainer
        : _darkSurfaceContainer,
    surfaceContainerHighest: brightness == Brightness.light
        ? _lightSurfaceContainerHigh
        : _darkSurfaceContainerHigh,
    outlineVariant: brightness == Brightness.light
        ? const Color(0xFFDDE4DA)
        : const Color(0xFF3A493D),
    error: brightness == Brightness.light
        ? _lightCoral
        : const Color(0xFFFFB4A8),
  );
  final base = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    // Inter is the UI body typeface (see `assets/fonts/Inter`) and covers
    // every text role except `displayMedium` (the Home date and first-run
    // onboarding headings, overridden below to Newsreader).
    // `fontFamilyFallback` applies to every style
    // derived from this `ThemeData` (since `copyWith` preserves it unless a
    // style explicitly sets its own), covering Japanese glyphs Inter does
    // not ship.
    fontFamily: 'Inter',
    fontFamilyFallback: _cjkFontFamilyFallback,
  );

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surfaceContainer,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colorScheme.surfaceContainer,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      focusElevation: 1,
      hoverElevation: 1,
      highlightElevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return base.textTheme.labelSmall?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      filled: false,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colorScheme.surfaceContainer,
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.72),
      ),
      labelStyle: base.textTheme.labelMedium?.copyWith(
        color: colorScheme.primary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    ),
    textTheme: base.textTheme.copyWith(
      // Newsreader (brand display serif) is scoped to `displayMedium` only
      // -- Home date and first-run onboarding headings -- per the 2026-07-06
      // typography ruling and 2026-07-10 onboarding extension
      // ("28px級以上かつ1画面1〜2箇所" rule, `docs/design/ui-spec.md`
      // セクション2). Its Japanese fallback is the system serif
      // (`_serifCjkFontFamilyFallback`), distinct from the sans-serif
      // fallback the rest of the app inherits from `ThemeData.fontFamily`.
      // Every other role stays on the base Inter typeface.
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontFamily: 'Newsreader',
        fontFamilyFallback: _serifCjkFontFamilyFallback,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.28,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFF24382D)
          : colorScheme.surfaceContainerHighest,
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: brightness == Brightness.light
            ? Colors.white
            : colorScheme.onSurface,
      ),
      actionTextColor: brightness == Brightness.light
          ? const Color(0xFFF6E7B7)
          : const Color(0xFFFFDFA8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
  );
}

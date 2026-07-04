import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

const _seedColor = Color(0xFF2F6F4E);
const _lightSurface = Color(0xFFFFFCF7);
const _lightSurfaceContainer = Color(0xFFF2F7EF);
const _lightSurfaceContainerHigh = Color(0xFFE8F0E5);
const _lightCoral = Color(0xFFE8755A);
const _darkSurface = Color(0xFF101510);
const _darkSurfaceContainer = Color(0xFF182019);
const _darkSurfaceContainerHigh = Color(0xFF223025);

/// The bundled brand fonts (`assets/fonts/Lora`, `assets/fonts/Inter`) only
/// ship Latin glyphs, per task-30's "no new Japanese font" decision --
/// Japanese continues to render through the platform's own fallback. This
/// list makes that fallback explicit rather than implicit: real devices
/// normally resolve missing glyphs to a system CJK font automatically even
/// without this, but declaring it here is harmless when the family isn't
/// present (Flutter simply skips it) and it is also what lets the
/// `visual_qa` screenshot harness -- which runs in an isolated `flutter
/// test` environment with no automatic system font fallback -- render
/// Japanese seed data by registering a real Hiragino font under the
/// `Hiragino Sans` family name (see
/// `test/visual_qa/visual_qa_screenshots_test.dart`).
const _cjkFontFamilyFallback = <String>[
  'Hiragino Sans',
  'Noto Sans CJK JP',
  'Noto Sans JP',
];

ThemeData buildTodoriTheme(Brightness brightness) {
  final generatedScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final colorScheme = generatedScheme.copyWith(
    primary: brightness == Brightness.light
        ? const Color(0xFF2F6F4E)
        : const Color(0xFF9CD8B3),
    onPrimary: brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF0D1C13),
    primaryContainer: brightness == Brightness.light
        ? const Color(0xFFDDEBDD)
        : const Color(0xFF1B4A31),
    onPrimaryContainer: brightness == Brightness.light
        ? const Color(0xFF163B28)
        : const Color(0xFFDDF3E2),
    secondaryContainer: brightness == Brightness.light
        ? const Color(0xFFE8EFE5)
        : const Color(0xFF2B372E),
    surface: brightness == Brightness.light ? _lightSurface : _darkSurface,
    surfaceContainer: brightness == Brightness.light
        ? _lightSurfaceContainer
        : _darkSurfaceContainer,
    surfaceContainerHighest: brightness == Brightness.light
        ? _lightSurfaceContainerHigh
        : _darkSurfaceContainerHigh,
    outlineVariant: brightness == Brightness.light
        ? const Color(0xFFD9E3D6)
        : const Color(0xFF3A493D),
    error: brightness == Brightness.light
        ? _lightCoral
        : const Color(0xFFFFB4A8),
  );
  final base = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    // Inter is the UI body typeface (see `assets/fonts/Inter`); Lora is
    // layered on top for display/headline styles and the AppBar title
    // below. `fontFamilyFallback` applies to every style derived from this
    // `ThemeData` (including the Lora overrides below, since `copyWith`
    // preserves it), covering Japanese glyphs neither brand font ships.
    fontFamily: 'Inter',
    fontFamilyFallback: _cjkFontFamilyFallback,
  );

  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surfaceContainer,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colorScheme.surfaceContainer,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontFamily: 'Lora',
        color: colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
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
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: colorScheme.surface,
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
      // Lora (brand display serif) covers Today/screen/section headings;
      // everything else stays on the base Inter body typeface.
      displayLarge: base.textTheme.displayLarge?.copyWith(fontFamily: 'Lora'),
      displayMedium: base.textTheme.displayMedium?.copyWith(fontFamily: 'Lora'),
      displaySmall: base.textTheme.displaySmall?.copyWith(fontFamily: 'Lora'),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: 'Lora',
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontFamily: 'Lora',
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

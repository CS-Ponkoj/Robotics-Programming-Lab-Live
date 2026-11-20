import 'package:flutter/material.dart';
import 'package:iuse_demo/state/feedback_mode.dart';

/// One account's brand colours: the main colour, darker shades for headers,
/// and a light tint for selected surfaces.
class BrandPalette {
  const BrandPalette({
    required this.brand,
    required this.dark,
    required this.deep,
    required this.tint,
  });

  final Color brand;
  final Color dark;
  final Color deep;
  final Color tint;
}

/// Instructors keep the original teal; each student feedback mode has its
/// own colour. None uses the violet reserved for AI-generated feedback.
abstract final class BrandPalettes {
  static const instructor = BrandPalette(
    brand: Color(0xFF19778C),
    dark: Color(0xFF0F4C5C),
    deep: Color(0xFF0A3742),
    tint: Color(0xFFDDEFF2),
  );
  static const traditional = BrandPalette(
    brand: Color(0xFF2F5FA7),
    dark: Color(0xFF1F4277),
    deep: Color(0xFF132A4D),
    tint: Color(0xFFDFE8F5),
  );
  static const tdd = BrandPalette(
    brand: Color(0xFF2E7D4F),
    dark: Color(0xFF1E5A37),
    deep: Color(0xFF123B24),
    tint: Color(0xFFDFF0E5),
  );
  // Gold: the lightest shade that keeps white text at 4.5:1 contrast.
  static const tddAi = BrandPalette(
    brand: Color(0xFF96700A),
    dark: Color(0xFF7A5B05),
    deep: Color(0xFF4F3B00),
    tint: Color(0xFFFBF0D2),
  );

  /// Signed out and instructors use the original teal.
  static BrandPalette forAccount({
    required bool signedInStudent,
    required FeedbackMode mode,
  }) {
    if (!signedInStudent) return instructor;
    return switch (mode) {
      FeedbackMode.traditional => traditional,
      FeedbackMode.tdd => tdd,
      FeedbackMode.tddAi => tddAi,
    };
  }
}

abstract final class AppColors {
  static BrandPalette _palette = BrandPalettes.instructor;

  /// Switches the brand colours; rebuild the app theme afterwards.
  static void usePalette(BrandPalette palette) => _palette = palette;

  static Color get brandDark => _palette.dark;
  static Color get brand => _palette.brand;
  static Color get brandDeep => _palette.deep;
  // Tint for selected and brand-highlight surfaces.
  static Color get brandTint => _palette.tint;
  // Cool grey page so white cards stand out from it.
  static const pageBackground = Color(0xFFEDF1F5);
  static const ink = Color(0xFF16222E);
  static const inkMuted = Color(0xFF475766);
  // Visible card and panel edges on both white and the page.
  static const border = Color(0xFFD3DBE4);
  static const borderStrong = Color(0xFF93A3B2);
  static const neutralContainer = Color(0xFFEDF1F5);
  // Reserved for AI-generated feedback so it is always recognizable.
  static const ai = Color(0xFF5B46C2);
  static const aiContainer = Color(0xFFEEEAFB);
  static const success = Color(0xFF18794E);
  static const successContainer = Color(0xFFE7F6ED);
  static const performanceLow = Color(0xFFC62828);
  static const performanceMid = Color(0xFF9A5A00);
  static const warningContainer = Color(0xFFFFF3DA);
  static const resultsSurface = Color(0xFFE9F2F6);
  static const resultsHeader = Color(0xFFD5E8F0);
  static const learningSurface = Color(0xFFF0F8F7);
  static const practiceSurface = Color(0xFFFFF5E6);
  static const insightSurface = Color(0xFFF5F2FC);
}

/// A plain page behind the work, so white cards read as separate layers.
class LearningBackdrop extends StatelessWidget {
  const LearningBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.pageBackground,
        child: child,
      );
}

/// Cards are white on the grey page; colour is kept for accents and status.
Color learningCardSurface(int index) => Colors.white;

Color performanceColor(num percentage) {
  final normalized = (percentage.toDouble().clamp(0, 100)) / 100;
  if (normalized <= 0.5) {
    return Color.lerp(
      AppColors.performanceLow,
      AppColors.performanceMid,
      normalized * 2,
    )!;
  }
  return Color.lerp(
    AppColors.performanceMid,
    AppColors.success,
    (normalized - 0.5) * 2,
  )!;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadii {
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// Two-layer elevation for raised cards and panels: a tight contact shadow
/// that defines the edge, and a soft one that lifts the card off the page.
const appCardShadow = [
  BoxShadow(
    color: Color(0x1416222E),
    blurRadius: 2,
    offset: Offset(0, 1),
  ),
  BoxShadow(
    color: Color(0x0F16222E),
    blurRadius: 16,
    offset: Offset(0, 6),
  ),
];

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    // Explicit tints replace the generated light cyan so every highlight
    // reads as the same teal brand.
    primaryContainer: AppColors.brandTint,
    onPrimaryContainer: AppColors.brandDeep,
    secondary: const Color(0xFF3D5A73),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFE3EBF2),
    onSecondaryContainer: const Color(0xFF1C3347),
    tertiary: AppColors.ai,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.aiContainer,
    onTertiaryContainer: const Color(0xFF2B1F6B),
    surface: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF7F9FB),
    surfaceContainer: const Color(0xFFF1F4F7),
    surfaceContainerHigh: AppColors.neutralContainer,
    surfaceContainerHighest: const Color(0xFFE4E9EF),
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    surfaceTint: Colors.transparent,
    error: AppColors.performanceLow,
    onError: Colors.white,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
  final text = base.textTheme;
  final textTheme = text.copyWith(
    displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.ink),
    headlineLarge: text.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.ink),
    headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.ink),
    headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink),
    titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.ink),
    titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.ink),
    titleSmall: text.titleSmall?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.ink),
    bodyLarge: text.bodyLarge?.copyWith(height: 1.55),
    bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
    bodySmall: text.bodySmall?.copyWith(fontSize: 14, height: 1.45),
    labelLarge:
        text.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium:
        text.labelMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    labelSmall: text.labelSmall?.copyWith(fontSize: 13, letterSpacing: 0.2),
  );
  final roundedSmall = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.sm),
  );

  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.pageBackground,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: Colors.white,
      backgroundColor: AppColors.brandDark,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      // A border plus a light shadow keeps every card's edge visible.
      elevation: 1.5,
      shadowColor: const Color(0x3316222E),
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.inkMuted,
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle:
          textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
      shape: roundedSmall,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: AppColors.brandTint,
      side: BorderSide.none,
      labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.ink),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: const StadiumBorder(),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      extendedTextStyle: TextStyle(fontWeight: FontWeight.w700),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      titleTextStyle: textTheme.headlineSmall?.copyWith(fontSize: 22),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandDeep,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: Colors.white, height: 1.4),
      actionTextColor: const Color(0xFF9FE3EF),
      shape: roundedSmall,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      elevation: 6,
      shape: roundedSmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.borderStrong,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brand
            : colorScheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brand
            : AppColors.borderStrong,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.brand,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        shape: roundedSmall,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.brandDark,
      unselectedLabelColor: AppColors.inkMuted,
      indicatorColor: AppColors.brand,
      labelStyle: textTheme.labelLarge,
      dividerColor: AppColors.border,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: AppColors.brandTint,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brand,
        shape: roundedSmall,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.brand,
      linearMinHeight: 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      // Keep the code editor's own light/dark background intact.
      filled: false,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.brand, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: AppColors.brandDark,
        side: const BorderSide(color: AppColors.borderStrong),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: BoxDecoration(
        color: AppColors.brandDark,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(colorScheme.surfaceContainerLow),
      headingTextStyle:
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w700),
      horizontalMargin: 16,
      columnSpacing: 24,
    ),
  );

  return theme;
}

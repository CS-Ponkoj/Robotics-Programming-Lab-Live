import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brandDark = Color(0xFF0F4C5C);
  static const brand = Color(0xFF19778C);
  static const pageBackground = Color(0xFFF4F7F9);
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

/// Quiet color around the work, while keeping text and code surfaces readable.
class LearningBackdrop extends StatelessWidget {
  const LearningBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.learningSurface,
              AppColors.pageBackground,
              AppColors.insightSurface
            ],
          ),
        ),
        child: child,
      );
}

Color learningCardSurface(int index) => switch (index % 3) {
      0 => AppColors.learningSurface,
      1 => AppColors.practiceSurface,
      _ => AppColors.insightSurface,
    };

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
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: const Color(0xFF1D2935),
    onSurfaceVariant: const Color(0xFF425466),
    error: AppColors.performanceLow,
    onError: Colors.white,
  );

  final theme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.pageBackground,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      foregroundColor: Colors.white,
      backgroundColor: AppColors.brandDark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
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
    progressIndicatorTheme: const ProgressIndicatorThemeData(
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
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 350),
      textStyle: TextStyle(color: Colors.white, fontSize: 13),
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

  return theme.copyWith(
    textTheme: theme.textTheme.copyWith(
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall:
          theme.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.45),
      labelSmall: theme.textTheme.labelSmall?.copyWith(fontSize: 13),
    ),
  );
}

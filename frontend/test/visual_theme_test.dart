import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('learning surface tints keep body text readable', () {
    final scheme = buildAppTheme().colorScheme;
    for (final background in [
      AppColors.learningSurface,
      AppColors.practiceSurface,
      AppColors.insightSurface
    ]) {
      expect(contrast(scheme.onSurface, background), greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.onSurfaceVariant, background),
          greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.primary, background), greaterThanOrEqualTo(4.5));
    }
  });
  test('form theme does not paint over the code editor background', () {
    expect(buildAppTheme().inputDecorationTheme.filled, isFalse);
  });
  test('shared text and status colors meet normal-text contrast', () {
    final scheme = buildAppTheme().colorScheme;
    expect(
        contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5));
    expect(
        contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.performanceMid, AppColors.warningContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.success, AppColors.successContainer),
        greaterThanOrEqualTo(4.5));
    // Brand-tint highlights and AI-feedback labels must stay readable.
    expect(contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.brandDark, AppColors.brandTint),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.ai, AppColors.aiContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.ai, scheme.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(scheme.onTertiaryContainer, scheme.tertiaryContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThanOrEqualTo(4.5));
    expect(contrast(AppColors.inkMuted, AppColors.neutralContainer),
        greaterThanOrEqualTo(4.5));
    for (var score = 0; score <= 100; score++) {
      final foreground = performanceColor(score);
      final badge =
          Color.alphaBlend(foreground.withValues(alpha: .12), Colors.white);
      expect(contrast(foreground, badge), greaterThanOrEqualTo(4.5),
          reason: 'Score $score');
    }
  });
}

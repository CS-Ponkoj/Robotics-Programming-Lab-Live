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
    for (var score = 0; score <= 100; score++) {
      final foreground = performanceColor(score);
      final badge =
          Color.alphaBlend(foreground.withValues(alpha: .12), Colors.white);
      expect(contrast(foreground, badge), greaterThanOrEqualTo(4.5),
          reason: 'Score $score');
    }
  });
}

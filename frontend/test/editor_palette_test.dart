import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iuse_demo/theme/app_theme.dart';
import 'package:iuse_demo/theme/editor_palette.dart';

double contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance < secondLuminance ? firstLuminance : secondLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('secondary interface text is readable on white cards', () {
    final colors = buildAppTheme().colorScheme;
    expect(
      contrastRatio(colors.onSurfaceVariant, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final palette in [EditorPalette.dark, EditorPalette.light]) {
    test('editor colors meet normal-text contrast in ${palette.background}',
        () {
      for (final entry in palette.styles.entries) {
        final color = entry.value.color;
        if (color != null) {
          expect(
            contrastRatio(color, palette.background),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} must remain readable in the editor',
          );
        }
      }
      expect(
        contrastRatio(palette.lineNumber, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(palette.foreground, palette.selection),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}

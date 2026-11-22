import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Shared building blocks so every screen draws cards, pills, numbers and
/// section titles the same way: white surfaces with a visible edge on the
/// grey page, and colour kept for status.

/// The standard card box: white, a visible border and a light shadow.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.borderColor,
    this.color,
    this.radius = AppRadii.lg,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Use a status colour here (for example success) to mark a finished item.
  final Color? borderColor;
  final Color? color;
  final double radius;

  /// Flat surfaces sit inside another card and need no shadow.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: elevated ? appCardShadow : null,
      ),
      child: child,
    );
  }
}

/// A card with a header row (icon, title, subtitle, actions on the right),
/// a body, and an optional footer strip, like an editor's panel.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.actions = const [],
    this.footer,
    this.bodyPadding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? footer;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSurface(
      margin: margin,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: PanelTitleRow(
                title: title,
                icon: icon,
                subtitle: subtitle,
                actions: actions,
              ),
            ),
            const Divider(height: 1),
            Padding(padding: bodyPadding, child: child),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: const Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    child: footer!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One compact header line for a panel, as in a code editor or dashboard:
/// a plain coloured icon, the title, a muted one-line description after it,
/// and the panel's actions on the right.
class PanelTitleRow extends StatelessWidget {
  const PanelTitleRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.actions = const [],
    this.minHeight = 36,
    this.fillTitle = false,
  });

  /// Keep the title at its full width and leave the space to [actions]
  /// (one of which should be Expanded).
  final bool fillTitle;

  final String title;
  final IconData? icon;
  final String? subtitle;
  final List<Widget> actions;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
          ],
          Flexible(
            fit: FlexFit.loose,
            flex: fillTitle ? 0 : 1,
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ] else if (!fillTitle)
            const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// A small rounded square holding an icon, used in headers and stat tiles.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size = 36,
    this.color,
    this.background,
  });

  final IconData icon;
  final double size;

  /// Defaults follow the account's brand colours.
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? AppColors.brandTint,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? AppColors.brandDark),
    );
  }
}

enum PillSize { small, medium }

/// A rounded status label: tinted background, a thin border in the same
/// colour, and an optional icon or dot. [solid] fills it with the colour.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
    this.solid = false,
    this.size = PillSize.medium,
    this.background,
    this.textColor,
  });

  final String label;

  /// The status colour: text, icon, dot and border use it.
  final Color color;
  final IconData? icon;
  final bool dot;
  final bool solid;
  final PillSize size;

  /// Overrides the tinted background, for pills that keep a theme container.
  final Color? background;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = size == PillSize.small;
    final foreground = textColor ?? (solid ? Colors.white : color);
    final fill = background ??
        (solid
            ? color
            : Color.alphaBlend(color.withValues(alpha: 0.10), Colors.white));
    final style = (small ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
        ?.copyWith(color: foreground, fontWeight: FontWeight.w700);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: solid ? color : color.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
            ),
            SizedBox(width: small ? 5 : 6),
          ] else if (icon != null) ...[
            Icon(icon, size: small ? 13 : 15, color: foreground),
            SizedBox(width: small ? 4 : 6),
          ],
          Flexible(
            child: Text(
              label,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One number with its label, such as a reading or a score. Digits keep a
/// fixed width so a changing value does not shift the layout.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.unit,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A tile fills the width it is given (for example a grid cell), so the
    // tiles in a row line up instead of shrinking to their text.
    return LayoutBuilder(
      builder: (context, outer) => SizedBox(
        width: outer.hasBoundedWidth ? outer.maxWidth : null,
        child: _tile(theme),
      ),
    );
  }

  // Dashboard style: a small capitalised label with its icon on top, then
  // the value large, with its unit muted beside it. One label line keeps
  // every tile in a row the same height.
  Widget _tile(ThemeData theme) {
    final scheme = theme.colorScheme;
    return AppSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Semantics(
        label: unit == null ? '$label: $value' : '$label: $value $unit',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section title with an optional one-line explanation and actions.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.prominent = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// A page title rather than a section title: one size larger.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: prominent
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleLarge,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// The last tile of a list that opens its earlier ("old") items.
class OldCollectionTile extends StatelessWidget {
  const OldCollectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.borderStrong, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                IconTile(icon: icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns from an "old" list to the current one.
class BackToCurrentLink extends StatelessWidget {
  const BackToCurrentLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
          label: Text(label),
        ),
      );
}

/// One tab of a [PillTabBar].
class PillTabData {
  const PillTabData({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Key? key;
}

/// A row of rounded tabs in a white track; the selected one is filled with
/// the brand gradient. [compact] draws smaller tabs without the track, for
/// a second level such as Exercise 1, 2, 3.
class PillTabBar extends StatelessWidget {
  const PillTabBar({super.key, required this.tabs, this.compact = false});

  final List<PillTabData> tabs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final wrap = Wrap(
      spacing: compact ? 8 : 4,
      runSpacing: compact ? 8 : 4,
      children: [for (final tab in tabs) _PillTab(tab: tab, compact: compact)],
    );
    if (compact) return wrap;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl + 4),
        border: Border.all(color: AppColors.border),
        boxShadow: appCardShadow,
      ),
      child: wrap,
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.tab, required this.compact});

  final PillTabData tab;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = tab.selected;
    final Color fg;
    final BoxDecoration decoration;
    if (compact) {
      fg = selected ? AppColors.brandDeep : AppColors.ink;
      decoration = BoxDecoration(
        color: selected ? AppColors.brandTint : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: selected ? AppColors.brand : AppColors.border,
        ),
      );
    } else {
      fg = selected ? Colors.white : AppColors.ink;
      decoration = BoxDecoration(
        gradient: selected ? AppColors.brandGradient : null,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      );
    }
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: tab.key,
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: tab.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14, vertical: compact ? 6 : 8),
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.icon != null) ...[
                  Icon(tab.icon,
                      size: 17,
                      color: selected && !compact ? Colors.white : fg),
                  const SizedBox(width: 7),
                ],
                Text(tab.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice of a multiple-choice question: a rounded tile with a letter
/// badge that fills with the brand colour when chosen.
class AnswerOption extends StatelessWidget {
  const AnswerOption({
    super.key,
    required this.letter,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;

  /// Null while the answer cannot change (for example while submitting).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: onTap != null,
        label: '$letter. $text',
        excludeSemantics: true,
        child: Material(
          color: selected ? AppColors.brandTint : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.brand : Colors.white,
                      border: Border.all(
                        color: selected ? AppColors.brand : AppColors.borderStrong,
                      ),
                    ),
                    child: Text(
                      letter,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected ? Colors.white : AppColors.inkMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.ink,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A score as a ring that fills to the percentage, with the number inside.
/// The fill animates in once unless the platform asks for reduced motion.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    required this.color,
    this.size = 72,
    this.stroke = 7,
    this.label,
  });

  /// 0 to 100.
  final int score;
  final Color color;
  final double size;
  final double stroke;

  /// Optional small caption under the number, such as "score".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = score.clamp(0, 100) / 100;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion ? target : 0, end: target),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            value: value,
            color: color,
            track: color.withValues(alpha: 0.14),
            stroke: stroke,
          ),
          child: child,
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '$score%',
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                height: 1,
                fontSize: size * 0.26,
              ),
            ),
            if (label != null)
              Text(
                label!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.inkMuted,
                  fontSize: size * 0.13,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 6.283185307179586, false, base);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -1.5707963267948966, 6.283185307179586 * value, false,
        arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

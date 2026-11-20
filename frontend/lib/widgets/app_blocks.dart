import 'package:flutter/material.dart';
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
    this.radius = AppRadii.md,
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
        borderRadius: BorderRadius.circular(AppRadii.md - 1),
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
  });

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
          ] else
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

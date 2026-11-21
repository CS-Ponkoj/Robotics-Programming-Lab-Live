import 'package:flutter/material.dart';
import 'package:iuse_demo/theme/app_theme.dart';

/// Draws any [AppBar] as a compact, floating, rounded brand card on the page
/// colour, so every page shares the home header's look.
class FloatingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FloatingAppBar(this.bar, {super.key, this.barHeight = 56});

  /// The page's own bar: title, leading, and actions stay unchanged.
  final AppBar bar;

  /// Height of the card itself.
  final double barHeight;

  static const double _top = 10;
  static const double _bottom = 8;

  @override
  Size get preferredSize => Size.fromHeight(barHeight + _top + _bottom);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final side = compact ? 8.0 : 16.0;
    return ColoredBox(
      color: AppColors.pageBackground,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, _top, side, _bottom),
          child: FloatingHeaderCard(
            child: SizedBox(
              height: barHeight,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: bar,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rounded brand-gradient card behind a floating header.
class FloatingHeaderCard extends StatelessWidget {
  const FloatingHeaderCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Depending on the theme rebuilds this when the account's palette changes.
    Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandDeep.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          const BoxShadow(
            color: Color(0x1416222E),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: child,
      ),
    );
  }
}
